# Audit de production Zuno TV — 4 octobre 2026

Périmètre : l'app box **Zuno** (`android-app/lib/main_tv.dart`, écrans `lib/features/tv/`,
lecteur natif `packages/native_video_player/`). Point de départ : branche
`claude/zuno-complet` (`dac20f2b`, build vert, box de test versionCode 1791065876).
Branche de travail : `ccr-1d45eb8b-x46ieg`. Rien n'a été poussé sur `main`, la
release clients `zuno-tv` n'a pas été touchée (preuve en fin de document).

Vocabulaire des preuves, imposé par la mission :

- **PROUVÉ** : reproduit + corrigé + test exécuté qui passe.
- **FORTEMENT ÉTAYÉ** : preuve statique forte (lecture de code + tests partiels).
- **NON VÉRIFIÉ** : plausible, mais seule une box peut le confirmer.

Aucune box, aucune chaîne IPTV, aucun HDMI n'a été mesuré ici : toute métrique
« sur l'appareil » est **NOT MEASURED**.

## 1. Verdict

**NEAR-READY.** Le code des chemins critiques (lecteur natif, zapping, focus audio,
retour d'arrière-plan, reconnexion) est borné, protégé par jetons de session et
testé hors appareil. Les défauts trouvés et corrigés ici ne sont pas des crashs du
lecteur : ce sont des fuites d'identifiants dans le journal local, un fsync par
ligne sur le fil UI, un import EPG sans délai qui bloquait tout import suivant,
un remplacement de liste non atomique, un ré-import complet possible pendant la
lecture et deux défauts de télécommande. Ce qui reste **NON VÉRIFIÉ** l'est par
nature (son réel, mémoire après 100 zaps, écran noir au retour) et doit passer
par la box de test avant toute publication.

## 2. Inventaire réel (preuves : fichier + zone)

| Élément | Valeur | Preuve |
| --- | --- | --- |
| Plateforme | Android TV / Fire TV / Google TV (APK sideload), minSdk 21 | `.github/workflows/build-zuno-tv.yml`, `ci/tv/patch_gradle.py` (kBoxMinSdk) |
| UI | Flutter 3.x stable (CI : canal stable ; local : 3.47.6), Dart | `pubspec.yaml`, workflow |
| Moteur vidéo | Media3 ExoPlayer **1.5.1** (+ `media3-exoplayer-hls` 1.5.1) sur `SurfaceView` en Hybrid Composition | `packages/native_video_player/android/build.gradle`, `NativeVideoView.kt` |
| Décodeur audio FFmpeg | `org.jellyfin.media3:media3-ffmpeg-decoder:1.5.0+1` (audio seulement) | `build.gradle`, `NativeVideoView.ffmpegVideoReady` |
| Réseau lecteur | `DefaultHttpDataSource`, connexion 15 s, lecture 15 s, UA VLC, redirections inter-protocoles | `NativeVideoView.buildConfiguredPlayer` |
| Retry Media3 | `DefaultLoadErrorHandlingPolicy(6)` | idem |
| Reconnexion app | 8 essais, 1-2-4-8-8-8-8-8 s, un seul `prepare()` à la fois | `logic/ReconnectPlan.kt`, `ReconnectGate` |
| Chien de garde Dart | 15 s sans progression → ré-ouverture, budget ≥ 5 (+ adresses de secours), puis écran « Réessayer » | `tv_player_screen.dart` `_recover` |
| Stockage | SQLite (`sqflite`), chaînes `channels`, EPG `epg_programs` | `playlist_database.dart`, `epg_repository.dart` |
| EPG | XMLTV en flux (`XmlEventDecoder`), gzip, 48 h gardées, parse sur l'isolate UI | `xmltv_parser.dart`, `epg_repository.dart` |
| Playlists | M3U (parse en isolate, `compute`) et Xtream (`player_api.php`) | `m3u_parser.dart`, `xtream_client.dart` |
| Login | Aucun compte Zuno : activation par MAC (ANDROID_ID) auprès du Worker | `subscription_backend.dart` |
| Cast | Code présent (`features/cast/`) mais chemin **téléphone** ; non branché sur les écrans TV | grep `TvPlayerScreen` / `cast_manager` |
| Enregistrement | Relais local 127.0.0.1 (une connexion, tee vers fichier) | `local_stream_relay.dart` |
| Catch-up | Oui si la chaîne le déclare (`CatchupUrlBuilder`) | `tv_player_screen._rewindMissed` |
| Sous-titres | Pistes du flux seulement, langue de l'app | `tv_player_screen._offerSubtitles` |
| DRM | Aucun | grep `DrmSessionManager` : 0 |
| Crash reporting | Boîte noire locale + Crashlytics fail-open (secret CI absent par défaut) | `core/blackbox`, `core/crash` |
| Lifecycle | `MainActivity` → `AppForeground` (onUserLeaveHint/onPause/onStop/onResume) → arrêt natif | `android/app/src/main/kotlin/.../MainActivity.kt`, `logic/BackgroundGate.kt` |
| Threads | Fil principal + fil de lecture Media3 ; aucun `GlobalScope`, `runBlocking`, `Thread.sleep` | grep (0 résultat) |
| Samsung Tizen / LG webOS | **N/A** (aucun code) | — |

Les dix composants dont la panne casse l'expérience : `NativeVideoView.kt`
(lecteur), `AudioHandoff`/`PlayerCensus` (un seul AudioTrack), `AudioFocusPolicy`,
`BackgroundGate`/`AppForeground`, `ReconnectGate`, `NativeVideoController`
(epoch/ack), `TvPlayerScreen` (zap, chien de garde), `TvLivePreview` (aperçu),
`PlaylistRepository` (listes), `EpgRepository`.

## 3. Problèmes trouvés

| Priorité | Problème | Cause racine | Fichier | Correctif | Vérification |
| --- | --- | --- | --- | --- | --- |
| P1 (sécurité) | Les identifiants Xtream (`username=…&password=…`, `/live/u/p/`) arrivaient en clair dans le journal local lisible depuis Réglages → Boîte noire | Seule la copie envoyée au panel était expurgée ; les exceptions `http` recopient l'URL complète (`xtream_client.dart:230`, `m3u_fetcher.dart`) | `black_box.dart`, `black_box_line.dart` | Expurgation à l'écriture, mêmes règles que l'envoi ; fil d'Ariane et Crashlytics expurgés | **PROUVÉ** : `black_box_line_test.dart` (URL Xtream, chemin `/live/u/p/`, lignes [SON] intactes) |
| P1 (perf, ANR) | `fsync` disque à CHAQUE ligne sur le fil UI ; 15 à 25 lignes [SON] par zap | `_file.flushSync()` après chaque `writeStringSync` | `black_box.dart` | `write` immédiat (survit à une mort du processus), `fsync` regroupé ≤ 1 s pour l'info, immédiat pour avertissement/erreur et à l'arrière-plan | **FORTEMENT ÉTAYÉ** : politique testée (`blackBoxFlushNow`), coût réel du fsync sur eMMC NOT MEASURED |
| P1 | Import EPG sans aucun délai : un serveur muet laissait `isSyncing` à vrai jusqu'au redémarrage, tous les imports suivants renvoyaient 0 en silence | `client.send()` et le flux sans `timeout` | `epg_repository.dart` | Délai en-têtes 30 s, silence 60 s → exception, verrou rendu | **PROUVÉ** : `epg_import_guard_test.dart` (serveur muet, flux qui se tait, import suivant OK) |
| P1 | Actualisation d'une liste : `DELETE` puis insertions par lots, sans transaction ; une mort du processus laissait une liste vide/tronquée 6 h | Deux opérations séparées | `playlist_repository.dart` | `_replaceChannelsOf` : une transaction, lots via `txn.batch()` | **PROUVÉ (mécanisme)** : `replace_channels_transaction_test.dart` (interruption → ancienne liste intacte) ; chemin réseau réel NON VÉRIFIÉ |
| P1 | Ré-import complet de la source possible PENDANT la lecture (timer 12 s de l'écran Direct, toutes les ~5 min) | `_kickSourceSync()` ignorait le lecteur ouvert ; `TvActivity.isBusy` est déjà vrai dans l'écran Direct lui-même | `tv_live_screen.dart`, `tv_sync_policy.dart` | Pas de re-vérification lente si un lecteur couvre l'écran (ou si l'écran n'est pas la route courante) | **PROUVÉ** (décision) : `tv_sync_policy_test.dart` |
| P2 (EPG) | Guide vide au 3e jour : téléchargé seulement à l'ajout de la source, 48 h gardées, jamais rechargé | Aucun appel de `downloadAndImport` dans `refreshPlaylist`/`refreshAll` | `playlist_repository.dart` | Re-téléchargement du guide d'une liste M3U quand elle est actualisée (6 h, bouton) | **FORTEMENT ÉTAYÉ** (même chemin qu'à l'ajout) |
| P2 (EPG) | Ré-import = programmes doublés (table sans clé unique) | `batch.insert` seul | `epg_repository.dart` | `batch.delete` par chaîne à sa première apparition, avant ses insertions | **PROUVÉ** : 12 → 12 → fichier partiel garde 12 |
| P2 (EPG) | Guide ISO-8859-1 jeté en entier | `utf8.decoder` strict | `xmltv_parser.dart` | `Utf8Decoder(allowMalformed: true)` | **PROUVÉ** : `xmltv_tolerant_decode_test.dart` |
| P2 (télécommande) | Retour maintenu dans le lecteur dépilait aussi la liste Direct | `maybePop()` sur chaque `KeyRepeatEvent` | `tv_player_screen.dart` | Un seul pop, à l'appui | **FORTEMENT ÉTAYÉ** (le lecteur Cinéma faisait déjà `!repeat`) |
| P2 (télécommande) | OK relâché sur un bouton qui vient de prendre le focus l'activait (double action) | `onSelect` au relâchement sans vérifier l'appui | `tv_focusable.dart` | Relâchement ignoré si l'appui n'a pas commencé sur ce bouton | **PROUVÉ** : `tv_focusable_select_test.dart` |
| P2 (mémoire) | Logos et affiches de l'accueil décodés en pleine taille (logos IPTV 500–2000 px) | `CachedNetworkImage` sans `memCacheWidth` | `tv_home_rails.dart` | Décodage à ×3 de la taille affichée | **FORTEMENT ÉTAYÉ** ; gain RAM NOT MEASURED |
| P3 | Abonnement connectivité créé après un `await` sur un écran déjà démonté | `_connSub` assigné sans `mounted` | `tv_hub_screen.dart` | `if (!mounted) return` | statique |
| P3 | Bandeau sport : `Timer.periodic` 30 ms qui fait défiler sous le lecteur | pas de test de route | `tv_sports_screen.dart` | ne fait rien quand la route n'est pas courante | statique |
| P3 | `isPlaying` périmé après `setUrl` (Lecture/Pause inversé pendant le chargement) | état non remis | `native_video_player.dart` | `isPlaying = false` au `setUrl` ; la barre Cinéma se ré-arme au vrai départ | **PROUVÉ** : `playback_epoch_test.dart` |
| P3 | `platformAacGaveUp` lu depuis le fil de lecture sans visibilité | champ non volatile | `NativeVideoView.kt` | `@Volatile` | statique |
| P3 (sécurité) | `android:allowBackup` absent (vrai par défaut) alors que les préférences portent la clé AES des codes | manifeste modèle | `ci/tv/patch_manifest.py` | `allowBackup="false"` + `tools:replace` | script idempotent vérifié (deux passes identiques) ; fusion manifeste vérifiée par le build CI |
| P1 (terrain, 2e passe) | Écran noir après ~1 min, le son continue (box de test) | copie de dernière image noire (`PixelCopy` d'une surface vidéo) et jamais retirée si le signal « première image » n'arrive pas après une reprise | `logic/HeldFrame.kt`, `NativeVideoView.kt` | copie noire rejetée ; copie retirée dès qu'une trame est rendue après son affichage ; repli `zuno.player.hold_frame_legacy` | **PROUVÉ** (règles, `HeldFrameTest`) ; cause sur la box **NON VÉRIFIÉE** (lignes de boîte noire à relire) |
| P1 (terrain, 2e passe) | Son très mauvais, fiche France 24 AAC-LC **44,1 kHz** sortie 44,1 kHz | hypothèse : conversion 44,1 → 48 kHz de la puce | `ZunoAudioChain.kt`, `AudioFixes.kt`, écran Diagnostic du son | essai « Sortie : 48 kHz » (défaut coupé) : rééchantillonnage Sonic avant l'AudioTrack | API vérifiée (`javap` media3-common 1.5.1), `AudioFixesTest` ; effet sur la box **NON VÉRIFIÉ** |

### Interrupteurs de repli (tous faux par défaut)

`lib/core/app/repair_flags.dart`, préférences SharedPreferences :

| Clé | Vrai = |
| --- | --- |
| `zuno.blackbox.raw` | journal écrit tel quel (ancien) |
| `zuno.blackbox.fsync_all` | un fsync par ligne (ancien) |
| `zuno.sync.during_playback` | re-vérification lente autorisée sous le lecteur (ancien) |
| `zuno.epg.refresh_off` | pas de guide re-téléchargé à l'actualisation d'une liste (ancien) |
| `zuno.player.hold_frame_legacy` | copie de dernière image gardée même noire, retirée seulement au signal (ancien) |
| `zuno.audio.out48k` (Diagnostic du son → « Sortie ») | **essai** à allumer à la main : rééchantillonnage 48 kHz avant l'AudioTrack (faux = flux, comme avant) |

Les réglages audio existants (`zuno.audio.*`, `zuno.player.bg_*`) n'ont pas changé.

## 4. Ce qui a été examiné et jugé sain (lecture complète, pas d'opinion)

- **Lecteur, cycle de vie** : un seul `ExoPlayer` par vue, réutilisé au zap
  (`stop()` + `clearMediaItems()` + `setMediaItem()` + `prepare()`), `release()`
  idempotent, `handler.removeCallbacksAndMessages(null)` à la libération, surface
  jamais détachée entre deux chaînes, bitmap de la dernière image recyclé.
- **Dernier choix gagne (A→B→C)** : jeton de session natif (`PlaybackSession`),
  horodatage `sessionOpenedAt` qui jette les événements Analytics plus anciens,
  epoch/ack côté Dart (`playback_epoch_test.dart`), 180 ms de regroupement des
  appuis Haut/Bas (un seul `setUrl` par touche maintenue), attente d'AudioTrack
  annulée et re-posée par chaque nouveau `openCurrent`.
- **Retries bornés** : Media3 6 essais ; natif 8 essais ; Dart ≥ 5 + adresses de
  secours ; relais d'enregistrement 12 reconnexions ; aucune boucle infinie.
  Temps avant l'écran « Réessayer » sur une chaîne morte : de l'ordre de 1,5 à
  3,5 min selon le nombre d'adresses de secours (calcul statique, NOT MEASURED).
  La carte de chargement affiche le numéro et le nom, Haut/Bas zappe pendant ce temps.
- **Arrière-plan** : `onUserLeaveHint`+`onPause` ou `onStop` → arrêt natif (décodeur,
  AudioTrack, focus rendus) ; aucune réouverture tant que l'app est dehors
  (`allowsReopen`) ; une seule reprise au retour (le `resumed` Flutter en retard est
  absorbé par `suspended == false`). Cinéma : reprise manuelle à la position.
- **Focus audio** : géré par Zuno, baisse à 20 % ignorée, pause sur perte réelle,
  reprise au GAIN seulement si c'est nous qui avions pausé (`AudioFocusPolicyTest`).
- **Un seul AudioTrack** : `prepare()` retenu tant qu'une piste est vivante, délai
  1,5 s, callbacks en retard « dus » (`AudioHandoffTest`, `PlayerCensusTest`).
- **Sécurité** : aucun secret ni URL de flux en dur ; HTTPS vers le Worker, aucun
  contournement de certificat ; `usesCleartextTraffic` nécessaire aux flux IPTV ;
  aucune WebView ; mots de passe Xtream chiffrés au repos (AES-GCM) ; les URL de
  flux en base restent en clair (contiennent les codes) — limite connue, voir §7.
- **D-pad** : tous les dialogues TV se ferment par Retour ; Retour un à un via
  `TvBackGuard` (un appui long n'envoie pas de retour système : Android l'annule).

## 5. Ce que la box de test doit confirmer (NON VÉRIFIÉ)

1. Son identique après 50 zaps et après Home → retour (boîte noire : `Zap : n°…`,
   `AudioTrack rendu. Pistes encore vivantes : 0` puis `1`, `Focus audio : obtenu`,
   `repli box : aucun`).
2. Pas d'écran noir au retour de Home quand aucune image n'avait été copiée.
3. RAM au lancement, pendant la lecture, après 20/50/100 zaps, après Home/retour.
4. Temps accueil → première image, zap → première image (P50/P95).
5. Chaîne morte (404) → écran « Réessayer » en moins de 4 min ; Haut/Bas pendant
   l'attente ouvre bien une autre chaîne.
6. Que l'expurgation du journal ne retire rien d'utile aux fiches [SON]
   (le test couvre une fiche type ; la vraie fiche d'une chaîne reste à relire).
7. Que la fusion du manifeste accepte `allowBackup="false"` (vérifié par le build CI).

## 6. Risques restants (non corrigés ici, à décider)

- **Parse XMLTV sur l'isolate UI** (`xmltv_parser.dart`) : un guide de 100 Mo+
  fait saccader l'accueil pendant l'import (à l'ajout ET, désormais, à chaque
  actualisation de liste, quand la box est inactive). Correctif possible :
  isolate dédié. Non fait ici (changement structurel, pas de mesure box).
- **Recherche TV** : `searchCatalog` recalcule une clé normalisée pour chacune des
  50 000 chaînes à chaque frappe, sur l'isolate UI (`voice_catalog.dart`). Débounce
  250 ms et jeton de génération présents. À précalculer par chaîne.
- **Relais d'enregistrement** : pas de contre-pression ; quand ExoPlayer a 45 s
  d'avance et cesse de lire, le relais garde jusqu'à ~40 s de flux en RAM
  (≈ 25 Mo à 5 Mb/s, ≈ 75 Mo en 4K). Seulement pendant un enregistrement.
- **Enregistrement d'une adresse `.m3u8`** choisie par le secours du direct : le
  relais ne sait servir que du MPEG-TS.
- **EPG Xtream** : non apparié (ids `xtream-<stream_id>` ≠ `epg_channel_id`),
  donc jamais importé — limite déjà documentée dans le code.
- **Media3 1.5.1 vs 1.11.1 (stable d'octobre 2026)** : pas de migration. Le
  binaire FFmpeg Jellyfin est aligné sur 1.5.x, et tout le chemin audio (chaîne de
  processeurs, attente d'AudioTrack, focus) a été réglé contre le comportement
  exact de `DefaultAudioSink` 1.5.1. Migrer sans box pour mesurer = risque > gain.
- **Pages mémoire 16 Ko** : **vérifié** sur l'APK de test courant (versionCode
  1791065876, `readelf -lW` sur `lib/arm64-v8a/*.so`) : alignement des segments
  LOAD = 0x10000 (`libapp.so`, `libflutter.so`) ou 0x4000 (`libffmpegJNI.so`
  Jellyfin, `libmpv.so`, `libsqlite3.so`, `libdartjni.so`…) — tous ≥ 16 Ko.
  `zipalign -c -P 16 -v 4` : exit 0 (bibliothèques compressées, extraites à
  l'installation). Les mêmes binaires sont embarqués dans ce build.
  Remarque : `libmpv.so` + `libmediakitandroidhelper.so` (media_kit) sont dans
  l'APK TV sans être utilisés sur la box (~25 Mo) : `pubspec.yaml` est commun au
  téléphone ; les retirer demanderait un flavor séparé.
- **Serveur de télécommande téléphone** reste lié à l'IP Wi-Fi après expiration du
  jeton (refuse les requêtes, mais garde le port). Fonction coupée par défaut.
- **Chemins codés par `kDebugMode`** : plusieurs échecs du relais et du serveur
  cast ne sont journalisés qu'en debug.
- **Un heartbeat réseau par chaîne ouverte** (`tv_player_screen._open` →
  `SubscriptionState.syncWithBackend`) : c'est la présence « regarde » du panel.
  Un seul appel en vol à la fois (`_netBusy`), et le regroupement des appuis
  (180 ms) fait qu'une touche maintenue n'en déclenche qu'un. 100 zaps posés =
  100 requêtes courtes vers le Worker ; pas un risque de stabilité, laissé tel quel.

## 7. Conformité plateformes

| Plateforme | État | Justification |
| --- | --- | --- |
| Android TV | PASS (statique) | Leanback launcher, bannière, paysage, D-pad complet, pas de touch requis, minSdk 21, ABIs ARM 32/64 + x86_64 vérifiées par le workflow |
| Google TV | PARTIAL | Idem Android TV ; 16 Ko et Play Core non vérifiés ici (sideload) |
| Fire TV | PARTIAL | Arrière-plan/focus/MediaSession traités au niveau Android ; aucun test sur Fire OS ici |
| Samsung Tizen | N/A | aucun code |
| LG webOS | N/A | aucun code |

## 8. Preuves exécutées

Commandes réellement lancées sur cette machine (4 octobre 2026) :

| Commande | Avant | Après |
| --- | --- | --- |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | exit 0, 256 remarques, 0 erreur | exit 0, 256 remarques, 0 erreur |
| `flutter test` | 360 réussis, 2 ignorés, 0 échec | **375** réussis, 2 ignorés, 0 échec |
| `gradle test` (`packages/native_video_player/logic-test`) | 141 tests, 0 échec | 141 tests, 0 échec |
| `python3 ci/tv/patch_manifest.py` ×2 sur le manifeste modèle | — | sortie identique (idempotent), `allowBackup="false"` présent |

Tests ajoutés : `test/core/blackbox/black_box_line_test.dart`,
`test/features/epg/epg_import_guard_test.dart`,
`test/features/epg/xmltv_tolerant_decode_test.dart`,
`test/features/playlists/replace_channels_transaction_test.dart`,
`test/features/tv/tv_sync_policy_test.dart`,
`test/features/tv/tv_focusable_select_test.dart`, et un cas dans
`test/features/player/playback_epoch_test.dart`.

## 9. Build de test (release `zuno-tv-test`)

Workflow `.github/workflows/build-zuno-tv.yml`, « Run workflow » sur la branche
`ccr-1d45eb8b-x46ieg`, inputs `publish=false`, `play_aab=false`, `test_box=true`,
`backend_url` vide, `variante=box`. Run **#145** (`37201117140`), commit
`4d87ee9e61edfd3ee37e4322353a45e167fda537`, toutes les étapes vertes (gate
qualité analyze + tests comprise).

Vérifié sur le fichier retéléchargé depuis la release (pas sur les intentions) :

| Contrôle | Résultat |
| --- | --- |
| Lien | https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv-test/zuno-tv.apk |
| SHA-256 (`sha256sum`) | `b50a8d98b1b9a9356abd8de49a6c9d644f7f0d85068be37a65464f699aa4007b` (54 551 814 octets, identique au digest de l'API et aux notes de la release) |
| `aapt2 dump badging` | `package: name='com.sevenmotion.tv.seven_tv' versionCode='1791115897' versionName='106'`, `application-label:'Zuno'`, `leanback-launchable-activity`, ABIs `arm64-v8a armeabi-v7a x86_64`, compileSdk 36 |
| versionCode > box de test précédente | 1791115897 > 1791065876 ✓ (la box affichera v106+1791115897 dans Réglages → Boîte noire) |
| `apksigner verify --print-certs` | `Signer #1 certificate SHA-256 digest: 5145b8e019f6d5fb96a207f2e73673fd954f799966fd598889211556cbdf9e61` (clé des box clients) |
| Manifeste fusionné (`aapt2 dump xmltree`) | `allowBackup=false`, `largeHeap=true` |
| `version.json` de `zuno-tv-test` | inchangé (le chemin test ne l'écrit pas, comme prévu par le workflow) |

Non publié aux clients : `publish=false`, et `test_box=true` interdit de toute
façon l'écriture sur `zuno-tv` (`PUBLIER` est faux).

Builds suivants, mêmes inputs, mêmes contrôles (fichier retéléchargé) :

| Run | Commit | versionCode | SHA-256 | Certificat |
| --- | --- | --- | --- | --- |
| #146 | `1b5a855` (écran noir, essai 48 kHz) | remplacé par #147 | — | — |
| #147 | `1050c92` (+ panel instantané, deux QR) | 1791118025 | `f5c990b2ddcb87f505814bd891c01ae3bf7e12439efc9e57a29376c1c3463f08` | `5145b8e0…` ✓ |
| #148 (`37203790667`) | `e698de2` (+ guide Xtream, EPG isolate, historique 20 s, reprise) | 1791118634 | `23a75f66b7372feb4af1b3fd01aad7135802a780d23adc99266992913eeaa54f` (54 584 479 octets) | `5145b8e0…` ✓ |
| #149 (`37205096210`) | `8956ae8` (+ cartes du panel : annonce, favori du jour, bannières) | 1791119971 | `3ba4ed02585e961ab0c5d0f85693d29b78daec77b646d3fe7320766ce3365a20` (54 627 855 octets) | `5145b8e0…` ✓ |
| #150 (`37207214664`) APK | `fb3df3e` (+ manifeste Wi-Fi non requis, paysage tablette Android 16) | 1791122105 | `843ae11e87f73dd6caf1502710b0adab63f29958e5ab357f1e3cae7934da5a47` (54 627 949 octets) | `5145b8e0…` ✓ |
| #150 AAB Google Play (`play_aab=true`) | `fb3df3e` | même numéro de build (workflow) | `1d0388b32ec49bdcb3b74c9dd2c5f6de7ab7a0d562778fd738ed0432cf9b4c28` (89 140 208 octets) | `keytool` : `51:45:B8:E0…9E:61` ✓ |

Contrôles AAB #150 sur le fichier retéléchargé : ABIs `arm64-v8a`,
`armeabi-v7a`, `x86_64` ; toutes les `.so` 64 bits alignées 16 Ko (`readelf`,
0 écart) ; `REQUEST_INSTALL_PACKAGES` absente du manifeste du bundle (0
occurrence). APK #150 : `android.hardware.wifi` non requis,
`PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY=true` présent (`aapt2 dump
xmltree`).

Windows #12 (`build-zuno-windows.yml`, run `37207207680`, push de `fb3df3e`) :
toutes les étapes vertes, version 106.0.12, `Zuno-Setup.exe` 29 395 652 octets
SHA-256 `acde7ab216935a502def2134c930f0f18672ace55e92371fb9bcab00651781e7`
(calculé par le build, artefact non retéléchargeable sans compte GitHub),
`zuno-windows.zip` 38 587 057 octets ; étape « Publier » **sautée** (branche
`ccr-`), release `zuno-windows` inchangée (fichiers du 3 octobre).

Release clients `zuno-tv` relue après #147, #148, #149 et #150 : digests
(`6321fa53…`, `9085457271…`, `b65392bf…`) et `updated_at` (2026-09-30) inchangés.

## 10. Preuve que la release clients `zuno-tv` n'a pas bougé

Avant toute action (API GitHub, 4 octobre 2026) :

- `zuno-tv.apk` 54 232 131 octets, SHA-256 `6321fa53aa240d805bb5cabcd9c3e1b67d9f6b690a7d58a8c1a9cd52129a0a50`
- `version.json` 275 octets, SHA-256 `9085457271e17df67c65d435bebecba4bb211a96d1ad9b21c3793fde823329a8`, versionCode 1790805013, versionName 106
- `zuno-tv.aab` SHA-256 `b65392bf1cf7a4265054519ffc8da41058a68fb66e1487078d419b4ad71dab9c`

Après le build de test (API GitHub, même jour) : release `updated_at`
`2026-09-30T21:59:55Z` inchangé, les trois actifs portent les **mêmes** digests
et les mêmes dates ; `version.json` retéléchargé a le même SHA-256
`9085457271e17df67c65d435bebecba4bb211a96d1ad9b21c3793fde823329a8` qu'avant
(versionCode 1790805013, versionName 106).

## 11. Score (honnête, hors appareil)

| Axe | Note | Pourquoi |
| --- | --- | --- |
| Fiabilité lecture /25 | 18 | Machine d'états, jetons, retries bornés, un seul AudioTrack : étayés et testés hors box ; comportement réel du décodeur/HDMI non mesuré |
| Zapping /15 | 11 | Dernier choix gagne (tests), 180 ms de regroupement ; latence réelle NOT MEASURED |
| UX TV & télécommande /15 | 11 | Deux défauts corrigés ; tous les dialogues fermables ; pas de test sur écran réel |
| Performance /10 | 6 | fsync par ligne retiré ; parse EPG et recherche restent sur l'isolate UI |
| Mémoire /10 | 6 | Fuites structurelles non trouvées ; décodage des logos borné ; aucune mesure |
| Reprise réseau /10 | 7 | Bornée, observable, annulable au zap ; chaîne morte lente à conclure (1,5–3,5 min) |
| Architecture /5 | 4 | Logique pure testée (Kotlin + Dart), peu d'état global, interrupteurs de repli |
| Sécurité /5 | 4 | Journal et Crashlytics expurgés, allowBackup faux ; URL de flux en clair en base |
| Couverture de tests /5 | 4 | 375 Dart + 141 Kotlin ; aucun test d'intégration sur appareil |
| **Total** | **71/100** | |

## 11 bis. Demandes du 4 octobre (après la première box de test)

| Demande | Ce qui existait | Ce qui change | Limite honnête |
| --- | --- | --- | --- |
| Panel → app instantané (essai, source) | Canal « signal » en attente longue (`BoxSignalClient.wait`) : un ordre `activate` / `source` arrive en quelques secondes ; lecture du statut toutes les 3–4 s ; mais l'import de la source était refusé tant que l'écran Direct ou le lecteur était ouvert (`SourceFetchDecision.playbackBusy`), et l'écran Direct VIDE compte comme occupé | `activation_pace.dart` : une box **sans chaîne** importe tout de suite, même sur l'écran Direct vide (rien ne peut jouer). Test ajouté dans `activation_pace_test.dart` | Une box qui a déjà des chaînes et qui **joue** reçoit une source remplacée au retour à l'accueil (importer 50 000 chaînes pendant la lecture fige l'image). L'activation / l'essai, eux, sont immédiats partout. Le Worker n'a pas été touché |
| Deux grands QR à l'installation | Activation : QR « Mon espace » seul ; Direct vide : QR WhatsApp seul | Activation : QR **WhatsApp** (code MAC pré-rempli) + QR **« Mon espace »** (ajout de sa propre liste depuis le téléphone), 210 px chacun, mention « Cette application ne vend aucune chaîne » au-dessus du second ; Direct vide : les deux QR aussi | Rendu réel (lisibilité, scan) à vérifier sur la box |
| Publication aux clients | — | Rien n'est publié : `publish=false` sur tous les builds. La publication ne se fait qu'après validation sur la box, sur demande explicite | — |

## 11 ter. Passe « rendre accro » (4 octobre, après recherche sur les zones non auditées)

Constat central : la plupart des fonctions de fidélisation (« En retard », « Tes
émissions », rappels, rattrapage, « ce soir », programme sous le nom) lisent le
guide, et le guide était **vide pour toutes les sources Xtream** (`_syncEpgFor`
sautait le XMLTV : identifiants jamais appariés) et saccadait la box pour les M3U
(décodage sur le fil UI).

| Changement | Fichiers | Preuve |
| --- | --- | --- |
| Guide Xtream apparié : `epg_channel_id` de chaque chaîne (gardé par `XtreamClient.epgChannelIds`) → XMLTV `xmltv.php` ; une chaîne XMLTV nourrit toutes les chaînes qui la déclarent (« TF1 HD » + « TF1 FHD ») | `xtream_client.dart`, `epg_targets.dart`, `playlist_repository.dart` | `epg_targets_test.dart`, `epg_isolate_import_test.dart` (vrai serveur HTTP local + base SQLite : 3 programmes × 2 chaînes + 3, identifiant inconnu ignoré) |
| Import du guide dans un **isolate** (téléchargement + décodage), rangées insérées par lots de 500 sur le fil principal ; repli `zuno.epg.inline_parse` | `epg_fetch.dart`, `epg_repository.dart` | même test (chemin isolate), `epg_import_guard_test.dart` (chemin en ligne : délais, dédoublonnage) |
| Historique « regardé » : après 20 s avec une image, ou en quittant le lecteur sur la chaîne ; une chaîne survolée ne pollue plus « Reprendre », la dernière chaîne au démarrage ni « À cette heure » ; repli `zuno.history.on_open` | `history_policy.dart`, `tv_player_screen.dart` | `history_policy_test.dart` |
| Reprise au démarrage : Haut/Bas parcourent toute la liste (la dernière chaîne à sa place), plus seulement les 8 « Reprendre » | `resume_zap.dart`, `tv_hub_screen.dart` | `resume_zap_test.dart` |

Non fait, documenté pour la suite (par valeur décroissante) : rappels visibles
dans l'app (la rangée « Vos rappels » ne se remplit jamais sur la box) ; grille
du guide pilotable à la télécommande ; rattrapage limité à 1 h de passé
(`purgeStale`) alors que les chaînes déclarent plusieurs jours ; recherche avec
classement (exact > préfixe > contenu, favoris en tête), clés précalculées hors
fil UI, numéro de chaîne, titres du guide ; appariement par nom pour les M3U sans
tvg-id ; `MediaSession` (lecture/pause HDMI-CEC, Assistant) ; Watch Next /
chaîne « Zuno » sur l'accueil Google TV.

## 11 quater. Cartes du panel sur l'accueil box (4 octobre, demande « notifications naturelles + publicités comme les box Android »)

Constat (mesuré par lecture du code, pas supposé) : le panel sait déjà publier
des **annonces** (`/api/announcement`, ordre signal `message`), un **favori du
jour** (`/api/featured`, ordre `featured`) et une **pub vidéo de démarrage**
(`/api/ad`) ; l'app téléphone les affiche, **l'app box les ignorait toutes**
(aucune référence dans `lib/features/tv/`). Le module « Bannières » du Centre de
contrôle est marqué *Bientôt (Phase 2)* : il n'existe pas côté Worker ni panel.

Fait côté box uniquement (`lib/features/panel_board/`, Worker et panel non
touchés, conformément aux interdits) :

| Carte | Source | Preuve |
| --- | --- | --- |
| Annonce du revendeur : carte en tête de l'accueil, icône selon `kind`, « Vu » mémorisé par id, QR du lien pour le téléphone ; arrive **instantanément** par le canal signal (`AnnouncementRepository.latest`, nouveau `ValueNotifier` alimenté par `fetchLatest`) ; relecture au plus toutes les 10 min sinon | `tv_panel_notice.dart`, `announcement_repository.dart` | `panel_board_test.dart` (`noticeAllowed`, `pickHeaderCard`) |
| Favori du jour : la chaîne nommée par le panel, **si** elle est dans la liste (repli accents/casse, direct d'abord, préfixe « TF1 » → « TF1 HD ») ; recherche hors fil UI au-delà de 2 000 chaînes (`Isolate.run`) | `panel_board.dart`, `tv_featured_card.dart` | `panel_board_test.dart` (6 cas dont liste de 2 050 chaînes) |
| Bannières images : lecteur de `GET /api/banners` (contrat dans `docs/PANEL-BOX-CARTES-ACCUEIL.md`), 404 = rien ; une image à la fois, libellé « Publicité » obligatoire, 6 apparitions/jour/bannière, « Fermer » = 7 jours, fenêtre `from`/`until`, mode enfants = `kids: true` seulement, rotation au tic de 20 s ; ordre signal `banner` relit la liste | `promo_banner_repository.dart`, `tv_promo_banner.dart`, `box_signal.dart`, `remote_activation_watch.dart` | `promo_banner_repository_test.dart` (404, 200, panne, cache, compteurs persistants), `box_signal_test.dart` |
| Une seule carte à la fois : émission suivie > annonce > bannière/favori en alternance | `pickHeaderCard` | `panel_board_test.dart` |
| Trois interrupteurs Réglages → En plus (« Annonces du service », « Favori du jour », « Bannières »), défaut allumé comme les autres `BoxFlag` ; coupé = la carte disparaît, rien d'autre | `panel_board_flags.dart`, `tv_extras_screen.dart` | — (réglage) |

Choix délibérés, appuyés par la recherche (brief du 4 octobre, sources datées) :
pas de pub vidéo au démarrage sur la box (le recul d'Amazon en 2024 sur
l'autoplay sonore du Fire TV, et media_kit n'est pas chargé sur la TV) ; pas de
notification système (Android TV n'affiche pas de bandeau ; la carte d'accueil
est la seule « notification » légitime, jamais sur l'image) ; pas de « streaks »
(aucune preuve d'efficacité sur TV, contraire au lean-back) ; libellé publicitaire
toujours visible (LCEN art. 20 ; L121-2 Code conso) ; Impeller reste coupé
(déjà le cas, confirmé par les retours RK3399/Mali).

NON PROUVÉ (seulement sur la box) : rendu des trois cartes à 1080p avec la vraie
police, focus télécommande Haut depuis les rangées vers « Vu » / « Fermer »,
image de bannière réelle (aucun serveur ne la sert encore).

Hors périmètre, à faire par qui a le droit de toucher Worker et panel : table +
`GET /api/banners`, écriture owner avec `signalFleet(env, 'banner')`, page
« Bannières » (spécification complète dans `docs/PANEL-BOX-CARTES-ACCUEIL.md`).
Sans cela, la box affichera déjà annonces et favori du jour, pas de bannière.

## 12. Bloqueurs de publication

Aucun P0 connu dans le code. La publication aux clients (`publish=true`) reste
interdite tant que les points du §5 (son après 50 zaps et après Home, écran noir
au retour, RAM après 100 zaps) n'ont pas été relus sur la box de test avec cette
version.
