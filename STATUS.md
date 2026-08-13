# 7 MOTION — État du projet et mémoire persistante

> Ce fichier est ma mémoire entre les sessions Claude. Quand tu
> ouvres une nouvelle conversation, dis-moi simplement
> **"lis STATUS.md et continue"** et je reprendrai exactement
> là où on s'est arrêtés.

---

## Session (2026-08-08) — Lecteur TV « forteresse » : cascade de sources, garde d'états, télémétrie, pression mémoire

Branche : `claude/7motion-android-tv-compat-e0rtyp`. Durcissement du plugin
`native_video_player` (Kotlin + contrôleur Dart), 4 chantiers, AUCUN écran
modifié. Journée aussi : audio focus système (le lecteur audible le demande,
jamais les aperçus — sinon une vignette met la lecture principale en pause),
grand nettoyage des releases (5 apps officielles seulement, cf.
docs/APPLICATIONS-OFFICIELLES.md sur la branche d'inventaire), site
app.7themotion.com réparé (routes /install /tv /win /samsung + 4 QR).

### 1. Cascade de sources native (failover silencieux)
- `setUrl` accepte `fallbackUrls` (Dart : `setUrl(url, fallbackUrls: […])`).
- Budget de reconnexion épuisé sur la source courante → bascule IMMÉDIATE
  et silencieuse sur la suivante (l'utilisateur ne voit que « buffering ») ;
  l'erreur ne remonte à Dart qu'après épuisement de TOUTES les sources
  (payload enrichi : `sourcesTried`). Rétro-compatible : sans fallbacks,
  comportement historique inchangé. L'ORCHESTRATION reste côté Dart.
- Back-off avec JITTER (±25 %) : évite le « thundering herd » (toutes les
  box qui perdent le même serveur re-frappaient à la même milliseconde).

### 2. Garde d'états (FSM défensive native)
- Enum `Fsm` (IDLE→LOADING→BUFFERING/READY/ENDED/FAILED, RELEASED terminal),
  confinée au thread PLAYER comme le reste de l'état.
- Commandes zombies (play/seek sans média ou après release, setUrl après
  release) : IGNORÉES + journalisées (`fsm_violation`), jamais un crash.

### 3. Télémétrie silencieuse (ring buffer local)
- `AnalyticsListener` : frames perdues (compteur total + événement si
  paquet ≥ 30) et underruns audio — les signaux AVANT-COUREURS d'une box
  qui souffre. Ring buffer borné à 100 événements (retry, failover, fatal,
  trim, violations) : impossible à faire déborder.
- Drain par `getStats` (canal) / `controller.getStats()` (Dart) : AUCUN
  envoi réseau côté natif — la Boîte noire draine quand la connexion est
  stable, pour ne jamais voler de bande passante à la vidéo.

### 4. Pression mémoire (onTrimMemory, plugin)
- `ComponentCallbacks2` sur le contexte application : RUNNING_LOW → les
  APERÇUS sont stoppés (décodeur + tampons rendus) ; RUNNING_CRITICAL →
  les lecteurs principaux rendent leurs codecs « chauds »
  (`setForegroundMode(false)`, lecture en cours intacte) ; `setMedia`
  réarme automatiquement au zap suivant. Mieux vaut un zap 500 ms plus
  lent qu'une app tuée par l'OS.

### 5. Samsung TV (Tizen) : reconnexion automatique (parité forteresse)
`tizen_player_screen.dart` : avant, la moindre erreur AVPlay affichait
« Réessayer » et attendait le client. Désormais : 3 relances SILENCIEUSES
avec back-off + jitter (0,5→1→2 s ±25 %), chien de garde 15 s contre les
gels sans erreur (AVPlay bufférant à l'infini), budget rechargé au zap /
à la lecture saine / au retry manuel. L'écran fatal reste le filet final.
NB : fichier exclu de l'analyze CI (paquet video_player_avplay injecté
par le workflow Tizen uniquement) → c'est le build Tizen qui compile-vérifie.

### Contrats préservés
Threading (état lecteur = thread PLAYER, canal = main), double chemin de
rendu + watchdog Dart, LoadControl par RAM, reprise réseau instantanée,
`silent`/recover, comptage retries sur URL identique : tous inchangés.

---

## Session (2026-08-06) — Box TV : fin des écrans noirs/blancs au démarrage (compat toutes box)

Branche : `claude/7motion-android-tv-compat-e0rtyp` (base
`claude/salut-4nby1y`, l'état le plus récent de l'app). Plainte terrain :
beaucoup de box (surtout anciennes) ouvrent sur un écran NOIR ou BLANC puis
se ferment. Cause racine trouvée dans le CI, pas dans le Dart : `build-tv.yml`
utilisait `channel: stable` NON épinglé → le moteur embarqué dérivait à
chaque build.

### Les 2 dérives moteur qui tuaient les vieilles box
1. **Flutter 3.35 (août 2025)** : plancher Android relevé API 21 → 24. Notre
   APK (minSdk forcé 21) s'installait sur Android 5/6/7.0 mais le moteur ne
   les supportait plus → crash/écran noir immédiat.
2. **Flutter 3.44 (mi-2026)** : Skia SUPPRIMÉ sur Android 10+, Impeller
   obligatoire, opt-out mort. Pilotes Vulkan/GLES des box bas de gamme
   cassés → écran noir documenté sur Android TV (flutter #177319, #160866,
   #160647). Le `BootGuard.setCompatMode` (« Impeller OFF ») n'avait
   d'ailleurs JAMAIS été câblé côté manifest/CI.

### Correctifs (tous dans `.github/workflows/build-tv.yml`, zéro Dart)
- **Flutter épinglé `3.32.x`** : dernière ligne stable qui supporte encore
  l'API 21 ET l'opt-out Impeller. Plus de dérive silencieuse du moteur.
- **Impeller OFF via manifest** (`EnableImpeller=false`) → rendu Skia
  éprouvé sur tous les GPU de box. Le toggle promis par BootGuard est
  désormais effectif, pour tout le monde.
- **Écran de lancement SOMBRE** (#101010 + logo centré) pour LaunchTheme ET
  NormalTheme, `drawable(-v21)` + `values(-night)` : fin de l'écran blanc
  du template `flutter create` pendant l'init moteur sur box lente.
- **Paysage verrouillé au niveau Android** (`screenOrientation=landscape`)
  en plus du verrou Dart : plus de re-layout portrait→paysage au boot.
- **`uses-feature` non requis** (micro, caméra, portrait, faketouch) : des
  permissions de plugins impliquaient des features « required » → certains
  launchers/stores TV cachaient ou refusaient l'app.
- **`targetSdk = 35` explicite** : ne dépend plus du défaut du SDK.

### À savoir
- Le build TV (APK sideload + AAB) se déclenche sur push (paths workflow) ;
  publication box = dispatch manuel `publish-cinema-test` + `publish-tv-update`
  (inchangé). Le mobile garde son CI/moteur : AUCUNE autre app touchée.
- Ne PAS remettre `channel: stable` sans revalider API 21 + rendu sur box
  réelle ancienne.

### Suite de session : « l'image ne vient pas » → DOUBLE CHEMIN DE RENDU vidéo
Retour client après les correctifs de démarrage : les deux apps TV s'ouvrent
mais **l'image vidéo n'arrive pas** dans le lecteur. Cause structurelle : le
lecteur (packages/native_video_player) rendait la vidéo dans une SurfaceView
en hybrid composition — une fenêtre Android SÉPARÉE que le compositeur de
certaines box rate (l'UI Flutter, elle, s'affiche). Aucun chemin unique ne
couvre 100 % du parc (la SurfaceView avait justement été choisie pour une
box où la texture mpv/libVLC restait noire).

**Correctif « une bonne fois pour toutes » : les DEUX chemins + bascule auto.**
- Mode **texture** (NOUVEAU DÉFAUT) : ExoPlayer décode vers une SurfaceTexture
  Flutter → la vidéo suit le MÊME pipeline que l'interface. Partout où l'app
  s'affiche, l'image vient. Sous-titres remontés en texte (« cueText ») et
  dessinés en overlay Flutter.
- Mode **surface** (secours) : le chemin SurfaceView historique, inchangé.
- **Watchdog** dans le widget : lecture en cours (son/position OK) mais
  aucune 1re trame après ~6 s → bascule sur l'autre chemin, ré-attache le
  controller (la dernière URL est rejouée seule) et **MÉMORISE** le chemin
  qui marche (SharedPreferences natives, par box). Une bascule max par vue
  (anti ping-pong).
- API : NativeVideoRender.mode()/setMode() ; canal info
  createTexturePlayer/disposeTexturePlayer/get-setRenderMode ; canaux lecteur
  « native_video_player/t<textureId> » (espace distinct des PlatformViews).
- AUCUN écran modifié : NativeVideoView décide seul de son chemin (lecteur,
  aperçus, multivue, diagnostic — tous couverts).

### Suite de session : « Seven Motion TV » ressuscitée (2e app TV, on garde TOUT)
Le client a précisé que l'app visée s'appelle **Seven Motion TV**
(`com.sevenmotion.tv.seven_tv`, label « 7 MOTION TV ») : l'app TV de juin
2026 (job `build_tv_flutter` de build-android.yml, supprimé ensuite avec la
release `seventv-latest` et les routes Worker /7tv /seventv — mais les box
installées l'ont toujours). Décision : ON GARDE LES DEUX apps TV.
- **`.github/workflows/build-seventv.yml`** (nouveau) : même code
  (main_tv.dart), identité historique conservée, TOUT le blindage compat
  de build-tv.yml (Flutter 3.32.x épinglé, Impeller OFF, splash sombre,
  paysage, minSdk 21 + v1/v2/v3, targetSdk 35, largeHeap, plugins alignés)
  **plus 2 correctifs propres** : APK **universel ARM 32+64** (l'ancien job
  était arm64-only → refus d'installer sur box/sticks 32 bits) et
  **signature stable** (l'ancien job signait avec un keystore debug
  ALÉATOIRE par run → MAJ par-dessus impossibles). ⚠️ Les installs de juin
  devront être réinstallées UNE fois (clé différente), ensuite MAJ normales.
  Publication opt-in : dispatch avec `publish=true` → release
  `seventv-latest` (seven-tv.apk + version.json, updater aiguillé par
  `TV_UPDATE_TAG=seventv-latest`).
- **`cloudflare/worker.js`** : routes /7tv, /seventv (+ /sevenmotion)
  ressuscitées → `seventv-latest/seven-tv.apk` (fichier client
  « SevenMotionTV.apk ») ; ajoutées à RESERVED. Redéployer le Worker
  (workflow deploy-worker) pour activer.

---

## Session (2026-07-17) — EPG « En direct » enfin visible + aperçu cliquable

Branche : `claude/autonomous-mobile-tv-release-r21jqf` (reprise de
`claude/maison-mere-phone` au commit 9f1ce58). Demande client depuis une
capture de l'écran **En direct** : sous l'aperçu, « ça doit venir les
émissions qui suivent (nos événements) » et « la petite vidéo doit être
cliquable ».

### Cause racine « Programme non disponible » (chaînes Xtream)
Le XMLTV du panel identifie ses chaînes par `epg_channel_id` (« TF1.fr »)
alors que nos chaînes Xtream s'appellent `xtream-<stream_id>` → AUCUN
programme importé ne matchait jamais une chaîne (boîte noire : import_ok
avec count=0 et known élevé). Corrigé par un **pont d'alias** :
- `XtreamClient` collecte `epg_channel_id → xtream-<id>` pendant l'import
  live (borné anti-OOM), exposé via `epgChannelAliases`.
- `EpgRepository` : table `epg_aliases`, le filtre du parseur XMLTV est
  élargi aux SEULS ids EPG des chaînes connues (jamais d'élargissement
  sauvage) et chaque programme est rangé sous l'id de SA chaîne à
  l'insertion (`mergeKnownWithAliases` / `remapProgramRow`, pures/testées).
- `PlaylistRepository` persiste les alias à l'ajout ET au refresh Xtream.

### Repli EPG courte (get_short_epg)
`ShortEpgService` : quand le XMLTV local ne connaît pas la chaîne, on
demande au panel ses « maintenant + suivants » — appel API léger (JAMAIS
une connexion de flux → comptes 1-conn respectés), cache mémoire 10 min
positif/négatif, best-effort. `parseShortEpgListings` pur (base64 ou clair,
timestamps, entrées invalides ignorées) testé sur 4 cas.

### UI aperçu En direct
- Section **« NOS ÉVÉNEMENTS »** (en-tête) au-dessus des émissions à venir
  (en cours en or + suivantes), qui bascule sur le repli get_short_epg
  quand le XMLTV est muet.
- **Vignette d'aperçu cliquable** : un tap ouvre le plein écran
  (GestureDetector pur, aucun FocusNode → parcours D-pad TV inchangé).

### Gates
`flutter analyze` 0 erreur ; 8 nouveaux tests verts (`epg_alias_short_epg`) ;
suite locale : les seuls échecs sont les tests sqflite_ffi (binaire sqlite3
non téléchargeable dans le sandbox — CI les passe). Fichiers DLNA +
`local_hls_relay` intacts ; aucun import media_kit ajouté (build TV sain).

---

## Dernière session (2026-07-16 → 17) — « SEVEN CINÉMA » : le côté Films & Séries niveau plateforme premium

Branche : `claude/seven-cinema-vod-venljh` (partie du HEAD
`claude/tv-channels-live-preview-24f338`). 5 phases livrées, chacune
commit + push + CI Quality verte. 542 tests (499 → 542), analyze 0 erreur.

### Phase 1 — Données : VOD unifié Xtream + M3U
- `M3uVodClassifier` (vod/domain) : entrées M3U enfin classées
  live/film/épisode d'après l'URL (chemins /movie/ /series/, extensions
  fichier fini ; SxxExx et 1x03 parsés). Conservateur : doute = live.
- Parser M3U pose `isLive:false` sur les fichiers VOD → ils SORTENT des
  listes live (requêtes is_live=1) et ENTRENT au Cinéma.
- `PlaylistRepository.getVodChannels()` : lecture bornée + rattrapage SQL
  des bases importées avant la classification + filtre Red Room.
- `VodRepository`/`SeriesRepository` fusionnent part Xtream (mémoire→
  disque→réseau, inchangé) et part M3U (SQLite) ; séries M3U regroupées
  par nom, épisodes servis en LOCAL (`m3useries-…` dans fetchDetail),
  ids `ep-…` = contrat AutoplayPolicy conservé.
- `CinePerf` (tv/data) : chronos budgets (accueil<400 ms, fiche<300 ms,
  Regarder→1re frame<2500 ms) → Boîte noire tag « perf », WARN si dépassé.
- `TvPosterPrefetch` (tv/core) : pré-chargement borné des jaquettes.

### Phase 2 — Accueil Cinéma
- Mémoire d'état ENTRE onglets (Films et Séries) : scroll vertical +
  offset de CHAQUE rangée (PageStorage sur bucket statique) + l'affiche
  focusée reprend l'autofocus au retour. Zéro jank au retour.
- Pré-chargement des jaquettes de la rangée SUIVANTE au focus.
- Chrono homeFirstRender branché (arrêt à la frame réellement affichée).

### Phase 3 — Fiches
- Fiche film : rail « Titres similaires » (même catégorie, depuis le
  cache, zéro réseau ; pushReplacement pour butiner) + chrono detailOpen.
  Clé i18n `tvSimilar` ×8.
- Fiche série : vignettes d'épisodes 16:9 (XtreamClient parse désormais
  `info.movie_image`, défensif) ; le DERNIER spinner du Cinéma remplacé
  par un squelette de rangées.

### Phase 4 — Lecture
- Double-appui Gauche/Droite (<500 ms, même sens) : pas de seek 10→30 s.
- Bulle de PREVIEW du temps cible au-dessus de la barre pendant le seek.
- Pastille « Épisode suivant » sur les 30 dernières secondes d'un épisode
  (OK = enchaîner, rien = générique ; cachée quand la barre s'ouvre).
  Clé i18n `tvNextEpisode` ×8.
- TTFF mesuré : chrono à l'appui Regarder (fiche/accueil/reprise/épisode),
  arrêté à la 1re image (_onPlayer), annulé si sortie avant.
- CORRECTIF : la VOD (mp4/mkv) ne passe PLUS par le relais local (tuyau
  TS live SANS Range — son propre contrat le dit) → seek/reprise fiables,
  ExoPlayer direct gère Range + reconnexion. HLS inchangé, live inchangé.

### Phase 5 — Polish
- RepaintBoundary autour des affiches (zoom focus ne repeint que la carte).
- `TvCineRoute` : fondu + glissement 220 ms (GPU pur) pour catalogue →
  fiche → lecteur (le reste de l'app garde ses transitions).
- Tests widgets : TvFocusable (focus/OK/zoom/flèches), TvSkeletonRails et
  TvEmptyState (« zéro spinner »).

### Phase 6 — Téléchargements intelligents (2026-07-17, déployé tv-prod)
- `vod_download_service` refondu : file SÉRIELLE (un job à la fois),
  COURTOISIE RÉSEAU (`setPlaybackHold` depuis le lecteur — jamais 2
  connexions sur un compte 1-conn ; lecture LOCALE libère le réseau),
  smart downloads (épisode vu → fichier supprimé + suivant en file,
  toggle persisté ON), garde d'espace `df -k` (500 Mo start / 200 Mo
  en route → statut noSpace), épisodes téléchargeables (isEpisode,
  groupName).
- Lecteur : substitution hors-ligne D'ABORD (`localFile` → file://,
  démarrage instantané, zéro mécanique distante) ; fin d'épisode →
  `onEpisodeWatched` à côté du markFinished.
- UI : rangée « Téléchargés » (lecture directe), appui long épisode =
  télécharger (pastille ✓/%), écran Téléchargements (toggle smart +
  espace libre), id D'ORIGINE en lecture offline (reprise partagée).

### Correctifs terrain + thème (2026-07-17)
- « LIGNES JAUNES » (photos client) = Material MANQUANT (texte de
  secours Flutter jaune souligné monospace) sur 3 chemins : TvCineRoute,
  lanceur `_open`, lecteur TV → Material transparent posé aux trois.
- CINÉMA EN ROUGE BRAISE (demande client) : tokens `ember*` +
  `cineGradient` (#D63A30) sur Films/Séries/Fiche/Recherche/
  Téléchargements + commandes VOD du lecteur. Le LIVE garde l'or.
- Crash « film ne s'ouvre pas » (box à jour du 16 au soir) : la VOD
  passait par le relais live → réglé par « VOD hors relais » (Phase 4).

### Phase 7 — Philips Hue : mode salle de cinéma (2026-07-17)
- `lib/features/hue/data/hue_service.dart` : découverte SSDP locale du
  pont (signature hue-bridgeid), association par bouton physique
  (fenêtre 30 s, clé persistée), scène rouge braise via groupe 0
  (bri 36, hue 1500), pause → bri 90, sortie → restauration EXACTE par
  lampe (colormode ct/hs respecté, éteintes restent éteintes). Zéro
  cloud, zéro dépendance, best-effort partout.
- `tv_hue_screen.dart` (Réglages TV → Lumières Philips Hue) :
  rechercher / associer avec compte à rebours / activer / tester 4 s.
- Hooks lecteur VOD only : start (cinemaStart idempotent), pause/resume,
  dispose (cinemaEnd). 13 clés i18n × 8 langues. Tests parsing +
  restauration (583 tests verts au total).

### CI utilitaire
- `publish-cinema-test.yml` (sur main, workflow_dispatch, input run_id) :
  publie l'APK d'un run build-tv en prérelease `cinema-test` à LIEN
  DIRECT (Downloader sans compte GitHub). Jamais « latest ».

### À savoir / reste à faire côté Cinéma
- Les MESURES réelles des budgets s'observent sur box via la Boîte noire
  (tag « perf ») — pas de box dans l'environnement de dev, chiffres à
  relever sur le terrain.
- Bases existantes : la reclassification M3U joue au prochain
  refresh de playlist ; en attendant, getVodChannels rattrape par URL.
- Idées suivantes : sous-titres externes .srt (VOD), reprise
  cross-appareil, préchargement du prochain épisode pendant le générique.

---

## Session PARALLÈLE (2026-07-16 soir) — Mission casting : fondation fMP4 (AC-3 vrais Chromecast)

Branche de session : `claude/7motion-casting-arch-w56et4` (reprise de
`claude/maison-mere-phone`, mêmes commits repoussés vers les branches
maison-mère + miroir une fois la CI verte).

### Enquêtes (sous-agents, vérifiées sur le code)
- **Crash « The Few s'est fermée »** : cause racine identifiée = R8
  effaçait les génériques Gson de flutter_local_notifications ; quand
  une alarme de notification sonnait (nudge quotidien 20 h, rappel
  EPG, reboot), `ScheduledNotificationReceiver` mourait HORS des
  filets Dart → fermeture sèche. **Le correctif existe déjà**
  (`4e8eeb0`, règles keep com.dexterous/TypeToken dans
  ci/proguard-rules.pro) mais la release téléphone étant manuelle,
  **les clients tournent probablement encore sur l'APK d'avant** →
  publier via build-android `make_release=true` (accord client).
  Bonus détectés : nudge « 20 h » sonne à 20 h UTC (tz.local jamais
  posé — bug UX, pas cast, à traiter plus tard).
- **Carte audio du cast** : sauvetage TV-directe limité à
  `kRescueAudio = {ac3, eac3, dts}` ET aux seuls SHIELD/NVIDIA
  (`isExoPlayerReceiver` ne matche pas les dongles Google TV malgré le
  commentaire). Trous réels : VRAI Chromecast × AC-3/E-AC-3 (aucune
  issue : CORS interdit la TV-directe, mux.js refuse le Dolby) et MP2
  partout (échec silencieux : vidéo sans son, pas d'exception → pas de
  sauvetage possible). Aucun code fMP4/transcodage n'existait.

### Fait cette session
- **Fondation fMP4** (`lib/features/cast/data/fmp4/`, ~2 700 lignes
  avec tests, NON branchée au chemin de production) : ré-emballage
  segment TS → segment fMP4 pur Dart — Shaka lit le fMP4 SANS mux.js,
  l'AC-3/E-AC-3 passe en passthrough sur les vrais Chromecast.
  Modules : audio_frames (trames AC-3/E-AC-3/ADTS + dac3/dec3/esds),
  ts_es_extractor (démux PES persistant, PES bornés émis à longueur
  déclarée, PES à cheval reportés), h264_annexb (AVCC, avcC, SPS),
  fmp4_writer (moov/moof/mdat, tfdt 64 bits), fmp4_remuxer (façade,
  horloges 33 bits déroulées, base audio continue, reliquats reportés,
  init régénérée sur changement de config). Tests bout-en-bout sur TS
  synthétiques (SPS réel bit à bit, trames AC-3 valides, wrap 33 bits,
  discontinuités, MP2 signalé/retiré, HEVC refusé).
- **Observabilité récepteurs** : `google.load_media` et
  `relay_audio.fallback_direct_tv` journalisent désormais
  `receiverModel`/`receiverMaker` bruts — la boîte noire dira ce que
  les box du terrain annoncent AVANT d'élargir isExoPlayerReceiver.
- **Contrat verrouillé** : `kRescueAudio` promue constante de classe
  testée (≠ kUntransmuxableAudio) ; commentaire R8 corrigé (les
  workflows passent en réalité proguard-android-OPTIMIZE.txt).

### Suite (2026-07-17) — release publiée + verdict terrain + correctifs LG
- **Release téléphone « prod » publiée** (run #1090, accord client) avec
  le fix crash R8 — installable via Réglages → Vérifier les mises à jour.
- **Boîte noire client reçue** (LG QNED816QA + SHIELD, panel
  business-cdn-8k) : SHIELD **8/8** (100 %, 8,1 s de moyenne, relais
  gagnant partout, audio AAC sur tout l'échantillon — pas d'AC-3
  rencontré) ; LG DLNA **5/8** (21,6 s de moyenne). Causes LG lues dans
  les logs : TV verrouillée sur le cast précédent (fault UPnP 701
  « Transition not available »), ~45 s d'essais perdus par chaîne
  (stratégie gagnante jamais mémorisée), « limite atteinte » (la TV
  tire encore l'ancien flux pendant le pré-vol). Post-mortem : une
  chaîne HEVC échoue via relais TS sur SHIELD (CAF exige du fMP4 pour
  le HEVC → argument de plus pour le chantier fMP4). Chaînes TENNIS
  EVENT 1 / FRANCE 3 : le panel sert `black.ts` (placeholder) au probe.
- **Correctifs livrés (chemin DLNA uniquement, Chromecast intouché)** :
  1. Rattrapage 701 dans `UpnpAvTransport.playStream` : Stop appuyé +
     attente réelle de libération (6 s) + UNE nouvelle chance de
     SetAVTransportURI (event boîte noire `dlna.transition_recovery`) ;
     `_parseSoapFault` remonte aussi `errorCode` nu (« code UPnP 701 »).
  2. Stop DLNA best-effort (borné 3 s) AVANT le pré-vol dans
     `_castToInner` — miroir du réflexe Chromecast (contention
     1-connexion).
  3. Souvenir de la STRATÉGIE GAGNANTE par TV (`_DlnaPathMemo`,
     TTL 15 min, prioritaire si plus frais que le dernier échec,
     oublié sur échec total) — event `failover.start_at_winner`.
  4. Diagnostic : garde anti-doublon dans `DiagnosticBatchRunner`
     (sessions dupliquées du rapport = diag périmé ramassé après un
     timeout global).
  Tests : faux renderer DLNA HTTP (701 rattrapé/persistant/code nu/716
  non rattrapé) + souvenir de victoire (5 cas purs).

### Prochaines étapes (mission casting)
1. Vérifier au prochain export client que la LG remonte à ~8/8 et que
   `dlna.transition_recovery` / `failover.start_at_winner` apparaissent.
   Corréler `ready_audio_at_risk` ↔ plaintes quand une chaîne AC-3 sera
   dans l'échantillon.
2. **Brancher le fMP4** derrière une garde stricte : récepteur web
   (non-ExoPlayer) ET audio ∈ {ac3, eac3} — population qui échoue à
   coup sûr aujourd'hui — avec repli TS inchangé et kill switch.
   Playlist : #EXT-X-MAP + master avec CODECS= (local_cast_server).
3. Publier la release téléphone (fix crash) avec accord client.
4. MP2 : décision transcodage (MediaCodec AAC ? taille APK) après
   lecture boîte noire ; élargissement isExoPlayerReceiver sur preuves.

---

## Session précédente (2026-07-16) — Cast increvable + fluidité + pistes TV

Branche de travail : `claude/maison-mere-phone` (miroir
`claude/tv-channels-live-preview-24f338`). Tout est vert (analyze +
497 tests locaux) et poussé. Ce qui a été fait :

### Cast (priorité client)
- **Vague B — télécommande pure** : pendant un cast, zapper change la
  chaîne SUR LA TV (jamais de reprise locale — c'est ce qui ouvrait
  2 connexions et cassait la stabilité). Nouveau
  `CastManager.castChannelOnCurrentSession` + contexte de zap partagé
  (`setCastPlaylist`, `zapCastNext/Prev`, `canZapOnCast`) ; garde
  centralisée dans `_applyZap` ; Ch+/Ch- dans l'overlay du lecteur ET
  la mini-barre globale ; fin de la reprise locale automatique en
  fin/échec de cast (Lecture = reprise explicite).
- **Keepalive écran éteint** : POST_NOTIFICATIONS désormais demandée
  sur le chemin cast (Android 13+ supprimait la notification → kill
  OEM) ; le natif remonte le VRAI résultat de startForegroundService
  (avant : `keepalive_started` menteur dans la boîte noire).
- **Audio du relais HLS** : discontinuités PCR INTRA-connexion enfin
  signalées (#EXT-X-DISCONTINUITY — c'était la désynchro/son haché) ;
  AC-3/E-AC-3/DTS en stream_type 0x06 correctement étiquetés
  (descripteurs DVB parsés) ; WARN boîte noire
  `hls_relay.ready_audio_at_risk` quand le codec audio n'est pas
  transmuxable par le Default Media Receiver (mp2/ac3/eac3/dts/
  aac-latm/private → l'explication du « la voix n'est pas bonne » ;
  mux.js ne re-emballe que AAC/MP3). Piste restante si le terrain le
  confirme : router ces flux vers direct_tv, ou transcodage.

### Fluidité TV (suite de l'audit)
- Guides EPG : futures mémorisés (tv_timeline_guide, tv_guide) — le
  tic 30 s ne re-tape plus SQLite ; anti-rebond 250 ms + cache
  synchrone dans tv_guide_grid ; aperçu tivimate_home en
  ValueNotifier (plus de setState d'écran au focus).
- Images : décodage borné (cacheWidth) posters Cinéma, backdrop héros,
  logos incrustés du lecteur.
- Sync EPG : parse XMLTV dans un ISOLATE dédié
  (`XmltvParser.parseInIsolate`, streaming conservé, inserts SQLite
  sur l'isolate principal par lots de 500).

### Stabilité « ne jamais fermer »
- Purge `didHaveMemoryPressure` généralisée à TOUS les flavors
  (`_MemoryPressureGuard` dans guarded_main).
- `local_stream_relay._handleRequest` : fermeture de réponse GARANTIE
  (try/finally — fini les sockets zombies → OOM lent).
- Frontières de session cast : `on Exception` → `on Object` (les
  Error ne laissent plus de sessions zombie ni ne privent du repli
  local).

### Lecteur TV — feuille « Pistes & format d'image »
- Nouveau bouton « Pistes » (5e) → panneau latéral focus-émulé :
  pistes AUDIO (langues localisées), SOUS-TITRES (+ Désactivés),
  FORMAT D'IMAGE (Contenir/16:9/4:3/2.39/Étirer/Remplir — fini le
  16:9 figé). Sélection via TrackSelectionOverride ExoPlayer (zéro
  rebuild), ratio 100 % Flutter, persistance PlayerSettings. Le natif
  remonte désormais le code langue (`language`) dans l'événement
  `tracks`.

### Reste à faire (classement mondial — cf. audit)
- Enregistrement planifié depuis l'EPG (RecordingService existe, il
  manque le bouton « programmer » dans le guide).
- Décalage audio + offset sous-titres ; sous-titres externes .srt
  (VOD) ; reprise cross-appareil ; catégories personnalisables +
  verrou PIN ; multi-vue 4 flux.
- Audio cast : valider sur le terrain la corrélation
  `ready_audio_at_risk` ↔ plaintes son, puis décider (routage
  direct_tv prioritaire pour ces codecs, ou transcodage).

---

## Qui je suis (toi, Lionel)

- Fournisseur et revendeur IPTV qui veut son propre lecteur premium
- Domaine : **7themotion.com** (acheté chez Hostinger, géré par Cloudflare)
- Repo GitHub : `manzilionellm-dotcom/tvking` (branche `claude/premium-iptv-redesign-xYNVd`)
- Mon support officiel = numéro WhatsApp `+1 807 788 8909` MAIS jamais nommé
  "WhatsApp" dans l'UI — branding "Concierge / Support" uniquement

---

## Identité des produits

Deux apps dans le MÊME repo (flavors Flutter) :

### 7 MOTION (flavor principal, grand public)
- **Tagline** : "THE FEW · NOT FOR EVERYONE"
- **Branding** : Maison Noir — fond charbon `#0A0A0C`, accent ember
  rouge `#D63A30`, texte ivoire `#F0EDE9`. Jamais Netflix-red ni néon.
- **Logo** : 7 rouge sur noir + badge bleu vérifié à côté du wordmark
- **Modèle commercial** : 13 €/an sur 7themotion.com, paiement EXTERNE
- **Package Android** : `com.manzilionellm.tvking`
- **Entrypoint** : `lib/main.dart`
- **Téléchargement** : `99999.7themotion.com/dl`

### Red Room (flavor adulte 18+)
- **Tagline** : "STRICTLY 18+ · AFTER HOURS"
- **Branding** : R rouge sang sur velours noir
- **Restrictions** : seules les chaînes [ChannelGenre.adult]
  apparaissent (filtre au niveau `PlaylistRepository.getAllChannels`).
  Biométrie OBLIGATOIRE à chaque cold start. Gate "j'ai 18+" au
  premier lancement. Pas de Play Store (politique Google).
  Pas d'iOS (politique Apple).
- **Package Android** : `com.redroom.player` (différent → cohabite
  avec 7 MOTION sans collision sur le téléphone)
- **Entrypoint** : `lib/main_redroom.dart`
- **Téléchargement** : `99999.7themotion.com/redroom`
- **Aiguillage** : `lib/core/flavor/flavor.dart` →
  `FlavorConfig.current.{adultOnly, biometricMandatory, requireAgeGate}`

---

## Architecture en place

### Backend (Cloudflare)
- **Worker** `lively-voice-7cb0` sur dash.cloudflare.com
- **Custom Domains** actifs : `99999.7themotion.com` (le domaine
  racine `7themotion.com` n'est pas encore branché à cause de
  DNS records Hostinger résiduels à supprimer)
- **KV namespace** : `KV_7MOTION` — stocke `client:<MAC>` avec
  `{name, playlists, status, paid, trial_until, note, last_seen_at,
  added_at, updated_at}`
- **ADMIN_SECRET** : variable env du Worker (set via wrangler)

### Endpoints publics
- `GET /` → landing page (téléchargement APK)
- `GET /dl` → 302 vers APK GitHub release `latest`
- `GET /1`, `/666666`, `/leo`, etc. → 302 vers APK (codes vanity)
- `POST /api/heartbeat` → l'app pingue avec son MAC, crée fiche
  trial 10 j si nouveau
- `GET /api/status/:mac` → l'app lit son statut courant
- `GET /config/:mac` → playlists assignées par l'admin

### Endpoints admin (auth X-Admin-Secret)
- `GET/POST /admin/clients` → CRUD
- `GET/PUT/DELETE /admin/clients/:mac`
- `POST /admin/clients/:mac/action` (freeze, unfreeze, ban,
  mark_paid, mark_unpaid, renew, note)
- `GET /admin/panel` → HTML autonome du panel web

### App Flutter
- **Player** : media_kit (libmpv)
- **Repos** : SQLite via `sqflite`
- **Identité device** : MAC virtuel `MK:XX:XX:XX:XX:XX` généré au
  1er boot, persisté en SharedPreferences
- **Trial** : SubscriptionState ping le backend au boot,
  fallback local 10 j si serveur down
- **Cast** : DLNA + Chromecast + QR (retiré du player) — clé
  Chromecast prévue à l'achat
- **PiP natif** : MainActivity.kt + MethodChannel `tvking/pip` +
  WakeLock + WifiLock pour enregistrement en background

---

## Décisions UX importantes

1. **WhatsApp est INVISIBLE** — le bouton VIP ouvre un sheet à
   2 choix ("Message instantané" / "Appel téléphonique"). Au tap
   sur Message, WhatsApp s'ouvre en silence. Pas de vert WhatsApp,
   pas du mot "WhatsApp" dans l'UI.

2. **Rotation auto SUIT le téléphone** — pas de forçage paysage.
   Style YouTube/Netflix : tel en portrait = vidéo portrait avec
   bandes, tel en horizontal = paysage plein cadre. Ça marche
   même si auto-rotate système OFF.

3. **PiP au BACK** — appuyer sur BACK pendant la lecture met la
   vidéo en mini-fenêtre flottante au lieu de fermer le player.
   YouTube canonique.

4. **Enregistrement continue en background** — WakeLock + WifiLock
   acquis par le ForegroundService AVANT le download HTTP.

5. **Section 'Mes sources IPTV' dans Réglages** — l'user peut
   ajouter ses propres playlists M3U/Xtream en plus du système
   revendeur (push à distance).

6. **Système revendeur intégré** — Toi tu pushes les playlists
   depuis le panel admin, le client reçoit auto via heartbeat.
   En parallèle, le client peut ajouter ses propres URLs.

---

## Bugs résolus récemment

- ✅ Overflow header player (badge LIVE) → `FittedBox(scaleDown)`
- ✅ Rotation auto qui suivait pas le téléphone
- ✅ Cast par QR ne marchait pas sur navigateur ordi → page HTML5
  du LocalCastServer joue le flux via hls.js / mpegts.js
- ✅ Enregistrement s'arrêtait quand on quittait l'app → WakeLock
  + WifiLock dans le service Kotlin
- ✅ PiP n'existait pas → implémentation native via MainActivity.kt
- ✅ Bouton QR retiré du header player (preference user)
- ✅ Mentions WhatsApp retirées partout
- ✅ **Enregistrement s'arrêtait après ~2 min** → cause : les CDN/Xtream
  ferment périodiquement la socket HTTP (`onDone`), l'ancien code
  nettoyait le job au lieu de reconnecter. Fix dans
  `http_recording_downloader.dart` : reconnexion auto sur coupure
  (raw + HLS, back-off progressif), plafond max **6 h**
  (`kMaxRecordingDuration`), callback `onAutoStopped` +
  `finishRecordingByPath` pour finaliser proprement la fiche en base.

- ✅ **Cast Chromecast — page receiver morte au parsing (2026-07-05)** :
  `cast_receiver.js` est un template literal ; le `join('\n')` de
  l'overlay debug produisait un VRAI retour à la ligne dans la page
  générée → SyntaxError → `context.start()` jamais appelé → AUCUNE
  session Cast possible depuis le commit overlay (eee9b56). Corrigé
  (`\\n`) + garde-fou : `node --check` sur les scripts générés.
- ✅ **Cast Chromecast — sender aveugle en lecture TS (2026-07-05)** :
  le LOAD interceptor `return null` (mpegts.js) ne répondait JAMAIS au
  téléphone : pas de MediaStatus → `RemoteMediaClient.load()` sans
  réponse → l'app déclarait « échec » à 25 s TV allumée, et
  pause/stop étaient morts. Fix pattern « custom player » officiel :
  interceptor MEDIA_STATUS sortant (playerState/media/mediaSessionId
  réels du `<video>` TS) + `broadcastStatus(true, requestId)` pour
  acquitter LOAD/PAUSE/PLAY/STOP + events video → broadcast.
- ✅ **Cast Chromecast — live TS sans reconnexion (2026-07-05)** : les
  serveurs IPTV ferment périodiquement la socket ; le receiver fige
  → reconnexion auto (backoff 1→5 s, 6 tentatives, compteur remis à
  zéro sur lecture stable), sinon IDLE/ERROR propre vers le sender.
- ✅ **mpegts.js servi même origine (2026-07-05)** : `/vendor/mpegts.js`
  (Worker, cache edge, version épinglée 1.7.3, repli unpkg puis CDN
  direct) — un CDN tiers bloqué sur le réseau TV ne tue plus le TS.
- ✅ **Découverte — MulticastLock tenu en quasi-permanence (2026-07-05)** :
  le stream SSDP ne se terminait jamais au timeout (flag `done` relu
  seulement à l'arrivée d'un device) → socket UDP + lock multicast
  vivants ~60 s/60 s en warmup (batterie). Fix : `controller.close()`
  à la deadline + annulation des subscriptions au timeout côté
  `CastManager.startDiscovery`.
- ✅ **Warmup écrasait l'état `connecting` (2026-07-05)** : le tick 60 s
  pouvait lancer une découverte pendant un `castTo` (40 s max) et
  corrompre l'UI. Garde `connecting` ajoutée.
- ✅ **Session Cast terminée par la TV : bouton restait « connecté »
  (2026-07-05)** : l'événement natif `ended` ne nettoyait pas
  `_device/_selectedDevice/_transport`. Corrigé.
- ✅ **Toast après `Navigator.pop` dans le picker (2026-07-05)** :
  `ScaffoldMessenger.of(context)` sur un context désactivé → capture
  du messenger avant le pop.

## Bugs connus / pas encore résolus

- ⚠️ Domaine racine `7themotion.com` pas encore Custom Domain
  du Worker (DNS records Hostinger à supprimer)
- ⚠️ APK 207 Mo en debug — release sera plus petit mais à optimiser
- ⚠️ Pas encore de panel admin Flutter étendu (le web suffit)
- ⚠️ Cast officiel Chromecast pas encore testé (attente clé)

---

## Temps réel app ↔ panel + panel intelligent (2026-07-11)

Branche : `claude/app-panel-intelligence-77azr1`. Contrat complet dans
`docs/REALTIME-PROTOCOL.md`. Tout est FAIL-OPEN : sans WebSocket, l'app
et le panel se comportent exactement comme avant (polling conservé).

- **Hub temps réel** : Durable Object `RealtimeHub` (`cloudflare/realtime.js`),
  binding `RT_HUB` + migration dans wrangler.toml (plan gratuit OK,
  `wrangler deploy` suffit). WS appareils `/api/rt/device`, WS panel
  `/api/v1/rt/ws?token=JWT`.
- **Instantané** : chaque mutation du panel (activation, gel, ban, push
  playlist, transfert, annonces, thème, tarifs, force-update…) publie un
  `sync` vers le(s) appareil(s) visé(s) → l'app re-fetch en <1 s au lieu
  de ~30 min. Réponses HTTP enrichies de `rt:{delivered,id}` ; l'appareil
  renvoie un `ack` → le panel affiche « ✓ Appliqué en X ms ».
- **App Flutter** : `lib/core/realtime/realtime_sync_service.dart`
  (dart:io WebSocket, AUCUNE dépendance nouvelle), reconnexion backoff
  5→120 s, re-check au retour au premier plan, bannière messages admin
  (`admin_message_banner.dart`), annonces et force-update appliqués EN
  DIRECT (signaux `revision` sur AnnouncementRepository /
  ForceUpdateChecker). Branché dans main / main_tv / main_windows /
  main_tizen (main_prive hérite du mobile).
- **Panel** : présence en direct (page En ligne fusionne WS + présence
  HTTP — les vieux APK comptent toujours), pastille verte temps réel sur
  Devices, envoi de message / forcer la synchro depuis la fiche appareil,
  Dashboard avec section « À traiter » (`GET /api/v1/insights` : licences
  qui expirent sous 7 j, essais qui finissent sous 48 h, payants muets
  depuis 7 j, nouveaux du jour), indicateur ● Direct / ○ Différé dans la
  sidebar, tokens Tailwind `success`/`warning` enfin définis (les confirmations
  vertes étaient invisibles avant).
- **Revue** : 8 angles + corrections appliquées (anti-spoof X-RT-IP,
  socket fantôme au timeout de connexion, latence « null ms », publishes
  parallélisés, requêtes insights en batch + dédup par MAC, etc.).
- Vérifié : `flutter analyze` 0 erreur, 194/194 tests, build panel vert,
  smoke tests worker 6/6 + realtime 11/11.

---

## App Licensing Platform (Phase 1.A — démarrée)

Nouvelle plateforme centrale pour gérer toutes les apps du portfolio
(7 MOTION, Red Room, futures). Cf. brief utilisateur "SaaS App
Licensing Platform" — Shopify/Stripe/Firebase pour ses apps.

### Stack
- **Backend** : Cloudflare Worker existant + nouveau module
  `cloudflare/api_v1.js` (namespace `/api/v1/*` parallèle aux endpoints
  legacy `/admin/*` et `/api/*` qui restent intacts pour compat ascendante).
- **Base de données** : nouvelle Cloudflare **D1** (`tvking_licensing`).
  Schéma complet dans `cloudflare/schema.sql` (apps, customers, devices,
  licenses, playlists, payments, audit_logs, notifications, resellers,
  admin_users).
- **Migration KV → D1** : `cloudflare/migrate_kv_to_d1.js` exposé via
  `POST /admin/migrate-to-d1` (idempotent, supporte `{dry_run: true}`).
- **Frontend admin** : `admin-panel/` — React + Vite + Tailwind à
  déployer sur Cloudflare Pages (build command : `cd admin-panel &&
  npm install && npm run build`, output : `admin-panel/dist`).

### Setup user one-time (à faire dès que tu installes Node + Wrangler)
1. `cd cloudflare && wrangler d1 create tvking_licensing`
2. Paste l'`id` retourné dans `wrangler.toml` à la place de
   `REMPLACE_MOI_PAR_L_ID_D1`
3. `wrangler d1 execute tvking_licensing --remote --file=schema.sql`
4. `wrangler deploy` (deploy le Worker avec les nouveaux endpoints)
5. `curl -X POST https://<worker>/admin/migrate-to-d1
        -H "X-Admin-Secret: <secret>"
        -d '{"dry_run":true}'` pour simuler
6. Si OK → re-curl sans `dry_run` → la migration écrit dans D1
7. Connecter Cloudflare Pages au repo (cf. `admin-panel/README.md`)

### Pages disponibles Phase 1.A
- `/login` — auth JWT (bootstrap : email=`admin`, password=`ADMIN_SECRET`)
- `/` Dashboard — KPIs lus en direct de D1
- `/customers` — liste + recherche (lecture seule en 1.A)
- `/devices` — liste + recherche (lecture seule en 1.A)
- `/apps` — liste (lecture seule en 1.A)
- `/activations` — liste licenses (lecture seule en 1.A)
- `/playlists` `/renewals` `/payments` `/resellers` `/notifications`
  `/logs` `/settings` → stubs marqués "Soon" en sidebar

### Phase 1.B (prochaine session)
- Création/édition Customers/Devices/Apps complète (boutons "Nouveau")
- Formulaire **Activer un MAC** (MAC + App + durée 1m/3m/6m/1y/lifetime → 1 clic)
- Renouvellement de license (cumule les jours si renouvelé avant expiration)
- Push playlist Xtream à distance (chiffrement creds via Web Crypto AES-GCM)
- Filtres avancés sur licenses (status, app, expirant dans 7j)
- Audit logs en lecture

### Phases ultérieures (non démarrées)
- 1.C — Resellers (portal séparé + crédits + stats)
- 2 — Paiements Stripe/PayPal + webhook auto-create license + invoice PDF
- 3 — Customer self-service portal (account.7themotion.com)
- 4 — Cron auto-expire + auto-renew + notifs email via Resend
- 5 — Analytics avancées (revenue, top apps, top resellers, renewal rate)

---

## Anciennes étapes mobiles (gardées en backlog)
1. Cast Chromecast natif à tester (attente clé)
2. QA pass complet sur Fire TV / Android TV / téléphone
3. Bug enregistrement "stop à 1 min" à diagnostiquer (probablement
   limite 1 connexion par provider IPTV — cf. message user)

---

## Conventions de code (rappel — voir aussi AGENTS.md)

- **Pas de print()** — `debugPrint()`
- **Pas de couleurs hardcodées** — `AppColors.*` ou `LumiereColors.of()`
- **Commentaires en français, abondants** — projet pédagogique aussi
- **Pas de URL IPTV en dur** dans le code de prod
- **Tokens design** : `lib/core/theme/lumiere_tokens.dart`

---

## Comment ME briefer à la prochaine session

Tape juste :

> **"Lis STATUS.md et reprends. On en était à [ce que tu veux faire]."**

Et je relirai ce fichier, les derniers commits, et on continuera
sans perdre de temps en re-contexte.
