# BUILD-REPORT

Date : 2026-07-29 · Branche : `claude/audit-mobile-tv-delivery-ghn12o` ·
Commit livré : (tête de branche après les 8 commits d'audit).

## Barrières qualité (avant build)

| Porte | Résultat |
|---|---|
| `flutter analyze` (local, Flutter 3.44.8) | 0 erreur (5 warnings dans des fichiers non touchés ; CI `--no-fatal-warnings`) |
| `flutter test` (local, suite complète) | 672 tests verts (664 baseline + 8 nouveaux) |
| CI `Quality (analyze + tests)` | voir statut du run dispatché sur le commit final |
| CI `Tests` (cœur métier) | voir statut du run |

## Builds produits (CI, signés clé maîtresse)

> Renseigné à partir des runs CI réels et des artefacts vérifiés. Les APK de
> livraison sont republiés sur les canaux de TEST à lien direct (jamais les
> canaux clients — cf. SIGNING-REPORT.md). Valeurs finales dans le tableau
> ci-dessous et dans la SORTIE FINALE.

| App | Plateforme | Workflow | Run CI | Artefact | Taille | SHA-256 | Signature |
|---|---|---|---|---|---|---|---|
| 7 MOTION | Android (APK) | build-android.yml | _(à renseigner)_ | 7motion.apk → phone-test | _(vérifié)_ | _(vérifié)_ | clé maîtresse (v1+v2) |
| 7 MOTION | Android (AAB) | build-android.yml | _(idem)_ | 7motion.aab (artefact de run) | — | — | clé maîtresse |
| DEFEW TV | Android TV (APK) | build-tv.yml | _(à renseigner)_ | app-release.apk → cinema-test | _(vérifié)_ | _(vérifié)_ | clé maîtresse (v1+v2) |
| DEFEW TV | Android TV (AAB) | build-tv.yml | _(idem)_ | defew-tv.aab (artefact de run) | — | — | clé maîtresse |

## Liens directs de téléchargement

Voir le tableau de la SORTIE FINALE (releases de test à lien direct GitHub).

## Vérification des artefacts

Pour chaque APK publié : existence, taille cohérente, présence des
signatures v1 (META-INF) et v2/v3 (APK Signing Block), empreinte du
certificat (keytool), SHA-256 (sha256sum). Détails renseignés après
téléchargement des artefacts publiés.

## Note iOS / autres

Pas d'IPA signé produit (certificats/profils Apple absents de cet
environnement). Windows/Tizen : workflows existants non déclenchés par cet
audit (hors périmètre mobile+TV Android).
