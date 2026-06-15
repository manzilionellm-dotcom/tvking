# Prompt de passation — DeFew TV (à coller dans Claude Code)

Copie TOUT ce qui est entre les lignes `=====` dans Claude Code sur ton ordinateur.

=====================================================================

Tu es un Staff Engineer (niveau Netflix / Apple TV+ / Disney+ / YouTube) en
charge de finaliser **DeFew TV** (alias « The Few »), une application IPTV
premium en **Flutter**. Tu travailles dans CE dépôt. Lis ce briefing en entier
avant d'agir, puis exécute en incréments stables, chacun vérifié « vert ».

## 0) RÈGLES NON NÉGOCIABLES
1. **NE TOUCHE JAMAIS au lecteur vidéo.** Il est impeccable. Le moteur vit dans
   le plugin `packages/native_video_player/` (ExoPlayer/Media3 + SurfaceView) et
   `media_kit`. Toute fonctionnalité « lecture/qualité/position » est interdite
   sauf demande EXPLICITE de l'utilisateur.
2. **Stabilité avant tout.** L'app ne doit jamais planter ni geler. Avant tout
   travail lourd sur une liste, vérifie que c'est O(1)/O(n) hors `build()` et
   jamais des regex/scan répétés (cause d'ANR déjà corrigée).
3. **Français partout** : UI ET commentaires de code abondants et pédagogiques.
4. **Aucune playlist/URL IPTV en dur** en prod (les `fake_*` peuvent avoir des
   placeholders de dev). Tout vient du backend par MAC.
5. **Couleurs/tailles** uniquement via `TvTokens`/`TvDimens` (TV) ou
   `AppColors`/`AppTextStyles` (mobile). Jamais de `Color(0xFF…)` magique ni de
   `fontSize:` en dur dans l'UI.
6. **Pas de `print()`** → `debugPrint()`.
7. Messages de commit **sans backticks** (le shell les exécuterait).
8. Ne mets aucun identifiant de modèle d'IA dans les commits/PR/code.

## 1) CE QU'EST L'APP
- App TV (10-foot, navigation télécommande D-pad). Entrée : `lib/main_tv.dart`
  (flavor `sevenMotion`). UI TV dans `lib/features/tv/`.
- App SŒUR mobile (« The Few ») : `lib/main.dart`, MÊME backend/panel.
- Cibles : Android TV, Fire TV / **Fire Stick (Amazon)**, Google TV. À terme :
  Samsung (Tizen) et LG (webOS) — codebase web déjà démarré dans
  `tv-tizen-webos/` (à enrichir, NE marche PAS avec l'APK : Tizen/webOS = web).

## 2) ARCHITECTURE
```
lib/
├── core/        # thème (TvTokens/TvDimens), i18n, widgets génériques
├── features/
│   ├── tv/presentation/      # écrans TV (tv_live_screen, tv_player_screen, …)
│   ├── playlists/data/       # PlaylistRepository (SQLite), RemoteSourceRepository
│   ├── channels/             # Channel (genre/cleanName en cache), recently_watched
│   ├── subscription/data/    # heartbeat + statut (subscription_backend.dart)
│   ├── security/data/        # app_pin_settings, parental_controls (Mode Enfants)
│   ├── device/data/          # device_identity (MAC stable « MK:… »)
│   └── recordings/, sports/, …
cloudflare/      # worker.js (+ api_v1.js) = backend Cloudflare (app.7themotion.com)
admin-panel/     # panneau React/Vite du revendeur (DevicesPage, etc.)
tv-tizen-webos/  # app web Samsung/LG (chantier)
marketing/amazon/, docs/AMAZON_FIRETV.md  # soumission Amazon
ci/defew-debug.keystore   # keystore FIXE (signature stable)
```

## 3) WORKFLOW GIT & BUILDS (IMPORTANT)
- Branche de travail : **`claude/iptv-chromecast-cast-WeAyo`**. Reste dessus.
- AVANT chaque push : `git fetch origin <branche>` puis
  `git rebase origin/<branche>` (d'autres sessions poussent en parallèle).
- `android/` est **régénéré par la CI** via `flutter create` → tout code natif
  durable doit vivre dans `packages/` (plugins auto-enregistrés) ou être
  appliqué par un patch du workflow `.github/workflows/build-tv.yml`.
- Le workflow **build-tv.yml** : compile `main_tv`, patche le manifest (cleartext
  HTTP, leanback, **bannière `android:banner`**), génère icônes, **copie le
  keystore fixe** (`ci/defew-debug.keystore` → `~/.android/debug.keystore` pour
  une **signature stable** = mises à jour sans désinstaller), build un **APK
  UNIVERSEL** (toutes ABIs → s'installe sur tous les Fire Stick 32/64 bits), et
  publie sur la release **`tv-latest`**.
- **Vérifier un build** : regarde le JOB (pas seulement le run) de build-tv.yml
  via `gh run list`/`gh run view` ou l'API GitHub Actions. Fie-toi à la
  conclusion du JOB (le niveau run peut rester « in_progress » par retard d'API).
  L'étape 18 « Build DeFew TV (release universel) » = compilation Dart ; étape 19
  = publication. Si rouge, lis les logs et grep `Error:`, `e: …dart:`.
- **Worker** : `deploy-worker.yml` déploie `cloudflare/worker.js` automatiquement
  sur push `claude/**`. Vérifie le brace-balance avant push (un `}` orphelin
  casse TOUS les déploiements — déjà arrivé). `api_v1.js` a un déséquilibre de
  parenthèses de +1 DÛ à une regex (normal, présent sur HEAD).
- **Distribution** : code Downloader **`6248618`** et lien `app.7themotion.com/tv`
  → pointent toujours sur `tv-latest` (dernier APK).

## 4) BACKEND (Cloudflare worker, app.7themotion.com)
Routes publiques utiles à l'app :
- `POST /api/heartbeat` {mac, model, platform:'tv', sources[], recent[]} → statut.
  (Stocke aussi l'inventaire des sources et l'historique par MAC.)
- `GET /api/status/:mac` → statut d'abonnement.
- `GET /api/device-source/:mac` → source(s) poussée(s) par le panel (trio).
- `GET /api/history/:mac` → historique de visionnage (synchro multi-box).
API admin (`api_v1.js`) : `/api/v1/devices/:id/overview` (fiche 360° : licence,
présence, M-Trio, inventaire réel), `/api/v1/sources/:mac`, activation, etc.
MAC stable : dérivée d'`ANDROID_ID` via le plugin `packages/tvking_device/`,
priorité aux prefs (ne change jamais une fois posée).

## 5) ÉTAT ACTUEL (déjà livré et VERT)
Stabilité (anti-ANR : genre Channel en cache + index mémoïsé), démarrage direct
sur les chaînes en cache, **bannière logo Android TV**, **signature stable**,
**APK universel Fire Stick**, **cache disque images + skeletons (60 FPS)**, rail
**« ✨ Pour vous »**, **historique synchronisé serveur**, Mode Enfants + contrôle
parental (PIN), panel « centre de contrôle 360° par MAC » + inventaire réel des
sources, gestion des sources côté client (M3U/Xtream). Déjà présents : Continue
Watching, Top 10, Tendances, Récemment, Favoris, recherche, enregistrements,
Actu sport (équipes favorites + alarmes), reconnexion auto du lecteur.

## 6) PRIORITÉS À FAIRE (dans l'ordre)
A. **Amazon Appstore (Fire TV)** : l'APK est prêt (universel, sans Google Play
   Services — le Cast se fait par QR+mDNS, pas la lib Play Services). Aider à la
   soumission. Assets dans `marketing/amazon/` (`icon_512.png`,
   `feature_1280x720.png`), fiche FR dans `marketing/amazon/listing_fr.md`, guide
   `docs/AMAZON_FIRETV.md`. À produire si demandé : version EN de la fiche,
   page « politique de confidentialité » à héberger.
B. **Samsung (Tizen) + LG (webOS)** : enrichir `tv-tizen-webos/` (app web,
   lecteur natif AVPlay/webOS, MÊME backend par MAC). Voir `tv-tizen-webos/README.md`.
   Packager `.wgt` (Samsung) / `.ipk` (LG) puis soumettre aux stores.
C. **Finitions « niveau Netflix »** sans toucher la vidéo : préchargement
   d'images, gestion réseau intelligente (retries + bannière hors-ligne discrète),
   onboarding première ouverture. Justifier chaque ajout par un gain utilisateur.

## 7) MÉTHODE
- Travaille par petits incréments compilables. Après chaque incrément : commit
  clair (sans backticks), push (avec fetch+rebase avant), puis VÉRIFIE le build
  TV au niveau JOB jusqu'à « success ». Si rouge, corrige immédiatement.
- Pour le code JS/worker, équilibre `{}()[]` avant push.
- Compare chaque écran/interaction aux grandes apps US ; si moins fluide, réécris.
- Ne te précipite pas : l'utilisateur veut l'app la plus stable possible.

Commence par : lire `lib/main_tv.dart`, `lib/features/tv/presentation/tv_live_screen.dart`,
`cloudflare/worker.js` (handleHeartbeat, handlePublicDeviceSource, handlePublicHistory),
`.github/workflows/build-tv.yml`, puis demande à l'utilisateur quelle priorité
(A/B/C) il veut attaquer — ou propose la plus utile.

=====================================================================
