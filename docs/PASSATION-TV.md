# PASSATION — Côté TV (box Android TV / Fire TV / Samsung)

> Document de passation pour un ingénieur qui reprend le côté télévision.
> Rédigé le 2026-08-08. Tout ce qui est décrit ici est vérifié à cette date.

## 0. En une minute

- **Une seule app TV vendue : « 7 MOTION TV »** (`com.sevenmotion.tv.seven_tv`),
  distribuée par la release GitHub `seventv-latest`, lien client
  `app.7themotion.com/tv`.
- **Tout le code vit sur UNE branche** :
  `claude/7motion-android-tv-compat-e0rtyp` — c'est l'état le plus récent du
  projet Flutter (mobile + TV + Samsung + Windows partagent ce code).
- La mémoire du projet est dans **`STATUS.md`** (à la racine de cette
  branche) : chaque session de travail y est journalisée avec les causes
  racines et les correctifs. **À lire en premier.**

## 1. Où est le code (branche `claude/7motion-android-tv-compat-e0rtyp`)

| Quoi | Chemin |
|---|---|
| Point d'entrée TV | `lib/main_tv.dart` (333 lignes) |
| Toute l'UI TV (écrans 10-foot, D-pad) | `lib/features/tv/presentation/` (home, chaînes, films, séries, guide EPG, diagnostics, téléchargements, réglages…) |
| Données/perf TV | `lib/features/tv/data/` et `lib/features/tv/core/` (CinePerf budgets, TvPosterPrefetch…) |
| **Lecteur vidéo natif** (le cœur sensible) | `packages/native_video_player/` — plugin Flutter maison. Kotlin : `packages/native_video_player/android/src/main/kotlin/com/manzilionellm/native_video_player/NativeVideoView.kt` (868 lignes) ; Dart : `packages/native_video_player/lib/native_video_player.dart` |
| Playlists M3U / Xtream, EPG, VOD | `lib/features/playlists/`, `lib/features/epg/`, `lib/features/vod/` |
| App Samsung (même UI TV, lecteur AVPlay) | `lib/main_tizen.dart` + `lib/features/tv/presentation/player/tizen_player_screen.dart` |
| Backend (liens courts, panel, API, updater) | `cloudflare/worker.js` (+ `cloudflare/landing.js` = le site) |
| Tests (~540, verts en CI) | `test/` |

Lien direct vers la branche :
`https://github.com/manzilionellm-dotcom/tvking/tree/claude/7motion-android-tv-compat-e0rtyp`

## 2. Le lecteur vidéo — décisions gravées (NE PAS défaire sans box réelle)

Tout est journalisé dans `STATUS.md`, résumé :

1. **Flutter épinglé `3.32.x`** dans les workflows TV. Raison : 3.35 a
   abandonné Android 5-7 (API < 24), 3.44 a supprimé Skia. Les box bas de
   gamme crashent au-delà. Ne pas remettre `channel: stable` non épinglé.
2. **Impeller OFF** (meta-data `EnableImpeller=false` posée par le CI) →
   rendu Skia. C'est LE correctif « écran noir GPU » des box.
3. **Double chemin de rendu vidéo** dans `NativeVideoView` : mode
   `texture` (défaut, MediaCodec → SurfaceTexture Flutter) et mode
   `surface` (SurfaceView de secours), avec **watchdog** : pas d'image
   après ~6 s → bascule automatique + mémorisation par box
   (SharedPreferences). Ne jamais réduire à un seul chemin.
4. **Media3 1.8.0** (pas l'ancien ExoPlayer), LoadControl à 3 profils
   selon la RAM (aperçus 8-15 s / 8 Mo, low-RAM 15-30 s / 18 Mo, normal
   20-50 s / 32 Mo, plafonds octets anti-OOM), décodage matériel avec
   `setEnableDecoderFallback(true)`, reconnexion auto + reprise réseau
   instantanée (`registerDefaultNetworkCallback`), audio focus système
   (le lecteur audible seulement — jamais les aperçus muets).
5. **media_kit (libmpv) est RETIRÉ du build TV par le CI** (étape
   « Alléger l'APK TV ») : la TV lit exclusivement via ExoPlayer. Ne pas
   le réintroduire côté TV (écrans noirs constatés sur box).
6. HLS bypasse le relais local ; le relais (`local_stream_relay`) ne sert
   que les flux TS continus et l'enregistrement 1-connexion
   (`lib/features/player/data/hls_preflight.dart` explique pourquoi).

## 3. Build & publication (GitHub Actions, sur CETTE branche)

| Workflow | Rôle | Publication |
|---|---|---|
| **`build-seventv.yml`** | Compile 7 MOTION TV (target `lib/main_tv.dart`), APK **universel ARM 32+64**, minSdk 21, targetSdk 35, R8, splash sombre, tous les patchs manifest | Dispatch avec `publish=true` → release **`seventv-latest`** (`seven-tv.apk` + `version.json` pour l'updater in-app ; garde anti-downgrade ; versionCode = epoch) |
| `build-tv.yml` | L'ancien build DeFew TV (même code, autre identité). Conservé pour référence — **plus distribué** | (ne plus publier) |
| `build-tizen.yml` | Samsung Tizen (.tpk signé certificat auteur, secrets `SAMSUNG_AUTHOR_P12_BASE64`/`SAMSUNG_AUTHOR_PASSWORD`) | release `tizen-latest` |
| `deploy-worker.yml` | Déploie `cloudflare/worker.js` sur `app.7themotion.com` | — |
| `quality.yml` / `tests.yml` | analyze + tests (barrière aussi intégrée aux builds) | — |

**Signature Android** : clé maîtresse release (« The Few », RSA 2048,
valide → 2053), déchiffrée en CI depuis `ci/release.jks.enc` avec le secret
`ANDROID_KEYSTORE_PASSWORD` (ou `ANDROID_KEYSTORE_BASE64`). Empreinte
SHA-256 du certificat :
`51:45:B8:E0:19:F6:D5:FB:96:A2:07:F2:E7:36:73:FD:95:4F:79:99:66:FD:59:88:89:21:15:56:CB:DF:9E:61`.
Signatures v1/v2/v3 activées. Tant que cette clé signe, les mises à jour
s'installent par-dessus chez tous les clients.

## 4. Distribution & mise à jour

- Lien client TV : **`https://app.7themotion.com/tv`** (alias : /7tv,
  /seventv, /777, /tv7…) — proxy Worker → toujours le dernier
  `seven-tv.apk` de `seventv-latest`, fichier servi « SevenMotionTV.apk ».
- Lien GitHub brut :
  `https://github.com/manzilionellm-dotcom/tvking/releases/download/seventv-latest/seven-tv.apk`
- **Updater in-app** : l'app lit `version.json` sur son tag
  (`TV_UPDATE_TAG=seventv-latest`, injecté au build). versionCode lu dans
  l'APK réel, jamais inventé ; grâce 12 h + espacement 24 h côté app
  (anti-harcèlement).
- Samsung : `https://app.7themotion.com/samsung` (.tpk, sideload Mode
  Développeur Tizen 6.0+ ; store = certificat distributeur Samsung à créer).

## 5. Historique et pièges connus

- **2026-08-08 : grand nettoyage.** Les releases `tv-prod`, `tv-latest`,
  `tv-fix-latest`, `cast-fix-tv-latest`, `cinema-test`, `phone-test`,
  `master-console` ont été SUPPRIMÉES (ordre du propriétaire). ~38 box de
  l'ancienne lignée DeFew (`com.defew.tv`) tournent encore, figées, sans
  canal de mise à jour : migration = installer 7 MOTION TV par-dessus
  (autre applicationId → les deux icônes coexistent tant qu'on ne
  désinstalle pas DeFew).
- Les installs Seven TV de **juin 2026** étaient signées avec une clé
  aléatoire → une réinstallation unique est nécessaire (documentée dans
  les notes de release), ensuite MAJ normales.
- `STATUS.md` (branche TV) contient le journal complet des causes
  racines : écrans noirs/blancs, « l'image ne vient pas », lignes jaunes,
  OOM box 1 Go, EPG Xtream muet, etc. **Chaque piège y a son explication.**
- Le dossier `docs/` de la branche TV contient aussi :
  `android-tv-hardening.md`, `AUDIT-DURCISSEMENT-TV.md`,
  `AMAZON_FIRETV.md`, `PORTAGE_TV_PLATEFORMES.md`.

## 6. Vue d'ensemble des 5 apps

Voir `docs/APPLICATIONS-OFFICIELLES.md` (même branche que ce document) :
liens permanents, signatures, procédure de publication pour chacune des
5 applications (Android, iPhone, TV box, Samsung, Windows).
