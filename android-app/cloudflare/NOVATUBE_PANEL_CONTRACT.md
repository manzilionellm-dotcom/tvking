# NovaTube — contrat du pont Atlas

État : candidat local du 14 novembre 2026. Aucun déploiement ni activation réelle ne fait partie de cette validation.

Le pont relie l’application `com.manthefew` à l’application Atlas `app_novatube4k`. Les noms et logos affichés dans l’APK restent sous le contrôle de l’APK. Les identifiants techniques du contrat ne sont pas des libellés à afficher.

## Baseline conservée

La release précédente 317 a été produite depuis le bundle historique `gold.js` dont le SHA-256 est `6788284148b1bfb451a63fadf2953f3e2c0713c36155fbf7c1889e3763363bce`. Le script `prepare_novatube4k_release.py` exige cette empreinte, ajoute uniquement des exports de fonctions déjà présentes, puis place les nouveaux modules autour du Worker original. Il vérifie que le retrait de ces exports restitue exactement le bundle initial. Aucun corps de fonction historique n’est réécrit.

Le candidat est préparé dans un répertoire distinct. Les quatre fichiers de preuve de la release 317 restent conservés. Les paramètres Workers restent `compatibility_date = 2025-05-01`, sans nouveau flag de compatibilité. `RealtimeHub` reste la même classe Durable Object et la même migration.

## Options réellement présentes dans le panel

L’inventaire provient de `admin-panel/src/App.tsx`, `components/Sidebar.tsx`, `lib/api.ts` et des pages concernées. Les autorisations du serveur restent déterminantes ; une option visible n’accorde pas un droit supplémentaire.

| Page / option | Route ou stockage du panel | Effet dans ce pont |
|---|---|---|
| Tableau de bord `/` | `/api/v1/stats/overview` | Fiches et licences déjà enregistrées dans les mêmes tables. Pas de statistique synthétique ajoutée. |
| Activation `/activate` | `POST /api/v1/activate` | Une MAC NOVATUBE inscrite force `app_id=app_novatube4k`, puis passe par les contrôles historiques JWT, origine, revendeur, crédit et idempotence. Aucun hook Gold. |
| Appareils `/devices` | `/api/v1/devices`, fiche et aperçu | Présence, modèle, version, plateforme, inventaire expurgé, gel, bannissement, reprise et suppression utilisent les tables existantes. |
| Activations `/activations` | `/api/v1/licenses`, renouvellement et statut | `state` relit la licence dédiée. Les ordres `activate`, `renew`, `suspend`, `resume`, `expire`, `block` et `license` provoquent une relecture. |
| Clients `/customers` | `/api/v1/customers` | Gestion administrative existante. Aucune identité d’installation créée ou déplacée par un appel appareil. |
| Chaînes `/chaines` | `/api/v1/sources/:mac` | Publication, remplacement, désactivation, suppression, révisions et retour arrière restent historiques. `state` fournit les sources après autorisation ; `/ack` confirme leur enregistrement réel. Le formulaire du panel est M3U ; l’APK accepte aussi Xtream. |
| Transfert `/transfer` | `POST /api/v1/transfer` | Adaptateur atomique pour deux installations NOVATUBE inscrites, détaillé ci-dessous. Autres MAC : route historique inchangée. |
| Familles `/families` | `/api/v1/families` | Consultation et suppressions historiques conservées. La baseline interdit déjà création de famille, ajout de membre et création de lien ; le pont ne réactive pas ces actions. |
| En ligne `/online` | `/api/v1/online`, `presence` | Présence authentifiée, pays/IP serveur et chaîne observée. Aucun score de qualité inventé. |
| Analyses `/insights` | `GET /api/v1/insights` | Route absente du bundle 317 ajoutée avec le module de lecture existant, authentification originale et rôle `super_admin`. L’enrôlement inactive/custom/0 n’est pas une vente. |
| Boîte noire `/blackbox` | `/api/v1/blackbox/:mac`, `/ask` | Demande d’envoi, réveil du client, journal filtré, date de réception et lecture par l’admin/revendeur autorisé. |
| Suivi des ordres et latence | `/api/v1/orders`, `/timeline`, `/metrics/latency` | Les mêmes tables `box_orders` et `source_revisions` reçoivent les vrais reçus et résultats. Aucune confirmation de lecture vidéo n’est fabriquée. |
| Notifications `/notifications` | `/api/v1/announcements`, paramètres, activation/suppression | Annonces et file `pending` servies dans `/panel`. L’ID lu est mémorisé après affichage réel par le client. |
| Gestion accueil `/home-manager` | `/api/v1/home-layout`, historique/restauration | Configuration transportée sans traduction arbitraire. Les clés historiques ne correspondent pas au carrousel natif 4K : `unsupported` tant qu’aucun rendu compatible n’existe. |
| Favori du jour `/featured` | `POST /api/v1/featured` | `name` et `note` transmis au rendu Android ; pas de changement de catalogue fournisseur. |
| Thème et automatisations `/theme` | `/api/v1/theme?platform=tv`, `/automations` | Valeurs effectivement calculées par Atlas. Portée plateforme, pas application. Accent/fond applicables aux menus ; nom/logo NovaTube conservés par Android. |
| Publicité `/ad` | `/api/v1/ad` | Configuration `enabled,url,skip,freq` transmise. Le client décide du rendu et du consentement ; aucune confirmation « appliqué » avant rendu réel. |
| Tarifs `/tarifs` | `/api/v1/pricing`, `/plan-costs` | Informations de tarifs, promotions et lien de paiement transmises. L’affichage d’un prix ou d’un essai ne crée aucune licence. Les coûts revendeurs restent dans le serveur historique. |
| Ajouter des jours à une MAC | `POST /api/v1/trial-extend` | Adaptateur NOVATUBE uniquement pour un essai déjà accordé, actif ou expiré. Enrôlement et abonnement payé refusés sans modification. |
| « + jours à tous » | `POST /api/v1/grant-trial-all` | Sémantique historique intégralement conservée : porte les licences actives à expiration finie et trop courte à au moins maintenant + N jours. Peut inclure un abonnement payé court ; ne touche ni `inactive/custom/0`, ni les durées déjà supérieures, ni les licences à vie. |
| Avis `/reviews` | `/api/v1/feedback-prompt`, `/api/v1/feedback` | Invitation et envoi d’un vrai avis par le pont authentifié ; note 0 à 5, MAC imposée par la clé. |
| Serveurs `/servers` | `/api/v1/servers` | Liste informative de serveurs transmise. Aucun compte fournisseur ni abonnement créé automatiquement. |
| Mise à jour `/force-update` | `/api/v1/force-update?platform=tv` | Seuils temporels de la plateforme TV transmis. URL de téléchargement remplacée uniquement dans la réponse dédiée par `https://novatube4k-apk.vercel.app/`. Installation avec l’interface système Android. |
| Applications `/apps` | `/api/v1/apps` | `is_active` de `app_novatube4k` participe au droit d’accès. Métadonnées et autres applications restent gérées par le panel. |
| Revendeurs `/resellers` | Comptes, permissions, soldes | Authentification, propriété et crédits existants conservés. Aucun crédit ou achat Strong/Gold lors d’une télémétrie, d’un transfert ou d’une prolongation manuelle d’essai. |
| Références `/references` et historique `/history` | Références d’activation, audit | Les opérations utilisent le journal existant ; ces pages ne sont pas l’historique de lecture TV. |
| Compte `/account` | Mot de passe, 2FA, sessions, export admin | Logique existante inchangée. L’export administrateur de base est distinct du backup applicatif par appareil. |
| Centre de contrôle `/control-center` | Liens vers modules | Les raccourcis actifs restent ceux du panel. « Bannières » et « A/B Testing » sont marqués « Bientôt », sans action active à connecter. |

Alias existants : `/activation-distance` mène à `/activate`, `/playlists` mène à `/chaines`.

## Authentification et droit d’accès

Toutes les routes appareil dédiées sont des `POST /api/novatube4k/<action>` avec `X-Device-Key` et `raw_mac` dans le JSON. La clé de 32 octets est propre à l’installation ; seule son empreinte SHA-256 est en D1. Elle ne figure jamais dans un journal, une réponse ou un backup applicatif.

L’appareil affiche sa MAC Atlas `MK:…` pour les opérations du panel. Le `raw_mac` est un identifiant technique interne, pas un code supplémentaire à demander au client. Le serveur impose la MAC liée à la clé ; un champ `mac` fourni par le client ne change jamais la destination d’une présence, d’un journal, d’un avis ou d’un ACK.

`register` crée une fiche et une licence dédiée inactive, `plan=custom`, `expires_at=0`. Il n’accorde aucun essai. `state` reste l’autorité pour l’accès et les sources. `panel` ne prolonge jamais une autorisation : il peut fournir diagnostics et réglages à un appareil enregistré mais inactif. Historique de lecture et backup exigent en plus une licence active.

Les anciennes routes appareil basées seulement sur une MAC restent fermées pour les MAC NOVATUBE. Les sous-appels aux handlers historiques sont internes au Worker, après vérification de clé ; ils ne rouvrent pas ces routes au public.

## Contrat appareil

| Action | Corps en plus de `raw_mac` | Réponse / limite |
|---|---|---|
| `register`, `state`, `ack` | Contrat de la release 317 conservé | Sources seulement sous licence ; IDs stables ; ACK de révision servie. |
| `panel` | Plateforme, version, timestamp de build UTC en secondes, métadonnées, inventaire expurgé, chaîne réelle, `announcements_after`, `config_etag` | 16 Kio. Présence, commandes, signaux et configuration. |
| `blackbox` | `text` | 256 Kio en entrée JSON ; handler historique conserve au plus 32 Kio UTF-8. `{ok:true,updated_at}` après stockage ; `skipped:true` si vide. |
| `orders-ack` | `orders:[{order_id,state,…}]`, au plus 20 | 24 Kio. Un résultat HTTP par élément dans `results`. `state` vaut `received`, `applied` ou `failed`. |
| `wait` | `after` entier, `timeout` de 200 à 20 000 ms | 4 Kio. Réponse de RealtimeHub `{v,timeout,box,events,fleet:[]}`. 503 si RT désactivé ou absent. |
| `rt-ticket` | Aucun autre champ requis | Ticket à usage unique de 60 secondes du DO historique. Facultatif : Android peut utiliser seulement `wait`. |
| `feedback` | `rating` entier 0..5, `message` non vide | 12 Kio ; message limité à 2 000 caractères et filtré ; `{ok:true}`. |
| `history` | Aucun autre champ requis | `{mac,recent}` sous licence active. |
| `backup` | `op:"get"` ou `op:"put", data:{…}` | 512 Kio en entrée ; objet sérialisé de 256 Kio maximum. Clés d’installation interdites, même imbriquées. |

Les endpoints de backup/historique existent pour l’intégration Android. Leur présence serveur ne signifie pas qu’un bouton de restauration ou la synchronisation des favoris natifs est déjà implémenté dans l’APK.

### Réponse de `panel`

```json
{
  "ok": true,
  "app_id": "app_novatube4k",
  "mac": "MK:11:22:33:44:55",
  "server_now": 1800000000000,
  "telemetry_ok": true,
  "commands_ok": true,
  "commands": [],
  "reset_at": 0,
  "blackbox_pull": 0,
  "signal_errors": [],
  "config_scope": "platform",
  "config_etag": "empreinte SHA-256",
  "config_unchanged": false,
  "config_errors": [],
  "config": {}
}
```

Tous les timestamps de serveur et d’ordres sont en millisecondes. `appBuild`, `minBuildTs` et `latestBuildTs` sont des timestamps UTC en **secondes**, jamais un `versionCode` Android. Le pont ne passe pas `?build=` au handler historique de version : un build NovaTube ne doit pas relever le compteur Flutter partagé.

`config` est absent si l’empreinte est inchangée. Un module en échec est absent et son nom apparaît dans `config_errors` : le client conserve sa précédente valeur. Un objet présent mais vide exprime la valeur vide réelle, sans être confondu avec une erreur réseau.

| Clé de configuration | Format historique servi |
|---|---|
| `announcements` | `{id,title,body,url,kind,cta,pending:[…]}` ou `{}` |
| `home` | `{items:[{key,position,enabled,ribbon,featured}],version}` |
| `theme` | `{appName,accent,bg}` ; `bg` vaut `dark`, `light` ou vide |
| `featured` | `{name,note}` |
| `ad` | `{enabled,url,skip,freq}` ; fréquence `daily` ou `always` |
| `pricing` | Tarifs, devise, essai affiché, promotion et textes du handler existant |
| `feedback` | `{enabled,message}` |
| `servers` | `{servers:[{id,label,url}]}` |
| `app_version` | `{minBuildTs,latestBuildTs,download_url}` |

Les réponses de configuration terminées sont mémorisées deux secondes au maximum, par plateforme, pays, curseur d’annonces et révision. Une mutation du panel invalide le cache. Aucun objet Request, promesse ou requête en cours n’est mémorisé entre requêtes Workers.

### Présence et inventaire

La présence utilise le handler existant sans appeler le heartbeat public, qui a d’autres effets sur les essais. L’IP et le pays proviennent des en-têtes Cloudflare. `quality` est un score de mesure facultatif : valeur absente = `null`. La résolution vidéo et les paramètres des lecteurs ne sont pas changés.

L’inventaire contient au plus cinq sources : type, nom de présentation filtré, état sélectionné, origine serveur seule si fournie et nombre de chaînes seulement s’il est connu. Nom de compte, mot de passe, chemin et query fournisseur sont absents. Un nombre inconnu vaut `null`, affiché « — » par le panel. Un historique vide envoyé est réellement vidé. Une lecture `state` rapprochée n’efface pas la chaîne fraîchement remontée par `panel`.

### Ordres, ACK et réinitialisation

Les kinds existants sont : `source`, `source_clear`, `activate`, `renew`, `expire`, `suspend`, `resume`, `block`, `license`, `transfer`, `device_delete`, `message`, `theme`, `home`, `force_update`, `featured`, `ad`, `pricing`, `feedback`, `servers`, `banner`, `reset`.

Il n’existe pas de commande de redémarrage système, lecture arbitraire, pause ou changement de chaîne à inventer. Les ordres transportent des identifiants et une révision, pas des secrets ni un contenu fournisseur.

Le serveur livre au plus 50 ordres non terminaux, les plus récents en premier. Cela empêche de vieux ordres source sans ACK d’empêcher la remise d’une révocation récente. Il conserve la preuve de livraison par MAC. Un ACK d’un ordre jamais remis à cette MAC est refusé. La révision et le trace ID sont relus dans l’ordre stocké, pas acceptés depuis le client.

`orders-ack` peut répondre HTTP 200 avec certains éléments refusés : seul le `status` de chaque `order_id` confirme son traitement. `source` et `source_clear` ne peuvent pas devenir `applied` par ce raccourci ; le client utilise `/ack` après réception et sauvegarde de la révision courante. Un rendu non implémenté renvoie `failed/unsupported`, pas `applied`.

`reset_at` est le timestamp persistant du clic de remise à neuf. Le bouton historique annonce l’effacement des listes panel/client et des données TV (chaînes, favoris, historique, guide), en conservant la licence. Le contrôleur Android doit enregistrer ce timestamp seulement après l’effet réel et conserver clé d’installation et MAC. Un ordre peut avoir un `created_at` légèrement supérieur à `reset_at` : l’ACK doit se rattacher au `reset_at` servi avec l’ordre.

### Réveil et boîte noire

`wait` rejoint directement la boîte aux lettres du DO nommée par la MAC authentifiée. Le client utilise un repli de polling lorsque le temps réel est indisponible. Après une mutation globale réussie, les seules NOVATUBE vues depuis moins de 120 secondes sont réveillées, par lots, jusqu’à 1 000 appareils par action. Le polling continue à couvrir les appareils non réveillés.

Les mutations concernées sont annonces, thème/automatisations, accueil/restauration, favori du jour, pub, tarifs, avis, serveurs, politique de mise à jour et prolongation globale. `/blackbox/:mac/ask` réveille uniquement la NOVATUBE visée. Le signal ne porte ni texte libre ni secret et ne crée aucun ACK fictif.

Le journal est filtré à la fois par le client, par le pont et par le handler historique : URLs, comptes, mots de passe, tokens, clé d’installation, empreintes et identité brute ne sont pas conservés. Le client mémorise `blackbox_pull` après confirmation d’enregistrement ; le timestamp de demande n’est pas remis à zéro côté serveur.

## Transfert et ajout manuel de jours

### Transfert

Les deux MAC doivent être des installations NOVATUBE inscrites. La source doit posséder une seule licence NOVATUBE non vierge ; la destination doit posséder uniquement sa licence d’enrôlement inactive/custom/0. Une destination déjà payée ou active, un transfert entre applications ou un propriétaire revendeur incompatible est refusé. JWT/session/origine sont contrôlés par le Worker original ; l’administrateur ou un revendeur ayant le droit `activate` est requis.

Une transaction D1 unique vérifie les versions et préconditions, remplace la licence vierge de destination, déplace la licence en conservant plan et expiration, déplace les listes déjà chiffrées, publie des révisions, ajoute les tombstones, invalide les anciennes preuves de révision et écrit l’audit. Une course concurrente ou une panne de ces écritures annule le lot. Un deuxième transfert identique retourne un conflit, sans double action. Aucun crédit n’est débité et aucun service Gold/Strong n’est appelé.

Les deux `device_id`, clés et identités d’installation restent intacts. La destination reprend le client et, si nécessaire, le revendeur de la source. Le blocage de la source est conservé sur la destination afin que le transfert ne contourne pas une suspension. Le réveil/ordre suit le commit ; une indisponibilité du temps réel n’annule pas une transaction déjà engagée.

### Ajouter des jours d’essai

Pour une MAC NOVATUBE, `trial-extend` exige un plan `trial`, `trial7`, `trial30` ou autre suffixe numérique, avec expiration finie positive et statut actif ou expiré. La nouvelle fin est `max(fin actuelle, maintenant) + N jours`. Le plan est préservé, le statut redevient actif si l’essai était expiré ; un blocage appareil reste un blocage. Licence, journal d’extension et audit sont engagés ensemble.

La route conserve l’authentification d’origine : JWT `super_admin`, ou secret administrateur valide pour cette route, avec contrôle de l’origine. Un enrôlement, une licence payée ou à vie n’est pas converti. Les anciennes MAC conservent le handler historique. Le bouton global `grant-trial-all` reste lui aussi historique, avec sa portée réelle décrite dans l’inventaire.

## Validation reproductible

Les tests utilisent uniquement des fixtures locales, des JWT éphémères et des adresses `.test`. Tous les fetch extérieurs sont interceptés et refusés. Les checks Android sont distincts de ces checks serveur.

```bash
python prepare_novatube4k_release.py --base /chemin/gold.js --out /chemin/panel-release
NOVATUBE4K_TEST_ENTRY=/chemin/panel-release/novatube4k-live-entry.js node --test novatube4k-panel.test.mjs novatube4k-wrapper.test.mjs
node --test novatube4k.test.mjs insights.test.mjs
node novatube4k-panel.workerd.mjs /chemin/panel-release/novatube4k-live-entry.js
```

Le jeu final couvre 23 scénarios nouveaux de panel, 14 scénarios d’intégration antérieurs, 27 tests de module/analyses et 18 étapes sur le vrai runtime Workerd avec D1/RealtimeHub locaux. Il vérifie notamment auth/origine/propriété, absence d’essai automatique, boîte noire, masquage des secrets, présence, configuration et etag, réveil sous deux secondes dans le runtime local, ACK partiels, source sous révision, reset, transfert atomique, course concurrente, rollback, essais manuels et isolation des anciennes MAC. Le nombre de requêtes réseau extérieures attendu est zéro.

Le manifeste `release-audit.json` contient l’empreinte de chaque module à téléverser. Avant un éventuel déploiement, il faut comparer la version de production à la baseline attendue et téléverser exactement le candidat validé, sans le recompiler depuis un autre état du dépôt.
