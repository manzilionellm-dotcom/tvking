# SECURITY-AUDIT

Date : 2026-07-29. Aucune valeur de secret n'est reproduite ci-dessous —
seulement emplacements et natures. Statut : **CORRIGÉ** ou **DOCUMENTÉ**.

## Critiques

| ID | Constat | Emplacement | Statut |
|---|---|---|---|
| S-C1 | Secret de signature JWT de repli codé en dur (`\|\| 'dev-secret'`) : instance sans `ADMIN_SECRET` = forge de jetons `super_admin` triviale | cloudflare/api_v1.js (verifyJwt, signJwt, 2 login), worker.js (WS) | **CORRIGÉ** (fail-closed : secret < 8 → refus ; 4 replis supprimés) |
| S-C2 | Bootstrap super_admin sur mot de passe de repli (`\|\| 'change-me'`) | cloudflare/api_v1.js | **CORRIGÉ** (aucun compte créé sans ADMIN_SECRET) |
| S-C3 | `/api/backup/:mac` : sauvegarde cloud des identifiants Xtream en clair, GET **et PUT** sans authentification (la MAC n'est pas un secret) | cloudflare/worker.js, lib/.../cloud_backup_repository.dart | **DOCUMENTÉ** (S-B1 : exige un jeton d'appareil signé + chiffrement du blob — refonte backend/app à valider bout-en-bout ; risque de casser la restauration existante si mal fait) |

## Hauts

| ID | Constat | Statut |
|---|---|---|
| S-H1 | Crash backend Firebase recevait l'erreur BRUTE (URI Xtream avec identifiants) hors caviardage | **CORRIGÉ** (voir M-H15) |
| S-H2 | Validation TLS désactivée (`badCertificateCallback => true`) sur le client d'import/API Xtream (identifiants dans l'URL), pas seulement sur le flux vidéo | **DOCUMENTÉ** (S-B2 : scinder client « flux » tolérant / client « API » strict — changement de comportement réseau à valider sur le parc de panels réels avant livraison) |
| S-H3 | `build-prive.yml` publiait `prive-latest` (release cliente) sans garde de branche : tout push feature/claude écrasait l'APK distribué | **CORRIGÉ** (garde `maison-mere-phone`/`main`) |
| S-H4 | Mot de passe admin en entrée `workflow_dispatch` type `string` (conservé/affiché en clair sur la page du run) | **DOCUMENTÉ** (S-B3 : le workflow reste, mais l'usage recommandé est `wrangler secret put` local — masquage `::add-mask::` insuffisant car l'input reste stocké) |
| S-H5 | Secret admin + PIN admin en clair dans SharedPreferences, comparaison non constant-time | **DOCUMENTÉ** (S-B4 : router par SecretCipher + KDF, aligné sur le PIN utilisateur déjà durci) |

## Moyens

| ID | Constat | Statut |
|---|---|---|
| S-M1 | Trous de couverture SecretRedactor : `secret/auth/api_key/key/sig/pwd/access_token/session`, en-têtes `Authorization`/`X-Admin-Secret`, chemins Xtream sans extension | **CORRIGÉ** + tests |
| S-M2 | Comparaisons de secrets non constant-time côté serveur (signature JWT, hash PBKDF2) | **CORRIGÉ** (timingSafeEqualStr sur les deux) |
| S-M3 | Injection shell via `inputs.run_id` interpolé dans les `run:` des 3 workflows publish | **CORRIGÉ** (variable d'env + validation `^[0-9]+$`) |
| S-M4 | `/cast-sign` : oracle de signature public → proxy ouvert 12 h | **DOCUMENTÉ** (S-B5 : lier à une MAC active, réduire l'expiration) |
| S-M5 | Rate-limit anti-énumération fail-open (y compris codes famille/invitation) | **DOCUMENTÉ** (S-B6 : fail-closed sur les buckets de code court) |
| S-M6 | CORS `*` avec `Authorization`/`X-Admin-Secret` autorisés sur les routes admin | **DOCUMENTÉ** (S-B7 : liste blanche d'origines) |
| S-M7 | PIN utilisateur par défaut `0000` accepté tant qu'aucun PIN défini (contrôle parental ouvert par défaut) | **DOCUMENTÉ** (S-B8 : imposer la définition à la 1re activation) |

## Bas

JWT admin 7 j sans révocation, en localStorage (S-B9) ; jeton WS en query
string, journalisable (S-B10) ; mots de passe de certificat Tizen en dur —
valeurs publiques documentées, impact faible (S-B11) ; serveur cast local
`0.0.0.0` + CORS `*` (S-B12). Tous **DOCUMENTÉS**.

## Points forts confirmés

Caviardage des secrets = vrai point d'étranglement, pur/testé/anti-ReDoS,
branché sur les 4 puits (la fuite backend S-H1 refermée par cet audit) ;
chiffrement au repos avec racine matérielle (Keystore/StrongBox) + versioning
de migration ; PIN utilisateur (PBKDF2 salé 20 000 itérations, temps
constant, verrouillage exponentiel) et `checkAdmin` fail-closed exemplaires ;
anti-SSRF `/cast-proxy` revalidé à chaque saut ; `JSON_HEADERS_PRIVATE` sans
CORS sur les endpoints à identifiants ; correctif documenté du
`badCertificateCallback` du résolveur DoH. Aucun keystore non chiffré ni
token haute entropie commité (`ci/release.jks.enc` = conteneur openssl salé,
`ci/defew-debug.keystore` = clé de debug volontaire).

## Note de périmètre

Les corrections serveur (worker.js/api_v1.js) sont validées par les smoke
tests Node existants (`cloudflare/*.smoke.mjs`, 100+ assertions vertes) mais
ne sont **déployées que par `deploy-worker.yml` depuis la maison mère** — cet
audit ne redéploie pas le Worker de production. Les items DOCUMENTÉS sont au
backlog `.company` avec leur justification de report (surface backend/parc à
valider hors de cet environnement).
