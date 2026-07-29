# SIGNING-REPORT

Date : 2026-07-29.

## Configuration de signature (existante, non modifiée)

Les deux apps sont signées **en CI** avec la clé de signature de production
déjà présente dans l'environnement sécurisé — cet audit n'a **créé aucune
clé**, n'a **pas modifié la clé historique** et n'a **copié aucune clé
privée dans le dépôt**.

| Élément | Source | Détenu par |
|---|---|---|
| Keystore de production | `ci/release.jks.enc` (conteneur openssl salé) déchiffré en CI via le secret `ANDROID_KEYSTORE_PASSWORD` (ou `ANDROID_KEYSTORE_BASE64`) | GitHub Actions secrets |
| Config Gradle | `build-android.yml` / `build-tv.yml` injectent `key.properties` au build release | — |
| Keystore de debug (clé fixe volontaire) | `ci/defew-debug.keystore` | dépôt (assumé — clé de sideload partagée pour MAJ par-dessus) |

Règle CI respectée : si le secret keystore est absent, le workflow émet un
`::warning::` et **ne prétend pas** à une signature release (repli debug
explicite, non distribuable Play Store). Aucun secret n'est affiché dans les
logs.

## Vérification cryptographique des artefacts

Effectuée localement sur les APK **réellement publiés** (téléchargés depuis
les releases de test), via `keytool`/`jarsigner`/`unzip`/`sha256sum` :
présence des blocs de signature v1 (META-INF) et v2/v3 (APK Signing Block),
empreinte du certificat, taille cohérente, SHA-256.

> Les valeurs concrètes (empreinte publique du certificat, SHA-256, tailles)
> sont dans **BUILD-REPORT.md** et dans le tableau final — renseignées à
> partir des artefacts vérifiés, jamais inventées. Si une vérification
> échoue, l'artefact n'est PAS présenté comme build de production signé.

## Ce qui n'est PAS fait (et pourquoi)

- **Publication sur les canaux clients** (`prod`, `tv-prod`, `prive-latest`) :
  hors périmètre de cet audit. Ces canaux sont réservés à la branche
  `claude/maison-mere-phone` et à une décision humaine explicite (cf.
  RELEASE-CHECKLIST.md). Les livrables de l'audit partent sur les canaux de
  **test** à lien direct (`phone-test`, `cinema-test`), signés avec la même
  clé (installation par-dessus), invisibles de l'updater in-app.
- **iOS** : aucun build/signature iOS produit ici — les certificats et
  profils de provisioning Apple ne sont pas dans cet environnement (le
  workflow `build-ios-release.yml` existe et s'exécute depuis la maison mère
  avec les secrets TestFlight). Ne pas présenter d'IPA signé sans ces
  éléments = respect de la règle « ne pas inventer une signature ».
