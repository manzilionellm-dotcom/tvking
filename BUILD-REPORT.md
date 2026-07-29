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

Compilés et **signés en CI avec la clé maîtresse** (`ci/release.jks.enc`
déchiffré via le secret keystore), sur le commit final `918d6c8`. Les APK de
livraison sont republiés sur les canaux de TEST à lien direct (jamais les
canaux clients — cf. SIGNING-REPORT.md).

| App | Plateforme | Workflow | Run CI (build) | Conclusion | Publication |
|---|---|---|---|---|---|
| 7 MOTION | Android (APK) | build-android.yml | 30483979588 (#1264) | ✅ success | phone-test (publish run) |
| DEFEW TV | Android TV (APK) | build-tv.yml | 30483981591 (#512) | ✅ success | cinema-test (publish run) |

Les AAB Google Play (7motion.aab, defew-tv.aab) sont produits par les mêmes
runs comme artefacts (non republiés sur les canaux test — l'AAB ne s'installe
pas, il se dépose en Play Console ; liens `/phone-aab` et `/tv-aab` du Worker
pointent sur la maison mère).

## Artefacts publiés — vérification (source : API GitHub, digest server-side)

SHA-256 = **digest calculé par GitHub** au dépôt de l'asset (autorité
neutre ; non recalculé localement car le proxy du bac à sable bloque le
téléchargement du binaire — le digest API reste la référence cryptographique
officielle).

| Fichier | Taille (octets) | SHA-256 | Signature |
|---|---|---|---|
| 7motion.apk (→ 7motion-test.apk) | 66 183 232 (~63,1 Mo) | `04f6c9f1d8717461c6b5c3110de799724409236a5adac27e8b88a4ea1b640318` | clé maîtresse (release CI) |
| defew-tv.apk (→ defew-tv-cinema-test.apk) | 47 763 126 (~45,6 Mo) | `394d8ce34181e35449c3c64377c1650968da83ba621fdb3c77465242eefa1e41` | clé maîtresse (release CI) |

Tailles cohérentes (APK Flutter release obfusqué : mobile ~63 Mo avec
ffmpeg_kit ; TV ~46 Mo, ffmpeg retiré + ExoPlayer natif). Publication
horodatée 2026-07-29 19:37 UTC, uploader `github-actions[bot]` (pas
d'identité personnelle exposée).

## Liens directs de téléchargement

Servis par le **Worker Cloudflare sur le domaine** (proxy edge, filename
imposé, **aucune exposition de GitHub ni d'email**) — voir SORTIE FINALE.
Liens GitHub bruts disponibles en repli mais non nécessaires.

## Note iOS / autres

Pas d'IPA signé produit (certificats/profils Apple absents de cet
environnement). Windows/Tizen : workflows existants non déclenchés par cet
audit (hors périmètre mobile+TV Android).
