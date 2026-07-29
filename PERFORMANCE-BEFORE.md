# PERFORMANCE-BEFORE — Baseline mesurée avant corrections (2026-07-29)

Commit de référence : `25d7cb3` (fusion canonique mobile + TV, avant toute
correction de cet audit).

## Outils

| Outil | Version |
|---|---|
| Flutter (local + CI, canal stable) | 3.44.8 / Dart 3.10.x |
| Java (CI) | Temurin 17 |
| Gradle | géré par Flutter (CI) |

## Qualité statique et tests (local, machine 4 cœurs / 15 Go RAM)

| Mesure | Valeur |
|---|---|
| `flutter analyze` | **0 erreur**, 1 warning (`unused_element_parameter`), 267 infos — 39,3 s |
| `flutter test` (suite complète) | **664/664 verts** — 1 min 11 s |
| CI `Quality (analyze + tests)` (run 30480887197) | ✓ succès |
| CI `Tests` cœur métier (run 30480889255) | ✓ succès — 1 min 50 s |

## Taille des livrables (dernier état connu avant audit)

| Artefact | Taille | Source |
|---|---|---|
| 7motion-test.apk (arm64, release signé, obfusqué) | 66 035 756 octets (~63 Mo) | run 30158788079 (2026-07-25) |
| defew-tv.apk (universel, release signé) | voir BUILD-REPORT après builds baseline | canal tv-prod |

## Budgets performance embarqués (mesure sur appareil via Boîte noire, tag « perf »)

Définis dans `lib/features/tv/data/cine_perf.dart` (CinePerf) :

| Chrono | Budget |
|---|---|
| Accueil Cinéma (homeFirstRender) | < 400 ms |
| Ouverture fiche (detailOpen) | < 300 ms |
| Regarder → 1re frame (TTFF) | < 2500 ms |

Les valeurs réelles se relèvent sur box via la Boîte noire (pas d'appareil
dans cet environnement de dev) — WARN émis si budget dépassé.

## Gros catalogues — protections existantes constatées (avant audit)

- Import M3U/XMLTV : parsing en isolate (`xmltv_parse_isolate`), imports
  bornés anti-OOM (`XtreamClient` : collecte d'alias bornée), lecture
  SQLite bornée (`PlaylistRepository.getVodChannels` documentée bornée).
- UI TV : rails/scroll avec état persisté (PageStorage), préchargement de
  jaquettes borné (`TvPosterPrefetch`), RepaintBoundary sur affiches.
- `DeviceMemory` : plafond prudent 8000 éléments si RAM inconnue (testé).

Les mesures après corrections sont dans PERFORMANCE-AFTER.md.
