# PROMPT DE PASSATION — Zuno (app box Android TV) : stabilité, fluidité, boîte noire, enregistrement

> À coller tel quel dans une autre IA de développement disposant du dépôt
> `manzilionellm-dotcom/tvking` (branche `claude/app-admin-panel-connection-9fphfr`).

---

## 0. Ta mission en une phrase

Rendre l'application **Zuno** (lecteur IPTV Android TV en Flutter, dossier `android-app/`, entrée `lib/main_tv.dart`) **stable** (elle ne doit plus jamais se fermer toute seule), **fluide** (défilement de listes de 30 000 à 50 000 chaînes sans saccade sur une box à 1-2 Go de RAM), **rapide à l'import** (une liste Xtream ou M3U de 30 000 chaînes doit se charger sans figer l'écran), capable d'accueillir **beaucoup de listes en même temps** (5 à 10 codes Xtream/M3U fusionnés, façon TiviMate), avec une **boîte noire** consultable dans les Réglages qui dit EXACTEMENT pourquoi l'app s'est fermée, et un **enregistrement du direct** simple et fiable (« j'enregistre le match en cours en un bouton »).

Tu travailles comme un ingénieur senior Android/Flutter : tu mesures, tu prouves, tu ne devines pas. Tu n'inventes rien : chaque changement de comportement doit être justifié par une trace (log, mesure, doc officielle).

---

## 1. INTERDITS ABSOLUS (le propriétaire y tient plus qu'à tout)

1. **Ne touche à RIEN de visuel.** Ni couleurs, ni tailles, ni polices, ni disposition, ni textes, ni logo, ni animations de focus, ni l'ordre des écrans. Le thème est dans `lib/features/tv/core/tv_tokens.dart` (noir & or Zuno) : tu ne le modifies pas. Les écrans TV sont dans `lib/features/tv/presentation/` : leur apparence doit rester pixel pour pixel identique. Si une optimisation exige un changement visible, tu la refuses et tu proposes autre chose.
2. **Ne touche pas au binaire 4K Player** ni à la release GitHub `7motion-tv` (c'est une autre app, tierce, fermée).
3. **Ne déploie pas le Worker Cloudflare** (`android-app/cloudflare/`) : le code en production est PLUS RÉCENT que celui du dépôt (l'API en ligne renvoie des champs absents du dépôt). Un `wrangler deploy` depuis le dépôt casserait le panel du propriétaire.
4. **Ne change ni l'`applicationId` (`com.sevenmotion.tv.seven_tv`) ni la signature** : les box installées doivent pouvoir mettre à jour par-dessus.
5. **Respecte `android-app/AGENTS.md`** : commentaires en français abondants, aucune URL de flux en dur, pas de `print()`, toute dépendance ajoutée à `pubspec.yaml` documentée (pourquoi elle, ce qu'elle fait).
6. **Ne supprime aucune fonctionnalité** (favoris, récents, tendances, Pour vous, mode enfants, enregistrement, catch-up, sources multiples, activation par le panel).

---

## 2. Comment builder et publier (pas de Flutter en local, tout passe par la CI)

- Workflow racine : `.github/workflows/build-zuno-tv.yml`. Il patche le manifeste et Gradle (`android-app/ci/tv/patch_manifest.py`, `patch_gradle.py`), lance `flutter analyze` + `flutter test` (barrière qualité), compile `lib/main_tv.dart` en APK universel ARM, vérifie l'APK (package, Leanback, URL du backend dans `libapp.so`), et **publie** sur la release GitHub `zuno-tv` uniquement si `publish=true` (dispatch manuel) ou sur push vers `main`.
- Un push sur la branche lance un build de vérification SANS publication. Pour publier : Actions → « Build Zuno TV » → Run workflow → `publish = true`.
- Lien client (ne change jamais) : `https://github.com/manzilionellm-dotcom/tvking/releases/download/zuno-tv/zuno-tv.apk`. `versionCode` = secondes epoch (toujours croissant).
- Commits fréquents, messages clairs, branche `claude/app-admin-panel-connection-9fphfr` (ne pousse pas sur `main` sans accord).
- Impeller est **désactivé** volontairement (`EnableImpeller=false` dans le manifeste patché) : Skia est plus stable avec la vidéo sur les box (ticket Flutter #180831). Ne réactive pas Impeller.

---

## 3. Architecture utile (où travailler)

```
android-app/
├── lib/main_tv.dart                         # boot TV : init DB, licence, sync sources, synchro auto des listes
├── lib/core/app/boot_guard.dart             # disjoncteur anti-boucle de redémarrage (mode sans échec)
├── lib/core/app/guarded_main.dart           # filets d'erreurs Dart (ErrorWidget, FlutterError, Zone), cache images borné
├── lib/core/crash/crash_reporting.dart      # anneau MÉMOIRE de 50 erreurs (pas persisté → à transformer en boîte noire)
├── lib/core/curation/title_curator.dart     # nettoyage des noms (regex précompilées)
├── lib/features/channels/domain/channel.dart      # modèle Channel + caches + ChannelPrecompute (isolate)
├── lib/features/channels/domain/channel_genre.dart # classifieur genre/pays/qualité (regex précompilées)
├── lib/features/playlists/data/playlist_repository.dart # SQLite (sqflite), import M3U/Xtream, refresh, mergeAllPlaylists
├── lib/features/playlists/data/playlist_database.dart   # schéma SQLite (tables playlists, channels)
├── lib/features/playlists/data/m3u_fetcher.dart         # téléchargement M3U borné (60 Mo), sniff anti-HTML
├── lib/features/playlists/data/m3u_parser.dart          # parse M3U en isolate (octets transférés)
├── lib/features/playlists/data/xtream_client.dart       # API Xtream ; get_live_streams décodé+mappé en isolate
├── lib/features/playlists/data/remote_source_repository.dart # sources poussées par le panel (GET /api/device-source/:mac)
├── lib/features/playlists/data/playlist_import_limits.dart   # plafonds : 60 Mo M3U, 80 Mo JSON Xtream, 50 000 chaînes
├── lib/features/epg/data/epg_repository.dart            # XMLTV → SQLite (parse en flux MAIS sur le fil UI)
├── lib/features/recordings/…                            # enregistrement du direct (relais local + fichier .ts)
├── lib/features/tv/core/tv_activity.dart                # « la box est occupée » (Direct / lecteur ouverts)
├── lib/features/tv/core/tv_focusable.dart               # widget de focus D-pad (3 animations implicites + 2 ombres floues)
├── lib/features/tv/presentation/tv_hub_screen.dart      # accueil à tuiles (source-push panel toutes les 20 s)
├── lib/features/tv/presentation/tv_live_screen.dart     # DIRECT : 3 colonnes (catégories · liste · aperçu+guide), 2 000 lignes
├── lib/features/tv/presentation/tv_live_preview.dart    # aperçu vidéo (vue native créée après 1,5 s d'immobilité)
├── lib/features/tv/presentation/tv_player_screen.dart   # lecteur plein écran (watchdog 15 s, REC, favoris)
├── lib/features/tv/presentation/tv_add_source_screen.dart # « Ajouter ma liste » Xtream (écran de la capture ci-dessous)
├── lib/features/tv/presentation/tv_settings_screen.dart # Réglages (c'est LÀ que va l'entrée « Boîte noire »)
├── lib/features/tv/presentation/tv_diagnostic_screen.dart # diag caché (HAUT-HAUT-BAS-BAS sur l'accueil)
├── packages/native_video_player/               # plugin local : ExoPlayer/Media3 sur SurfaceView, PlatformView en Hybrid Composition
└── packages/tvking_device/                     # plugin local : infos appareil (getMemoryInfo…)
```

Données : SQLite via `sqflite`. Lecture des chaînes par tranches de 5 000 (`_readChannelsBounded`) puis **matérialisation de jusqu'à 50 000 objets `Channel` en RAM** (`kMaxInMemoryChannels`). Mode TV : `PlaylistRepository.mergeAllPlaylists = true` → toutes les playlists sont fusionnées (ids dupliqués suffixés `~p<playlistId>`).

---

## 4. Les bugs à corriger, avec ce qu'on sait

### BUG A (priorité 1) — Ajout d'un code Xtream depuis la box : l'app se ferme et redémarre
Écran « Ajouter ma liste » (`tv_add_source_screen.dart`), serveur choisi, identifiant/mot de passe saisis, bouton « Connexion… » → au bout de quelques secondes **le process meurt et l'app redémarre** (la box affiche un message système de plantage). Aucune exception Dart n'est vue : c'est une mort du process (très probablement **OOM natif** pendant `get_live_streams`, ou une erreur dans l'isolate de `compute`).

Chaîne actuelle (`xtream_client.dart` → `fetchLiveChannels`) : téléchargement borné à 80 Mo → octets transférés via `TransferableTypedData` à `compute(_mapLiveStreamsInIsolate, …)` → `utf8.decode` (crée une String de la taille du JSON) → `jsonDecode` (arbre d'objets ≈ 5-10× la taille du JSON) → mapping en `List<Channel>` → copie de retour vers l'isolate principal. Sur une box 1 Go, un JSON de 20-40 Mo suffit à dépasser la mémoire.

Ce qu'il faut faire :
1. **D'abord instrumenter** (voir §5 boîte noire) pour lire la vraie cause au redémarrage suivant (`ApplicationExitInfo` : OOM ? ANR ? crash natif ? signal 9 ?). Ne corrige pas à l'aveugle.
2. Supprimer la String intermédiaire : décoder le JSON directement depuis les octets avec le décodeur fusionné `utf8.decoder.fuse(json.decoder)` (`dart:convert`), qui parse l'UTF-8 sans créer de `String`.
3. **Borner la mémoire de l'import** : si la réponse `get_live_streams` dépasse un seuil raisonnable (par ex. 12 Mo), basculer sur un import **par catégorie** (`get_live_streams&category_id=<id>`, l'API Xtream le supporte) : chaque catégorie est petite, parsée, mappée, **insérée en base puis libérée**. Le pic mémoire devient celui d'une catégorie. Référence : OwnTV (open source, Kotlin) lit le JSON Xtream avec `JsonReader` « so a huge provider payload is never fully buffered » et annonce ~50 000 chaînes.
4. Idem pour le M3U : parser en **flux ligne par ligne** dans l'isolate (aujourd'hui : fichier entier → `split('\n')`, plusieurs copies).
5. Pendant l'import, l'UI doit rester réactive (le fil UI ne reçoit que des lots de `Channel` déjà construits, insérés par lots de 1 000).

### BUG B (priorité 2) — Direct gèle puis l'app est tuée sur grosse liste
Symptôme d'origine : ouverture de Direct, aperçu sur le logo, écran figé > 5 s, Android tue l'app. Cause trouvée et corrigée (commit `52d39d16`) : le premier calcul des noms/genres de TOUTES les chaînes (~10 M de tests regex) tournait sur le fil UI. Il est désormais dans un isolate (`ChannelPrecompute`, par tranches de 2 000). Vérifie qu'il ne reste **aucune** passe O(n) lourde sur le fil UI : `_recompute()` dans `tv_live_screen.dart` (map des tendances, « Pour vous », `_byId`), `_ingest()`, `tv_search_screen.dart` (première recherche : curation de tous les noms), mode enfants.

### BUG C (priorité 2) — Fluidité du défilement dans Direct
Faits sourcés (doc officielle Flutter « platform views ») : la vue native en **Hybrid Composition** (notre `native_video_player`, `initExpensiveAndroidView`) « fusionne les threads raster et plateforme, ce qui dégrade le FPS de Flutter » tant qu'elle est dans l'arbre. Corrigé partiellement (commit `56a4d769`) : la vue native n'est créée qu'après 1,5 s d'immobilité du focus et détruite dès que le focus bouge. À vérifier sur box réelle avec `flutter run --profile` + DevTools (timeline) si tu as un appareil ; sinon, instrumente le temps de frame (voir §5) et lis les chiffres dans la boîte noire.
Autres coûts par ligne à examiner sans changer le rendu : `tv_focusable.dart` (AnimatedScale + AnimatedOpacity + AnimatedContainer + 2 `BoxShadow` floues par ligne focalisée) — un rendu identique peut être obtenu moins cher (par ex. ombre pré-rendue, `RepaintBoundary`, éviter de reconstruire la ligne entière au changement de focus).

### BUG D (priorité 3) — Mémoire bornée sur la liste
L'app garde jusqu'à 50 000 objets `Channel` en RAM. Les apps natives fluides utilisent une fenêtre paginée (Room + Paging 3). Objectif : la liste de Direct lit la base par fenêtres (SQLite `LIMIT/OFFSET` ou keyset) et ne matérialise que ce qui est proche de l'écran ; catégories et compteurs calculés par requête SQL (`GROUP BY`), pas en mémoire. La disposition 3 colonnes et le comportement du focus restent identiques. C'est le chantier le plus lourd : fais-le en dernier, avec des tests.

### BUG E (priorité 3) — EPG sur le fil UI
`epg_repository.dart` parse le XMLTV en flux mais **sur l'isolate principal** (pas de `compute`, pas de timeout sur `client.send`, taille non bornée). Pour Xtream, la synchro est sautée (les ids `xtream-<id>` ne correspondent pas aux ids XMLTV, il faudrait capturer `epg_channel_id` de `get_live_streams`). À faire : parser en isolate par lots, borner, timeout, et apparier Xtream via `epg_channel_id`.

---

## 5. BOÎTE NOIRE (obligatoire, dans les Réglages)

Le propriétaire veut savoir **exactement** pourquoi l'app s'est fermée, sans ordinateur ni logcat. Implémente un enregistreur de vol :

- **Journal persistant sur disque** (`path_provider` → répertoire de l'app), fichier texte tournant (par ex. 2 × 512 Ko), écrit avec **flush immédiat** pour survivre à une mort brutale du process. Horodatage, niveau, tag, message.
- **Ce qu'on journalise** : démarrage (version, `versionCode`, modèle, Android, RAM totale/disponible via `tvking_device.getMemoryInfo`, mode sans échec oui/non), chaque écran ouvert/fermé, chaque import (source, type, taille téléchargée, nombre de chaînes, durée, échec + message), chaque synchro auto, chaque erreur du lecteur (ExoPlayer : code + message), les zaps, les reconnexions du watchdog, la mémoire Dart (`ProcessInfo.currentRss`) toutes les 30 s et avant/après chaque étape lourde, les erreurs rattrapées par `CrashReporting`.
- **Détection des gels du fil UI** : un chien de garde qui mesure la dérive d'un `Timer` périodique ou les `FrameTiming` (`SchedulerBinding.addTimingsCallback`) et journalise tout blocage > 700 ms avec ce qui était en cours.
- **Raison des morts de process** (côté natif, plugin `tvking_device`, Kotlin) : au démarrage, lire `ActivityManager.getHistoricalProcessExitReasons()` (API 30+) et journaliser la dernière sortie : `REASON_LOW_MEMORY`, `REASON_ANR`, `REASON_CRASH_NATIVE`, `REASON_SIGNALED`, `REASON_EXCESSIVE_RESOURCE_USAGE`, avec `description`, `pss`, `rss`, timestamp. En dessous d'API 30 : consigner « inconnu » et le dernier événement journalisé avant la mort.
- **Écran « Boîte noire » dans Réglages** (`tv_settings_screen.dart` → nouvel écran, même style que les autres écrans de réglages, aucune nouvelle couleur/police) : résumé en tête (dernière fermeture : quand, raison, mémoire), puis le journal (dernières 300 lignes, navigable à la télécommande), boutons « Copier » (presse-papiers) et « Effacer ». Bonus : « Envoyer au revendeur » = envoyer les 200 dernières lignes dans le heartbeat existant (`/api/heartbeat`) sous une clé optionnelle, SANS modifier le Worker (le serveur ignore les champs inconnus ; à vérifier d'abord).
- Le journal doit aussi être lisible depuis l'écran de diagnostic caché existant (`tv_diagnostic_screen.dart`).

Critère de réussite : après une fermeture brutale, on ouvre Réglages → Boîte noire et on lit la raison (ex. « 25/09 21:14 — LOW_MEMORY — pss 612 Mo — dernière action : import Xtream serveur S1, 31 Mo reçus ») sans aucun outil externe.

---

## 6. ENREGISTREMENT DU DIRECT (« j'enregistre le match en cours »)

Il existe déjà un enregistrement (`lib/features/recordings/`, touche 4 = REC dans `tv_player_screen.dart`, relais local qui copie le flux vers un fichier `.ts`, écran `tv_recordings_screen.dart`, service Android en avant-plan). Il doit devenir **simple et fiable** :

- Depuis le lecteur : un appui sur la touche REC (ou l'action REC dans la barre du lecteur existante) démarre l'enregistrement **immédiatement**, avec un état visible **avec les éléments déjà présents** (pas de nouveau design) ; un second appui arrête.
- « Enregistrer jusqu'à la fin du programme » quand l'EPG connaît l'heure de fin (arrêt automatique), et un arrêt manuel toujours possible.
- L'enregistrement continue si l'utilisateur quitte le lecteur ou l'app (service en avant-plan avec notification, `WAKE_LOCK`), s'arrête proprement si l'espace disque manque (seuil vérifié avant et pendant), et le fichier est **lisible dans l'app** (`tv_recording_player_screen.dart`) après un redémarrage.
- Journaliser dans la boîte noire : début, arrêt, octets écrits, cause d'arrêt.
- Tester : 10 minutes d'enregistrement d'une chaîne HD, puis lecture du fichier du début à la fin.

---

## 7. MULTI-LISTES (façon TiviMate)

Déjà en place : N listes ajoutées depuis la box (tuile Serveur : Xtream ou M3U), fusionnées dans Direct, synchro automatique (90 s après le boot pour les listes de plus de 24 h, puis toutes les 24 h, jamais pendant que Direct ou le lecteur sont ouverts — cf. `TvActivity`). Le panel, lui, pousse jusqu'à 3 sources (6 dans le code du dépôt, pas déployé).

À garantir : 5 codes de 10 000 chaînes chacun → import successif sans mort du process, Direct fluide, catégories de même nom fusionnées, favoris conservés, suppression d'une liste = ses chaînes disparaissent (et rien d'autre).

---

## 8. Ce qui a déjà été fait aujourd'hui (ne le refais pas, appuie-toi dessus)

| Commit | Contenu |
|---|---|
| `b4173264` | regex précompilées (curateur, classifieur), aperçu piloté par `ValueNotifier` (plus de rebuild global au focus), labels de catégories mémoïsés, import Xtream en isolate, EPG Xtream sautée, **fusion de toutes les playlists** (`mergeAllPlaylists`) |
| `ccd0967f` | source-push direct depuis le panel sur l'accueil (poll 20 s, ouverture auto de Direct) |
| `1dbd9e8f` + `52d39d16` | synchro auto des listes ; **pré-calcul en isolate** (`ChannelPrecompute`) ; `TvActivity` (pas de synchro pendant la navigation) |
| `56a4d769` | **aucune vue native pendant le défilement** (aperçu créé après 1,5 s, détruit au mouvement) ; M3U décodé + parsé dans l'isolate (octets transférés) |

Version publiée correspondante : `versionCode 1790364402`.

---

## 9. Méthode de travail exigée

1. Commence par la **boîte noire** (§5) : sans elle, tu ne pourras pas prouver la cause du BUG A ni mesurer la fluidité. Publie un build, fais reproduire le plantage au propriétaire, lis la raison.
2. Puis BUG A (import Xtream borné, par catégorie, décodeur fusionné), puis BUG C/B (fluidité mesurée), puis §6 (enregistrement), puis BUG E (EPG), puis BUG D (pagination) en dernier.
3. Pour chaque chantier : un commit, un message qui explique le POURQUOI, `flutter analyze` sans erreur ni warning, tests unitaires pour les parseurs (M3U/Xtream/XMLTV) avec des fichiers de 30 000 entrées générés, et une **mesure avant/après** consignée dans le message de commit (temps d'import, RSS max, ms par frame).
4. Si tu dois choisir entre « joli » et « stable », tu choisis stable. Si une optimisation demande un changement visuel, tu la mets de côté et tu le dis.
5. Chaque réponse au propriétaire se termine par : ce qui est fait, ce qui est prouvé (chiffres), ce qui reste, et le lien de l'APK avec son `versionCode` quand un build est publié.

---

## 10. Définition de « terminé »

- Import d'un code Xtream de 30 000 chaînes sur une box 1 Go : aucune mort de process, écran réactif pendant l'import, durée < 90 s, raison lisible dans la boîte noire si ça échoue.
- 30 minutes de zapping dans Direct sur 30 000+ chaînes : aucune fermeture, aucun gel > 700 ms consigné par le chien de garde.
- 5 listes fusionnées : mêmes critères.
- Enregistrement : 10 minutes enregistrées et relues.
- Boîte noire : chaque fermeture brutale a une entrée avec raison + contexte.
- Zéro pixel changé (comparer captures avant/après sur accueil, Direct, lecteur, Réglages).
