# Recording — Architecture actuelle

> **Statut du document** : audit Phase 0 (lecture seule). Aucune
> recommandation, aucune proposition de refactor — uniquement la
> description **factuelle** de ce qui existe dans le code au
> 2026-05-31. Toutes les conclusions pointent vers le fichier et
> la ligne. Toute affirmation non vérifiée empiriquement est
> préfixée par **[HYPOTHÈSE]**.

---

## 1. Vue d'ensemble

Le sous-système Recording capture un flux IPTV live (MPEG-TS brut
ou HLS) dans un fichier `.ts` local, persiste la métadonnée en
SQLite, et survit au verrouillage écran / app en background grâce
à un Foreground Service Android.

| Couche | Chemin | Contenu |
|---|---|---|
| Dart — données | `lib/features/recordings/data/` | 4 fichiers, ~970 LoC |
| Dart — domaine | `lib/features/recordings/domain/` | 1 fichier `recording.dart` |
| Dart — UI | `lib/features/recordings/presentation/` | 1 fichier `recordings_screen.dart` (518 LoC) |
| Native Kotlin | `android_overlay/google_cast/` | `RecordingForegroundService.kt` + `RecordingServiceBridge.kt` |
| Intégration player | `lib/features/player/presentation/video_player_screen.dart` | méthodes `_startRecording`, `_stopRecording`, `_onRecordingAutoStopped` |

**Architecture en deux pipelines** (commentaire `http_recording_downloader.dart:142-150`) :

- **Raw MPEG-TS** : 1 seule connexion HTTP qui dure des heures, le
  serveur envoie un flux continu, on écrit au fil de l'eau dans
  le `.ts`.
- **HLS (`.m3u8`)** : polling de la playlist toutes les 5s,
  téléchargement des segments `.ts` nouveaux, concaténation.

---

## 2. Composants — inventaire

### 2.1 Couche Dart

| Fichier | Rôle | LoC |
|---|---|---|
| `http_recording_downloader.dart` | Singleton orchestrant **N jobs parallèles**. Map `Map<String, _Job>` keyed par filePath. Auto-reconnect, plafond 6h, callback `onAutoStopped`. | 689 |
| `recording_service.dart` | Wrapper Dart fin du MethodChannel `com.manzilionellm.tvking/recording_service`. Best-effort — ne throw jamais. | 64 |
| `recording_repository.dart` | Persistance SQLite. Crée le schéma au boot, expose stream `List<Recording>` via `BroadcastStreamController`. Deux paths de finalisation : `finishRecording(rec)` et `finishRecordingByPath(path)`. | 202 |
| `gallery_exporter.dart` | Export vers MediaStore (Galerie Android). | — |

### 2.2 Modèle de domaine (`recording.dart`)

```dart
@immutable class Recording {
  final int? id;
  final String channelId;
  final String channelName;
  final String? programTitle;
  final String filePath;
  final int startedAt;        // millisSinceEpoch
  final int? endedAt;         // null = en cours
  final int fileSizeBytes;    // 0 tant que pas finalisé
  final String? channelLogoUrl;
}
```

**Convention** : `endedAt == null` ⇔ enregistrement EN COURS
(visible dans la card avec badge "EN COURS" + bouton Stop, cf.
`recordings_screen.dart:210` et `recordings_screen.dart:302-328`).

**Note** : le commentaire de tête (`recording.dart:1-6`) référence
toujours `libmpv stream-record` qui **n'est plus utilisé** (cf.
section 3.1). Stale comment à corriger.

### 2.3 Native Kotlin

| Fichier | Rôle |
|---|---|
| `RecordingForegroundService.kt` | Foreground service Android. Acquiert `PartialWakeLock` (CPU, max 12h) + `WifiLock HIGH_PERF`. Notification persistante. **`START_NOT_STICKY`**. |
| `RecordingServiceBridge.kt` | MethodChannel handler. Méthodes `start(title)` et `stop()`. Utilise `ContextCompat.startForegroundService` pour API 26+. |

### 2.4 Permissions & manifest

**[HYPOTHÈSE]** Le manifest doit déclarer :
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_DATA_SYNC` (Android 14+)
- `WAKE_LOCK`
- `INTERNET`

À vérifier dans `android/app/src/main/AndroidManifest.xml` (non
lu dans cette session). Le patch `apply_cast_patch.sh` est censé
ajouter les méta-data Cast — à confirmer pour les permissions
recording.

---

## 3. Cycle de vie d'un recording — flux normal

### 3.1 Historique : pourquoi pas `libmpv stream-record` ?

Commentaire `http_recording_downloader.dart:1-11` :

> Remplace l'API libmpv `stream-record` qui s'avère silencieusement
> inopérante sur les flux IPTV de l'utilisateur (constaté
> empiriquement : setProperty retourne sans erreur mais le `.ts`
> reste à 0 octets, y compris sur des flux bénins comme BFM TV
> testés 3 minutes).

→ Le pipeline actuel ouvre une **2ᵉ connexion HTTP** vers le
même `streamUrl` (en plus de celle du player media_kit). Coût :
double bande passante, et **certains fournisseurs IPTV limitent
à 1 connexion par credentials**. Pris en compte côté UX
(`video_player_screen.dart:469-474` : message "Ton fournisseur
IPTV n'autorise qu'une seule connexion à la fois").

### 3.2 `_startRecording` — séquence (`video_player_screen.dart:361-440`)

```
[user tape REC]
   │
   ▼
RecordingRepository.createFilePath(channelName, programTitle)
   │  → "/.../Recordings/<safe-name>-YYYYMMDD-HHMM.ts"
   │
   ▼
RecordingService.instance.start(title)   ← FIRST
   │  → MethodChannel → RecordingServiceBridge → Intent ACTION_START
   │  → RecordingForegroundService.onStartCommand
   │     ├─ createChannelIfNeeded (Android 8+)
   │     ├─ startForeground(NOTIFICATION_ID, buildNotification(title))
   │     └─ acquireLocks()
   │        ├─ PartialWakeLock (12h max safety timeout)
   │        └─ WifiLock HIGH_PERF
   │
   ▼
HttpRecordingDownloader.instance.start(streamUrl, filePath, onAutoStopped)
   │  → branchement HLS vs Raw selon ".m3u8" dans l'URL
   │
   │   ─ Raw : _startRaw
   │     ├─ openWrite(filePath)
   │     ├─ _openRawConnection (HttpClient, follow redirects, UA VLC)
   │     ├─ _jobs[filePath] = job
   │     ├─ _armMaxDurationTimer(6h)
   │     └─ _attachRawListener (onError/onDone → _reconnectRaw)
   │
   │   ─ HLS : _startHls
   │     ├─ probe playlist
   │     ├─ openWrite(filePath)
   │     ├─ _jobs[filePath] = job
   │     ├─ _armMaxDurationTimer(6h)
   │     └─ _runHlsLoop (fire-and-forget, polling 5s)
   │
   ▼ ok == true ?
   │
   ├─ false ──► RecordingService.stop() + toast erreur (return)
   │
   ▼
RecordingRepository.startRecording(channelId, channelName, …, filePath, logoUrl)
   │  → INSERT INTO recordings (ended_at = NULL)
   │
   ▼
setState(_activeRecording = rec) + toast "Enregistrement démarré"
```

**Ordre critique documenté** (`video_player_screen.dart:382-395`) :
le ForegroundService DOIT démarrer **AVANT** la requête HTTP du
downloader, sinon dès que l'utilisateur appuie HOME, Android met
le CPU en sommeil et coupe le WiFi → socket tuée → enregistrement
silencieusement arrêté. C'est le bug "ADULT: ALBA XXX" du user
(27 Mo en foreground, 0 octet de plus en background).

### 3.3 `_stopRecording` — séquence (`video_player_screen.dart:442-485`)

```
[user tape STOP]
   │
   ▼
HttpRecordingDownloader.instance.stop(filePath: rec.filePath)
   │  → job.stopping = true (empêche reconnexion en cours)
   │  → _stopJob(job) :
   │     ├─ maxTimer.cancel()
   │     ├─ sub.cancel()
   │     ├─ sink.flush() + close()
   │     └─ client.close(force: true)
   │  → _jobs.remove(filePath)
   │  → return bytesWritten
   │
   ▼
RecordingRepository.finishRecording(rec)
   │  → UPDATE recordings SET ended_at = now, file_size_bytes = stat(filePath)
   │
   ▼
SI activeCount == 0 :
   │  → RecordingService.stop()
   │  → ForegroundService release locks + stopSelf
   │
   ▼
setState(_activeRecording = null) + toast résultat
```

### 3.4 Auto-stop — branche callback (`http_recording_downloader.dart:597-616`, `video_player_screen.dart:493-509`)

Déclenché par 2 chemins :

1. **Plafond 6h** atteint → `_armMaxDurationTimer` firing →
   `_autoFinish(filePath)`.
2. **Serveur définitivement injoignable** → après
   `_kMaxReconnectFailures = 12` reconnexions consécutives qui
   échouent → `_autoFinish(filePath)`.

```
_autoFinish(filePath)
   │
   ├─ _jobs.remove(filePath)
   ├─ job.stopping = true
   ├─ _stopJob(job)   ← async, pas awaited
   └─ scheduleMicrotask(() => onAutoStopped(filePath))
                                      │
                                      ▼
                          [Dart code de l'UI]
                          _onRecordingAutoStopped(filePath)
                              │
                              ├─ RecordingRepository.finishRecordingByPath(filePath)
                              │     → WHERE file_path = ? AND ended_at IS NULL
                              │
                              ├─ SI activeCount == 0 : RecordingService.stop()
                              │
                              └─ SI _activeRecording.filePath == filePath :
                                  setState(_activeRecording = null) + toast
```

**Subtilité importante** : le callback `onAutoStopped` est attaché
sur le job par `start(...)`. Si l'utilisateur a quitté l'écran
`VideoPlayerScreen` entre-temps, **le callback fait `mounted`
check** et **finalise quand même la base** — donc l'enregistrement
sera bien marqué `ended_at` dans la DB, même si le badge "REC"
ne se met plus à jour côté UI.

### 3.5 Reconnexion auto — pipeline Raw (`http_recording_downloader.dart:316-365`)

```
[serveur ferme la socket : onDone OU onError]
   │
   ▼
_reconnectRaw(job, streamUrl)
   │
   ├─ SI job.stopping OU !_jobs.contains(filePath) : return
   ├─ SI job.elapsed >= 6h : _autoFinish, return
   │
   ├─ sub.cancel() (sink reste OUVERT — on append)
   ├─ await 2s (anti-hammering)
   │
   ▼
_openRawConnection(job, streamUrl)
   │
   ├─ null ─► job.reconnectFailures++
   │           SI >= 12 : _autoFinish, return
   │           wait = (2 * fail).clamp(2, 16)
   │           récurse _reconnectRaw
   │
   └─ resp ─► job.reconnectFailures = 0
              job.reconnectCount++
              _attachRawListener(job, streamUrl, resp)
```

**Backoff** : 2s, 4s, 6s, 8s… plafonné à 16s.

### 3.6 Reconnexion auto — pipeline HLS (`http_recording_downloader.dart:425-500`)

Pas de reconnect distinct — la boucle `_runHlsLoop` est un `while`
qui réessaie tant que `_jobs.contains(filePath) && !job.stopping`,
avec compteur `consecutiveErrors` (reset à chaque cycle réussi).
Mêmes seuils : 12 erreurs consécutives, backoff 2-16s.

---

## 4. État interne d'un job

```dart
class _Job {
  final String filePath;
  HttpClient? client;
  StreamSubscription<List<int>>? sub;
  IOSink? sink;
  final DateTime startedAt = DateTime.now();
  Duration get elapsed => DateTime.now().difference(startedAt);
  bool stopping = false;
  Timer? maxTimer;
  void Function(String filePath)? onAutoStopped;
  int reconnectCount = 0;       // diagnostic
  int reconnectFailures = 0;    // consécutif, reset au succès
  final Set<String> seenSegments = <String>{};  // HLS only
  int bytesWritten = 0;
}
```

**State machine implicite** (pas d'enum, pas de FSM explicite —
les transitions sont éclatées entre `_startRaw`, `_attachRawListener`,
`_reconnectRaw`, `_stopJob`, `_autoFinish`) :

```
                       ┌───────────┐
                       │  CREATED  │  (constructeur _Job)
                       └─────┬─────┘
                             │
              openWrite + _openRawConnection
                             │
                             ▼
                       ┌───────────┐
                       │  STREAMING │  (sub écoute, sink.add(chunk))
                       └─────┬─────┘
                             │
                ┌────────────┼────────────────┐
                │            │                │
            onDone/      stop(filePath)    timer 6h
            onError      par utilisateur    OR fail>=12
                │            │                │
                ▼            ▼                ▼
         ┌───────────┐  ┌──────────┐    ┌──────────────┐
         │ RECONNECT │  │ STOPPING │    │ AUTO_STOPPING │
         └─────┬─────┘  └────┬─────┘    └──────┬───────┘
               │             │                  │
       _openRawConnection    │                  │
        ┌──────┴──────┐      │                  │
   success         fail≥12   │                  │
        │             │      │                  │
        └──► STREAMING│      ▼                  ▼
                      │  _stopJob       _autoFinish (cb)
                      │      │           + _stopJob
                      │      ▼               │
                      └──► [JOB REMOVED FROM MAP]
```

**Aucune** transition n'est loggée structurellement aujourd'hui —
juste des `debugPrint('[Rec] ...')` épars.

---

## 5. Persistance — schéma SQLite

Table `recordings` (`recording_repository.dart:40-52`) :

```sql
CREATE TABLE IF NOT EXISTS recordings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  channel_id TEXT NOT NULL,
  channel_name TEXT NOT NULL,
  program_title TEXT,
  file_path TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  file_size_bytes INTEGER NOT NULL DEFAULT 0,
  channel_logo_url TEXT       -- ajoutée par ALTER TABLE migration
);
```

**Migration** (`recording_repository.dart:57-63`) : `ALTER TABLE
… ADD COLUMN channel_logo_url TEXT` wrap dans try/catch
`DatabaseException` pour être idempotent.

**Stream** : `_controller` est un `StreamController.broadcast()`,
émet la liste complète à chaque `_refresh()`. Pas de diff
incrémental — l'UI rebuild toute la liste à chaque tick.

---

## 6. Native Android — détails

### 6.1 `RecordingForegroundService.kt`

**`onStartCommand`** (`RecordingForegroundService.kt:75-107`) :

- `ACTION_START` + EXTRA_TITLE → `startForeground` + `acquireLocks`.
- `ACTION_STOP` → `releaseLocks` + `stopForeground(STOP_FOREGROUND_REMOVE)`
  + `stopSelf`.
- `else` (service relancé par l'OS sans intent — typique d'un kill
  mémoire suivi d'un restart) → on `releaseLocks` + `stopSelf`.

**Return value** : `START_NOT_STICKY`. Commentaire ligne 103-106 :

> NOT_STICKY = ne pas redémarrer le service si killed. Cohérent
> car libmpv aussi sera mort → relancer un foreground sans
> enregistrement actif n'a aucun sens.

**Conséquence majeure** : si l'OS tue notre process pendant un
enregistrement, **l'enregistrement est définitivement perdu** :

- Le `.ts` reste sur le disque, partiel.
- La row SQLite reste avec `ended_at = NULL` (orphelin).
- Aucun mécanisme de redémarrage automatique.
- Aucun crash report.

L'UI `RecordingsScreen` détecte l'orphelin (`endedAt == NULL` mais
`HttpRecordingDownloader.bytesWrittenFor(path) == 0`) et propose
un bouton STOP qui appelle `finishRecording` pour finaliser
manuellement.

### 6.2 Wake locks (`RecordingForegroundService.kt:121-155`)

```kotlin
PartialWakeLock(WAKE_LOCK_TAG).acquire(12 * 60 * 60 * 1000L)  // 12h
WifiLock(WIFI_MODE_FULL_HIGH_PERF, WIFI_LOCK_TAG).acquire()
```

- **12h max safety timeout** sur le wake lock — au-delà, Android
  release auto. Plus large que le plafond 6h Dart pour couvrir
  les overlaps.
- `setReferenceCounted(false)` : un seul acquire/release pair par
  cycle, pas de comptage.
- `onDestroy` (`:109-115`) appelle `releaseLocks` en safety net.

### 6.3 Notification

- Channel ID `recording_channel` créé à la demande
  (`createChannelIfNeeded` :191-209).
- `IMPORTANCE_LOW` + `setSilent(true)` → pas de son, pas de
  vibration, pas de heads-up. Juste l'icône dans la barre de
  statut.

---

## 7. Multi-recordings parallèles

Capability documentée en commentaire (`http_recording_downloader.dart:22-35`) :

> L'user a demandé "ajoute que je peux enregistrer plus de 10
> chaînes en même temps". On garde l'API publique singleton mais
> en interne on maintient une `Map<String, _Job>` keyed par
> filePath.

**Pas de limite logicielle** sur `_jobs`. Limite réelle = sockets
OS (~1000) + bande passante + provider IPTV (souvent 1-2
connexions concurrent max).

**Conséquences** :

- `RecordingService.stop()` n'est appelé QUE quand
  `activeCount == 0` (`video_player_screen.dart:461-463`,
  `recordings_screen.dart:148-152`, `video_player_screen.dart:496-498`).
- Le ForegroundService garde sa notif persistante tant qu'il
  reste au moins 1 job.
- La notif n'indique **pas** le nombre de jobs (juste le titre
  du dernier démarré).

---

## 8. Failure modes — recensement

### 8.1 Provider IPTV refuse la 2ᵉ connexion

**Cause** : la limite 1-connexion est très répandue chez les
revendeurs Xtream low-cost.
**Code** : `http_recording_downloader.dart:198-202` (`_openRawConnection`
retourne null après HTTP error).
**Comportement** : `_startRaw` retourne `false`, l'UI affiche le
message "Enregistrement impossible : le serveur a refusé la
requête" (`video_player_screen.dart:413-420`).
**Gravité** : **P2** — bien géré, message UX clair.

### 8.2 Process killed par l'OS pendant un enregistrement

**Cause** : pression mémoire Android (low-end devices), user
fait "Force Stop" depuis Réglages, crash natif.
**Code** : `RecordingForegroundService.kt:106` (`START_NOT_STICKY`).
**Comportement** : le fichier `.ts` reste partiel sur le disque,
la row SQLite garde `ended_at = NULL`. **Aucune récupération
automatique au prochain boot**.
**Code manquant** : pas de `recoverOrphans()` au démarrage de
l'app qui scannerait `WHERE ended_at IS NULL` et finaliserait
en se basant sur la taille actuelle du fichier.
**Mitigation existante** : `RecordingsScreen._stopRecording`
(ligne 136-176) gère ces orphelins à l'usage — l'utilisateur
voit un badge "EN COURS" qui ne grossit plus, tape Stop, la
fiche est finalisée.
**Gravité** : **P0**. Un enregistrement "fantôme" reste affiché
comme en cours indéfiniment si l'utilisateur ne va pas sur
`RecordingsScreen` pour le finaliser.

### 8.3 Socket fermée par le serveur (cas normal)

**Cause** : CDN qui recycle les connexions, rebalancing edge,
fenêtre de timeout du load balancer.
**Code** : `http_recording_downloader.dart:295-307` (onDone/onError
→ `_reconnectRaw`).
**Comportement** : reconnect transparent, append au même fichier,
compteur `reconnectFailures` reset au succès suivant.
**Gravité** : **P2** — c'est explicitement le bug fix V3 (cf.
commentaire ligne 37-56), bien testé.

### 8.4 Serveur définitivement injoignable

**Cause** : provider down, internet coupé, token expiré pendant
l'enregistrement.
**Code** : `http_recording_downloader.dart:341-349` (test
`reconnectFailures >= _kMaxReconnectFailures` = 12).
**Comportement** : `_autoFinish(filePath)` → callback UI.
**Gravité** : **P1**. Le message UX final
("Enregistrement terminé (limite de 6 h atteinte)" —
`video_player_screen.dart:501-504`) est **incorrect dans ce cas**
: ce n'est PAS la limite de 6h qui s'est déclenchée, c'est le
serveur qui est mort. Pas de distinction côté UI.

### 8.5 Plafond 6h atteint

**Cause** : enregistrement long oublié (match + prolongations,
nuit de docu).
**Code** : `http_recording_downloader.dart:319-326` (raw) et
`:434-440` (HLS).
**Comportement** : `_autoFinish` proprement.
**Gravité** : **P2**.

### 8.6 Wake lock libération oubliée

**Cause** : crash du service entre `acquireLocks` et
`releaseLocks`.
**Mitigation existante** : `onDestroy` (`:109-115`) appelle
`releaseLocks` en safety. Timeout 12h sur le wake lock garantit
que l'OS le release de toute façon.
**Gravité** : **P2**.

### 8.7 Disque plein

**Cause** : 6h × 5 Mbps ≈ 13 Go par enregistrement, ×N jobs
parallèles.
**Code** : aucune vérification d'espace disque avant
`createFilePath` ni pendant l'écriture.
**Comportement** : `sink.add(chunk)` lève une `FileSystemException`
qui est avalée par le `try/catch` (`http_recording_downloader.dart:282-287`,
juste un `debugPrint`). Le job continue d'essayer, le compteur
`bytesWritten` continue d'incrémenter (mais le sink ne reçoit
rien) → on log "X bytes" alors qu'on a écrit 0.
**Gravité** : **P1** — le compteur ment, l'utilisateur croit
que ça marche.

### 8.8 Compteur `bytesWritten` ment en cas d'erreur d'écriture

**Cause** : `job.bytesWritten += chunk.length` AVANT vérification
que `sink.add(chunk)` n'a pas levé (`http_recording_downloader.dart:281-288`).
Le `try/catch` enrobe les deux, donc si add throw, bytesWritten
N'EST PAS incrémenté — sauf que l'incrément est APRÈS l'add dans
le try → en pratique l'invariant tient. **À CONFIRMER en relisant
de plus près**.

Code actuel :
```dart
(List<int> chunk) {
  try {
    job.sink?.add(chunk);
    job.bytesWritten += chunk.length;
  } catch (e) {
    if (kDebugMode) debugPrint('[Rec] sink write error: $e');
  }
},
```

→ OK, l'incrément ne se fait que si `add` n'a pas thrown. **Pas
de bug ici, point écarté**.

### 8.9 Trois paths de cleanup confus

**Cause** : `_stopJob` (helper bas niveau), `_cleanupJob` (retire
de la map + _stopJob), `_autoFinish` (retire + _stopJob + callback).
**Code** : `http_recording_downloader.dart:597-644`.
**Comportement** : `_cleanupJob` n'est **jamais appelé** dans
le code actuel (grep confirme : seul usage à `_startHls:414`,
mais c'est dans un catch qui ne devrait pas se déclencher car
la map ne contient pas encore le job à ce moment).
**Gravité** : **P2** — code mort. Ambiguïté entre les 3 noms.

### 8.10 Aucune persistance des credentials de l'enregistrement

**Cause** : `_Job` ne stocke pas la `streamUrl` originale (elle
est juste capturée en closure par `_reconnectRaw(streamUrl)`).
**Comportement** : si le process est killé et qu'on voulait
implémenter un resume au reboot, on n'a pas l'URL pour relancer
la connexion. La row SQLite ne stocke pas non plus la `streamUrl`.
**Gravité** : **P1** (en lien avec 8.2). Bloque toute
récupération transparente.

### 8.11 ForegroundService stop avant `activeCount == 0` — race

**Cause** : appel concurrent de `_stopRecording` (depuis le
player) et `_stopRecording` (depuis `RecordingsScreen`) sur deux
jobs différents en parallèle. Si les deux lisent
`activeCount == 1` puis appellent `stop()` ensemble, ils risquent
de croire qu'ils sont chacun "le dernier" et stop le service
deux fois (idempotent côté Android) — ou pire, si le timing fait
que l'un voit `activeCount == 0` après le sien et l'autre voit
`activeCount == 1` avant le sien, le service peut être stopped
alors qu'il y a encore 1 job.
**[HYPOTHÈSE]** : Dart étant mono-thread, `activeCount` read +
`stop()` call sont atomiques tant qu'il n'y a pas de yield
entre. Le code fait `await HttpRecordingDownloader.stop(...)`
PUIS `if (activeCount == 0) await stop()`. L'`await` du premier
yield ⇒ un autre handler peut tourner entre, et observer un
`activeCount` différent.
**Gravité** : **P2** théorique.

### 8.12 HLS — segments ré-téléchargés en cas de reconnect

**Cause** : `seenSegments` est dans `_Job`, jamais persisté.
Si le job est killed et redémarré (manuellement par user), on
re-télécharge depuis le début de la fenêtre live.
**Gravité** : **P2** — peu probable, et impacterait juste
quelques secondes en double.

### 8.13 HLS — pas d'auto-stop sur "playlist statique terminée"

**Cause** : si le serveur sert un VOD HLS avec `#EXT-X-ENDLIST`,
on continue à poller indéfiniment (ou jusqu'aux 6h / 12 fails).
**Code** : `_runHlsLoop` ne parse pas `#EXT-X-ENDLIST`.
**Gravité** : **P2** — cas exotique pour de l'IPTV live.

### 8.14 Notification ne reflète pas l'état multi-jobs

**Cause** : `buildNotification(title)` n'utilise que le titre du
DERNIER `start` appelé.
**Code** : `RecordingForegroundService.kt:174-189`.
**Comportement** : "Enregistrement en cours / France 2" même si
on enregistre aussi BFM TV + LCI en parallèle.
**Gravité** : **P2** — cosmétique.

### 8.15 Pas de structured logging

Identique au Cast (cf. cast-architecture.md §7.2). Tout passe par
`debugPrint('[Rec] ...')`.
**Gravité** : **P1** pour le diagnostic à distance.

---

## 9. Diagnostics & observabilité

### 9.1 Ce qui existe

- **Compteur `bytesWrittenFor(path)`** consultable en live par
  l'UI (`RecordingsScreen._liveBytesLabel`, `recordings_screen.dart:372-384`).
- **Compteur `reconnectCount` / `reconnectFailures`** dans `_Job`
  — **non exposé** à l'UI ni au diagnostic.
- **Logs debugPrint** abondants : `[Rec] raw downloader started`,
  `[Rec] socket fermée par le serveur`, `[Rec] reconnecté`,
  `[Rec] serveur injoignable, abandon`, etc.

### 9.2 Ce qui n'existe pas

- **Pas d'historique** des recordings auto-stopped (qui a fini
  au plafond 6h vs serveur mort vs user stop ?).
- **Pas de métriques** par job : durée moyenne avant reconnect,
  taille moyenne par chaîne, taux de jobs orphelins.
- **Pas de canal d'upload** des logs (cf. cast).
- **Pas de notification de fin** envoyée à l'utilisateur après
  un auto-stop si l'app est en background (juste un toast la
  prochaine fois qu'il revient sur le player de cette chaîne).

**Mitigation Phase 0** : `StructuredLogger` (cf.
`cast-architecture.md §7.2`) disponible pour Phase 1.

---

## 10. Sécurité — observations

### 10.1 Bonnes pratiques

- `streamUrl` n'est jamais logué dans le code de production
  (juste filePath).
- User-Agent custom VLC pour passer les filtres anti-bot Xtream.
- File path basé sur `getExternalStorageDirectory()` →
  `/storage/emulated/0/Android/data/<package>/files/Recordings/` —
  scope app, pas accessible aux autres apps sans permission.

### 10.2 Risques

- **WakeLock 12h** : si pour une raison le service ne stop pas
  proprement, le téléphone reste réveillé 12h max (batterie).
  C'est borné, donc P2.
- **Fichiers `.ts` non chiffrés** sur le storage externe — un
  autre user / une autre app avec MANAGE_EXTERNAL_STORAGE pourrait
  les lire. Cohérent avec le besoin export Galerie cependant.
- **Pas de quota** sur le nombre / la taille cumulée des
  recordings → un user qui oublie peut remplir son téléphone.

---

## 11. Métriques observées

Aucune métrique automatique. Champs disponibles via le repository :

| Métrique | Disponible ? | Source |
|---|---|---|
| Nb total de recordings | Oui | `RecordingRepository.current.length` |
| Nb en cours | Oui | `HttpRecordingDownloader.activeCount` |
| Bytes écrits par job | Oui (live) | `bytesWrittenFor(filePath)` |
| Durée par recording | Oui | `Recording.duration` (calculé) |
| Taille fichier final | Oui | `Recording.fileSizeBytes` |
| Nb de reconnexions | **Non exposé** | dans `_Job.reconnectCount` private |
| Causes d'auto-stop (6h vs server mort) | **Non distinguées** | un seul callback `onAutoStopped` |
| Orphelins (`ended_at IS NULL` au boot) | **Non détectés automatiquement** | DB-side seulement |

---

## 12. Récapitulatif

- Pipeline **double** (Raw + HLS) bien isolé, avec reconnect auto
  et plafond 6h — corrige les deux bugs majeurs documentés
  (V2 multi-recordings, V3 long-duration).
- **`START_NOT_STICKY`** est une décision **délibérée** qui
  protège la batterie mais crée des **orphelins SQLite** si l'OS
  tue le process. Pas de recovery automatique.
- **Trois paths de cleanup** (`_stopJob`, `_cleanupJob`,
  `_autoFinish`) → code partiellement mort, ambiguïté.
- **Notification simpliste** : ne reflète pas le multi-jobs.
- **Aucune télémétrie persistée** au-delà de la row SQLite
  basique.
- Le commentaire de tête de `recording.dart` mentionne encore
  `libmpv stream-record` — **stale comment** à corriger.

Pour la classification P0/P1/P2 et les recommandations d'action,
voir `phase-0-audit-cast-recording.md`.

---

## 13. Ajouts du 2026-09-05 — magnétoscope programmé, différé, stockage

> Cette section décrit ce qui a été **ajouté** par-dessus l'architecture
> ci-dessus (qui reste valable pour le REC manuel).

### 13.1 Enregistrement programmé (depuis le guide)

| Pièce | Chemin | Rôle |
|---|---|---|
| Modèle | `lib/features/recordings/domain/scheduled_recording.dart` | créneau (début/fin + marges 2 min / 5 min), statut `planned → recording → done / missed / failed / cancelled` |
| Table | `lib/features/recordings/data/scheduled_recording_repository.dart` | `scheduled_recordings` (SQLite, même base) |
| Cerveau | `lib/features/recordings/data/recording_scheduler.dart` | `schedule()`, `cancel()`, `tick()` 30 s ; décision **pure** `SchedulePlanner.decide` (testée) |
| Pont natif | `lib/features/recordings/data/native_recording_scheduler.dart` | canal `com.manzilionellm.tvking/recording_scheduler` |
| Natif | `packages/tvking_device/.../ScheduledRecording{Store,Alarms,Receiver,Service,Bridge}.kt` | alarmes exactes (`setExactAndAllowWhileIdle`), receiver START/STOP/BOOT, service au premier plan qui capte (raw TS + HLS) **sans Flutter** |
| UI | `tv_program_actions.dart` (TV), `program_actions_sheet.dart` (mobile), sections « Prévus » des écrans Enregistrements | « Enregistrer / Me rappeler » sur une émission à venir |

Pourquoi le natif vit dans le **plugin** et non dans l'overlay Cast :
le build TV n'applique pas `apply_cast_patch.sh` ; le plugin est
présent sur tous les builds Android. Les permissions (BOOT_COMPLETED,
USE_EXACT_ALARM, FOREGROUND_SERVICE…) sont dans le manifeste du plugin.

Réconciliation : au boot et toutes les 30 s, le Dart lit le carnet natif
(`statusAll`) et crée/finalise les fiches `recordings` correspondantes.
Sans natif (Windows), le Dart capte lui-même (`HttpRecordingDownloader`,
ou tee relais si la chaîne est déjà lue). Si le natif reste muet 3 min
après le début effectif, le Dart prend la main et retire les alarmes.

Limites honnêtes : une ligne « 1 connexion » ne permet pas de capter une
chaîne pendant qu'on en regarde une autre — le planificateur refuse deux
créneaux qui se chevauchent sur des chaînes différentes, mais ne peut pas
empêcher le fournisseur de couper si le client zappe pendant la capture
(le lecteur affiche un message quand une capture programmée démarre).

### 13.2 Différé (timeshift) — `LocalStreamRelay`

Pause en direct (via le relais) → `startTimeshift(realUrl)` ouvre un
fichier tampon dans le cache (`shiftSink`, même connexion amont, tee) ;
le lecteur est **arrêté** (pas mis en pause : un ExoPlayer en pause
laisserait le relais lui pousser le flux en mémoire). Reprise →
`setUrl('/shift?u=…')` : la route rejoue le fichier depuis l'octet 0 puis
le suit (tail) avec contre-pression (`flush()`). « Retour au direct » →
`stopTimeshift` (fichier supprimé) puis `_loadCurrentUrl`. Plafonds :
1,5 Go / 90 min ; au-delà le tampon cesse de grossir et le lecteur revient
au direct en atteignant la fin. Zap, sortie, arrière-plan, VPN perdu :
tampon jeté. Lecture directe (HLS, repli) : pause simple, pas de différé.

### 13.3 Stockage — `RecordingStoragePolicy`

Limite choisie par le client (5/10/20/50/100 Go, ou sans limite, pref
`rec_storage_limit_gb`). `selectForPurge` (pure, testée) supprime les
enregistrements terminés les plus anciens jusqu'à repasser sous la limite,
jamais un enregistrement en cours. Appliquée à chaque fin d'enregistrement
et à chaque changement de limite. Espace libre : `StatFs` natif, `df` en
repli. Une capture programmée ne démarre pas sous 500 Mo libres
(`failed / noSpace`).
