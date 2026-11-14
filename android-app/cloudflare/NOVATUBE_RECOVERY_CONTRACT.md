# NovaTube — réassociation après perte de clé

État de ce changement : candidat local, à relire avant déploiement. Les tests
utilisent uniquement des appareils, sessions et sources de fixture. Aucune
liaison ni licence réelle n'a été modifiée pour cette validation.

## But et portée

Une nouvelle installation peut conserver sa MAC Atlas tout en ayant perdu
sa clé privée, par exemple après effacement des données Android. Une MAC,
une adresse IP ou un modèle identique ne prouvent pas que la nouvelle clé
est autorisée. Le serveur continue à refuser `state` et les sources tant
qu'un administrateur n'a pas approuvé le code réellement affiché sur la box.

La fonction s'applique exclusivement à une liaison `novatube4k_devices`
cohérente avec sa fiche `devices`, l'application `app_novatube4k`, son package
`com.manthefew` et une licence de cette application. La licence peut être
inactive, expirée ou bloquée : la réparation ne change jamais ce statut.
Les autres applications et les appareils non enrôlés ne sont pas réclamables.

## Réponse à l'appareil

Le client garde sa clé actuelle et continue à appeler
`POST /api/novatube4k/register`, avec `X-Device-Key` et `raw_mac` habituels.
Les champs facultatifs `model`, `appVersion`, `platform` permettent à
l'administrateur de lire les informations **déclarées** par cette installation.
Ils sont bornés et expurgés avant stockage ; ce ne sont pas des preuves
d'identité.

Si la clé est différente, la réponse HTTP 409 prend cette forme :

```json
{
  "ok": false,
  "error": "device_key_conflict",
  "app_id": "app_novatube4k",
  "mac": "MK:11:22:33:44:55",
  "server_now": 1800000000000,
  "recovery": {
    "status": "pending",
    "code": "4X7K-P9DM-2R6C",
    "expires_at": 1800000600000
  }
}
```

- Tous les horodatages sont des entiers UTC en **millisecondes**.
- Le code est constitué de 12 symboles Crockford base32, regroupés `4-4-4`.
  Alphabet : `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, soit 60 bits aléatoires
  cryptographiques. Regex : `^[0-9A-HJKMNP-TV-Z]{4}(?:-[0-9A-HJKMNP-TV-Z]{4}){2}$`.
- La durée maximale est de dix minutes. Une même nouvelle clé retrouve
  le même code tant qu'il est valide, sans prolongation du délai.
- Le code est lié au hash de la **nouvelle** clé et à l'ancienne liaison
  exacte. Aucun hash, clé ou MAC brute n'est retourné dans cette erreur.
- Trois emplacements au maximum sont conservés par liaison, y compris
  sous concurrence. Les slots expirés ou caducs sont réutilisés ; leur
  stockage ne croît pas indéfiniment.
- Quand les trois candidats sont encore valides, la même réponse 409
  contient `recovery:{status:"unavailable",retry_after:secondes}` sans code.
- Après expiration, un nouveau `register` fournit un nouveau code.
- Après approbation, ce même `register`, avec la clé locale inchangée,
  rend le contrat normal 200. `state` reste l'autorité pour la licence.

`device_identity_conflict` et `device_registration_missing` restent des 409
distincts. Ils contiennent aussi `ok:false` booléen, `app_id`, `mac` et
`server_now`, mais **aucun objet recovery**. Aucune erreur 409 ne vaut
autorisation ou suppression de profil.

Le client vérifie l'application, son propre identifiant MK, `ok:false`, le
code d'erreur et la forme/expiration du code. Le délai local est calculé
avec une horloge monotone depuis l'envoi de la requête, sans se fier à
l'heure configurée sur la box. Un code invalide ou expiré est retiré.

## Parcours administrateur

Les trois routes réutilisent `/api/v1/auth/me` du Worker historique, donc les
mêmes JWT, sessions, contrôles d'origine et quotas. Seul le rôle exact
`super_admin` est autorisé. Ni un revendeur, ni le rôle support, ni la clé
d'appareil ne donnent accès à cette opération. Un quota supplémentaire
limite ces routes à 30 appels par minute selon le limiteur existant.

| Étape | Route | Entrée / résultat |
|---|---|---|
| Capacité | `GET /api/v1/novatube4k/reassociate?mac=MK:…` | `{ok:true,supported:true,app_id,mac}` pour une liaison éligible. Aucun candidat ni code n'est listé. |
| Aperçu | `POST /api/v1/novatube4k/reassociate/preview` | Corps `{mac,code}` venant de la box. Réponse `{ok:true,app_id,mac,server_now,candidate:{request_id,created_at,expires_at,model,app_version,platform}}`. Aucune clé, empreinte, MAC brute ou code retourné. |
| Confirmation | `POST /api/v1/novatube4k/reassociate/approve` | Corps `{mac,code,request_id}`. `request_id` UUID v4 de l'aperçu est obligatoire. Réponse `{ok:true,app_id,mac,result:"device_reassociated",approved_at}`. |

Les POST acceptent un code en minuscules, avec espaces ou tirets puis le
normalisent, mais ne remplacent pas arbitrairement `O` par `0` ou `I` par `1`.
La saisie maximale est de 64 caractères et les corps JSON sont limités à
4 Kio. La capacité et l'aperçu ne créent ni schéma ni demande de récupération.
Le code ne doit jamais être placé dans une URL, un journal ou le stockage
persistant du navigateur. Le formulaire efface son aperçu quand le code ou
la fiche change et exige une nouvelle vérification après une erreur.

### Erreurs d'administration

Toutes les erreurs propres au module portent `{ok:false,error,message}`,
avec un message français sans donnée privée. Les erreurs d'authentification
restent celles du Worker historique.

| HTTP | `error` | Sens |
|---|---|---|
| 400 | `invalid_recovery_request` | MAC/code/id absent ou malformé. |
| 403 | `forbidden` | Acteur authentifié non `super_admin`. |
| 404 | `recovery_not_supported` | Autre app, fiche non enrôlée ou liaison incohérente. |
| 409 | `recovery_not_found` | Aucun candidat pour cette MAC et ce code. |
| 409 | `recovery_expired` | Délai écoulé avant vérification. |
| 409 | `recovery_consumed` | Candidat déjà approuvé ou remplacé. |
| 409 | `recovery_stale` | Aperçu ou liaison changé ; CAS perdu ; expiration pendant la transaction. |
| 413 | `body_too_large` | Corps dépassant 4 Kio. |
| 429 | `rate_limited` | Quota atteint. |
| 503 | `recovery_unavailable` | Erreur de stockage ou mécanisme indisponible. |

## Atomicité et audit

L'approbation relit **dans le lot D1 transactionnel** le candidat encore
valide, son `request_id`, son code, sa MAC, son alias brut, son `device_id`,
l'ancienne empreinte et la nouvelle. L'identité et la licence de l'app
doivent encore être présentes. L'expiration est vérifiée avec l'horloge
SQLite en plus de celle de la requête.

Le lot remplace seulement `device_key_hash`, met à jour la date de la
liaison et efface `last_served_rev` : une nouvelle installation doit relire
les sources avant de pouvoir accuser réception d'une révision. Il consomme
le candidat approuvé, invalide les autres et écrit l'action
`device.key_reassociate` dans `audit_logs`, avec acteur et `request_id`.
Cet audit ne contient ni code, ni empreinte, ni clé, ni MAC brute. Un échec
de l'audit annule également le remplacement de clé et la consommation.

La licence, sa date de fin, les sources chiffrées, révisions, ordres, clients,
paiements et crédits restent inchangés. La clé précédente est refusée aux
requêtes suivantes. Les requêtes déjà authentifiées avant la transaction
restent soumises au comportement historique du Worker ; ce changement
n'introduit pas d'interruption des requêtes en vol.

Deux approbations concurrentes ont un seul gagnant. Le rejeu ne crée pas
une seconde approbation ou une seconde écriture d'audit. Un administrateur
doit confirmer le code reçu réellement du propriétaire de la box : une
MAC ou des métadonnées ressemblantes ne suffisent pas.

## Vérification locale et intégration

- `node --test novatube4k-recovery.test.mjs` : schéma, droit, portée, code,
  expiration, concurrence, compare-and-swap, rollback et données inchangées.
- `NOVATUBE4K_TEST_ENTRY=/chemin/candidat/novatube4k-live-entry.js node --test
  novatube4k-recovery.test.mjs novatube4k-wrapper.test.mjs novatube4k-panel.test.mjs` :
  mêmes contrats et régressions sur le bundle historique exact enveloppé.
- `node novatube4k-recovery.workerd.mjs /chemin/candidat/novatube4k-live-entry.js` :
  runtime Cloudflare et D1 locaux, vraies requêtes concurrentes, échec
  transactionnel d'audit et zéro appel réseau extérieur.

`prepare_novatube4k_release.py` copie le nouveau module à côté de ceux de la
version 318. Aucun corps de fonction historique, binding, secret, classe
Durable Object, flag ou date de compatibilité n'est changé. Le Worker,
l'interface admin et l'APK doivent être validés puis publiés de façon
coordonnée. Il ne faut pas supprimer une fiche pour réparer sa clé.
