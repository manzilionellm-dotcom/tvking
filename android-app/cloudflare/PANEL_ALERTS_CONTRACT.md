# Alertes privées du propriétaire Atlas

Ce module ajoute une boîte de réception durable pour le rôle **`super_admin`**. La page existante « Notifications », ses annonces aux clients et les corps des fonctions du Worker historique restent inchangés. Le transport Web Push et son cron appartiennent au Worker isolé `panel-alert-dispatcher/` ; aucun cron n'est ajouté au Worker métier.

## Événements réellement observés

| Type API | Déclencheur | Signification et déduplication |
| --- | --- | --- |
| `new_device` | Insertion confirmée dans `devices` | Nouvelle fiche enregistrée dans Atlas, y compris un ajout administratif. Cela ne prouve pas que la box physique est en ligne. Une occurrence par identifiant de fiche. |
| `activation` | Insertion d'une licence active, passage à `active`, ou prolongation de son expiration | Activation ou prolongation effectivement enregistrée, sur toutes les routes, même sans `Idempotency-Key`. Un renouvellement ou une opération globale qui prolonge une licence active utilise le texte « Licence prolongée ». Une réactivation sans changement d'une licence lifetime déjà active ne crée pas de doublon. Ce type ne signifie pas nécessairement achat ou paiement. |
| `problem` | Demande de réassociation NovaTube `pending` valide | Vérification d'identité demandée, une occurrence par MAC et fenêtre UTC fixe de dix minutes. Aucun code d'assistance, hash ou MAC physique dans l'événement. Une alerte n'approuve jamais la réassociation. |
| `problem` | Commande avec `state='failed'` et `failed_srv` persisté | Échec de commande signalé dans les reçus. Le collecteur traite au maximum 200 lignes par passage, après le bootstrap et dans les dernières 24 heures, avec déduplication par `order_id`. Un état calculé `expired`, une commande en attente ou l'absence de polling ne suffit pas. |
| `problem` | Journal NovaTube authentifié accepté par le handler Boîte noire | Codes d'erreur fixes et récents d'authentification/import de source. Le journal, ses URL et ses noms de listes ne sont jamais recopiés dans l'alerte. |

Les triggers `AFTER` sur `devices`, `licenses` et les demandes de réassociation écrivent l'événement **dans la transaction métier**. Si elle échoue, l'événement est annulé avec elle. Leur installation ne rejoue pas les anciens appareils ou licences.

Il n'y a **aucun trigger sur `box_orders`** : `recordAck` historique utilise `D1Result.meta.changes === 1`, alors que D1 compte aussi les écritures des triggers. Le scan durable des reçus conserve donc les ACK et les confirmations/rejets de source d'origine. L'anti-jointure et la clé unique empêchent de perdre un commit tardif partageant le même timestamp.

### Limites des diagnostics

Le parseur exige l'en-tête exact du journal NovaTube, la MAC Atlas liée, la section UTC et une ligne complète datée. Les événements doivent avoir au plus dix minutes ; une avance d'horloge de plus de 60 secondes les exclut. Il accepte seulement `provider.reply_refused`, `provider.response_invalid`, `provider.http_auth` et les erreurs `source.import_invalid_url`, `source.import_local_unavailable`, `source.import_http_error`, `source.import_too_large`, `source.import_timeout`, `source.import_format`, `source.import_network`, `source.import_failed`.

Un succès ultérieur `xtream.authenticated` ou `m3u.catalogue_ready` supprime les erreurs précédentes du même journal avant collecte. Les annulations, le texte libre, les anciens journaux, les états du lecteur et une simple absence de réseau ne déclenchent pas d'alerte. Une horloge de box incorrecte peut donc empêcher la détection d'un incident réel. Le collecteur traite au plus cinq codes récents et déduplique par MAC, code et fenêtre UTC de dix minutes.

La collecte de journal suit un enregistrement Boîte noire réussi, après authentification `X-Device-Key`. Elle n'est pas dans la transaction du handler historique : si sa propre écriture échoue, la Boîte noire reste enregistrée et un téléversement ultérieur du journal encore récent peut réessayer. Ce lot n'ajoute pas de scan rétrospectif des journaux libres historiques.

## API et sessions

Préfixe : `/api/v1/panel-alerts`. Toutes les routes passent par le contrôle historique `/api/v1/auth/me`, puis exigent le rôle courant `super_admin` **et une session `sid` réelle**. Les JWT historiques sans session restent utilisables sur leurs anciennes routes mais pas sur cette API. Les réponses privées utilisent `Cache-Control: no-store, private`. Les origines et limites de débit existantes sont conservées ; les erreurs ne recopient ni corps privé ni détail SQL.

| Route | Contrat |
| --- | --- |
| `GET /preferences` | `{ok, enabled, types:{new_device,activation,problem}, push_available, public_key}`. Par défaut : compte désactivé, trois catégories activées. `public_key` est la clé publique VAPID valide, sinon `null`. |
| `PUT /preferences` | Corps complet obligatoire `{enabled:boolean, types:{new_device:boolean,activation:boolean,problem:boolean}}`. Les catégories supplémentaires et valeurs non booléennes sont refusées. |
| `GET /events?after=<seq>&limit=50` | `{ok, items, next_cursor, unread_count}`. Sans `after`, dernière page en ordre décroissant. Avec `after`, événements `seq > after` en ordre croissant. `limit` entre 1 et 100. Chaque item ajoute `seq`, `created_at`, `read_at` au payload ci-dessous. |
| `POST /read` | `{event_ids:[…]}`, entre 1 et 100 identifiants, puis `{ok,updated}`. Lecture propre à chaque compte, idempotente. |
| `GET /subscriptions` | `{ok,items:[{id,label,enabled,current_session,created_at,consented_at,expires_at,last_success_at,revoked_at,revoked_reason}]}`. Aucun endpoint, clé ou identifiant de session. |
| `POST /subscriptions` | Corps `{endpoint,keys:{p256dh,auth},expirationTime:null\|UTCms,label,permission:'granted',consent:true}` ; exige aussi les préférences du compte activées. Retour `{ok,id,enabled:true,delivery_confirmed:false,expires_at,consented_at}`. |
| `DELETE /subscriptions/:id` | Révoque uniquement une souscription du compte courant et annule ses livraisons encore en attente. Retour idempotent `{ok,id,enabled:false}` pour une ligne appartenant au compte. |

Tous les timestamps publics sont des entiers UTC en millisecondes. La lecture de l'inbox fonctionne sans consentement Push. Le consentement n'est pas une autorisation implicite d'afficher des notifications sur tous les navigateurs du compte.

### Souscriptions et consentement

La souscription est liée au compte et à la session qui l'a explicitement activée. Son expiration est le minimum entre la fin de cette session et celle annoncée par le navigateur, si présente. Une nouvelle connexion demande une réactivation explicite. Le nombre de souscriptions actives non expirées est limité atomiquement à cinq par compte. Une autre identité ne peut pas s'approprier un endpoint existant.

L'API vérifie la clé ECDH P-256 de 65 octets sur la courbe et le secret `auth` de 16 octets, en base64url canonique. Elle accepte seulement HTTPS et les chemins connus de FCM (`/fcm/send/…`, `/wp/…`), Mozilla (`/wpush/v2/…`) et Apple (`/Q…`). Pas d'URL arbitraire, identifiant dans l'URL, port non standard, query, fragment ou redirection. WNS n'est pas ajouté sans validation préalable de son contrat. Le transport répète ces contrôles.

Les endpoints et clés de souscription sont nécessaires à l'expédition et restent dans les tables privées D1. Ils ne sont jamais renvoyés par les listes API, écrits dans les audits métier, envoyés au Service Worker comme données applicatives ou inclus dans le payload. La clé VAPID **privée** appartient exclusivement aux secrets du dispatcher ; le Worker principal ne reçoit que `PANEL_PUSH_PUBLIC_KEY`.

L'activation du compte ou la réactivation d'une catégorie relève `enabled_at`. Le dispatcher n'expédie que les événements postérieurs à ce seuil et à `consented_at`. Il ne rattrape donc pas les alertes anciennes après un nouveau consentement. À chaque envoi, il vérifie encore le compte actif, son rôle, la session non supprimée/non expirée et l'absence de changement de mot de passe postérieur à sa création.

## Payload Push

```json
{
  "v": 1,
  "event_id": "pae_identifiant_aleatoire",
  "type": "problem",
  "title": "Commande en échec",
  "message": "Une commande de la box MK:11:22:33:44:55 est marquée en échec.",
  "url": "/blackbox?mac=MK:11:22:33:44:55"
}
```

Six propriétés exactement. `event_id` fait 8 à 128 caractères `[A-Za-z0-9_.:-]`, `title` 1 à 96, `message` au plus 240. L'URL, au plus 160 caractères, est relative et ne peut viser que `/devices?mac=…` ou `/blackbox?mac=…`, sans autre paramètre ni fragment. MAC autorisée : code Atlas `MK:…` ou six octets hexadécimaux séparés par `:`. Les textes sont fixes et ne contiennent aucune URL fournisseur, clé d'appareil, nom de source ou code de réassociation.

Le dispatcher utilise une livraison unique par événement/souscription et des leases. Ses états sont `pending`, `leased`, `retry`, `sent`, `failed`, `cancelled`. Un état `sent` signifie que le service Push a accepté la requête ; il ne prouve ni affichage ni lecture. Le navigateur déduplique encore par `event_id`. L'expédition est bornée aux événements des dernières 24 heures ; l'inbox reste durable et ne dépend pas de cette fenêtre. Aucun nettoyage d'historique n'est ajouté silencieusement dans ce lot.

## Bootstrap, livraison et vérifications

`node prepare_panel_alerts_migration.mjs <dossier>` produit `panel-alerts-migration.json` et `.sql`, avec les SHA256 des sources et de chaque instruction. Ce script ne contacte aucun service. Le plan comporte exactement 19 instructions : les deux `CREATE TABLE` recovery extraits de la fonction gelée, le schéma/index/meta des alertes, six triggers et l'index de scan des reçus en échec. La seule insertion immédiate est `panel_alert_meta(id=1,installed_at=heure D1)`, avec `OR IGNORE`.

Prérequis : tables métier de la version 318 présentes (`devices`, `licenses`, `box_orders`, `novatube4k_devices`). Appliquer le batch additif relu **avant** d'activer le nouveau Worker. Le rejouer est sûr et conserve le timestamp initial. Aucun `INSERT` d'appareil/licence/source, aucune licence réelle activée, aucun code d'assistance approuvé pendant cette migration.

`ensurePanelAlertsSchema` reste un filet de compatibilité pour les environnements de test et les tables optionnelles initialisées tardivement. La découverte incomplète est retentée après 30 secondes ; les demandes recovery encore récentes peuvent alors être rapprochées. Cette initialisation paresseuse ne remplace pas le bootstrap de production préalable, qui évite un intervalle sans triggers.

La préparation du Worker part du bundle historique à SHA attendu et n'ajoute que des exports internes et les modules propriétaires. La compatibilité reste `2025-05-01`, sans nouveau flag `nodejs_compat`. `panel-alerts.test.mjs` teste l'API, l'isolation, le consentement, les transactions et les diagnostics avec SQLite ; `panel-alerts.workerd.mjs` teste le candidat exact et la migration dans D1/Workerd, notamment les débits, l'idempotence et les ACK. Tous ces scénarios utilisent des identités locales et interdisent le réseau externe. Les tests de chiffrement et d'expédition interceptée appartiennent au dossier du dispatcher.

Les journaux de test et leurs empreintes constituent la preuve technique. Ils ne prouvent pas la livraison d'une notification sur un téléphone réel. La permission système, l'installation PWA et la réception effective devront être constatées sur le navigateur concerné après le déploiement approuvé et son opt-in.
