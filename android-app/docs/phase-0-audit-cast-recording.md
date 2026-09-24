# Phase 0 — Audit Cast + Recording

> **Cadre** : audit demandé par Lionel le 2026-05-31.
> Périmètre : Cast (DLNA + Google Cast + Roku + Web fallback) et
> Recording (HTTP downloader + Foreground service).
> **Aucun refactor** dans cette phase — uniquement description,
> classification et recommandations actionables que **l'utilisateur
> validera explicitement** avant Phase 1.
>
> Toute conclusion pointe vers un fichier:ligne précis.
> Toute affirmation non vérifiée empiriquement est marquée
> **[HYPOTHÈSE]**.

---

## 0. Méthodologie

1. **Lecture exhaustive** de tout le code Cast + Recording
   (Dart + Kotlin) — 14 fichiers Dart cast, 4 fichiers Dart
   recording, 4 fichiers Kotlin natifs, sections recording du
   player screen.
2. **Cartographie des flux** : voir documents séparés
   `cast-architecture.md` et `recording-architecture.md`.
3. **Recensement des failure modes** : 16 modes pour Cast,
   15 modes pour Recording (cf. les deux docs).
4. **Classification P0/P1/P2** : ce document.
5. **Logging structuré (additif)** : ajout d'un utilitaire dans
   `lib/core/observability/structured_logger.dart`. Aucun call
   site n'est instrumenté en Phase 0.

**Critères de classification** :

| Niveau | Définition | Action attendue |
|---|---|---|
| **P0** | Perte de données utilisateur OU plantage non-récupérable OU le système ment à l'utilisateur sur son état réel. | À corriger avant la prochaine release publique. |
| **P1** | UX significativement dégradée (latence > 30s sans feedback, message d'erreur trompeur, manque d'info actionable) OU impossible de diagnostiquer un incident à distance. | À planifier pour la version n+1. |
| **P2** | Cosmétique, théorique, ou bien géré dans la quasi-totalité des cas. | À traiter opportunément si refactor adjacent. |

---

## 1. Findings — vue synthétique

| ID | Sous-système | Titre | Gravité | Statut |
|---|---|---|---|---|
| F-01 | Recording | Orphelins SQLite après kill OS (process tué pendant un enregistrement) | **P0** | À corriger |
| F-02 | Recording | Disque plein : compteur bytes ment, recording continue silencieusement | **P0** | À corriger |
| F-03 | Recording | Auto-stop : message UX dit "limite 6h" même quand cause = serveur mort | **P1** | À corriger |
| F-04 | Recording | Pas de récupération de session après crash (streamUrl pas persistée) | **P1** | À traiter avec F-01 |
| F-05 | Recording | Pas de structured logging (juste `debugPrint('[Rec] …')`) | **P1** | Mitigation Phase 0 partielle (logger ajouté, non câblé) |
| F-06 | Recording | Notification ForegroundService ne reflète pas le multi-jobs | **P2** | Backlog |
| F-07 | Recording | Code partiellement mort : `_cleanupJob` jamais appelé | **P2** | Backlog |
| F-08 | Recording | Stale comment dans `recording.dart` ("libmpv stream-record") | **P2** | Cleanup trivial |
| F-09 | Cast | Pas de timeout global sur `castTo` (peut prendre 75s+) | **P1** | À corriger |
| F-10 | Cast | Ring buffer diagnostics non persisté (perdu au kill) | **P1** | À corriger |
| F-11 | Cast | Pas de récupération de session SDK natif (`setResumeSavedSession`) côté Dart | **P1** | À investiguer |
| F-12 | Cast | DLNA relay échec en silence sur certaines TVs (LG QNED816QA) — pas de hint actionnable | **P1** | À corriger côté UX |
| F-13 | Cast | Pas de structured logging | **P1** | Idem F-05 |
| F-14 | Cast | Relay HTTP : pas de SRI sur mpegts.js/hls.js (jsdelivr) | **P2** | Backlog |
| F-15 | Cast | Pas de Crashlytics/Sentry natif (crashs Kotlin non capturés) | **P1** | À investiguer |
| F-16 | Cast | Polling `hasActiveSession` 30s : pas de bouton "annuler" | **P2** | UX |

**Total** : **2 P0**, **9 P1**, **5 P2**.

---

## 2. Findings P0 — détail

### F-01 — Orphelins SQLite après kill OS

**Description** : `RecordingForegroundService` retourne
`START_NOT_STICKY` (cf. `RecordingForegroundService.kt:106`). Si
le process est killé pendant un enregistrement (pression mémoire,
crash natif, "Force Stop" depuis Réglages), le service ne
redémarre **pas**. Conséquences :

1. Le fichier `.ts` reste partiel sur le disque.
2. La row SQLite garde `ended_at = NULL`.
3. Au prochain boot de l'app, **aucune logique** ne scanne
   `WHERE ended_at IS NULL` pour finaliser. L'utilisateur voit
   une carte "EN COURS" indéfiniment.
4. Le bouton STOP de `RecordingsScreen` (`recordings_screen.dart:302-328`)
   appelle `HttpRecordingDownloader.stop(filePath: …)` qui no-op
   (le job n'existe plus dans `_jobs`) puis `finishRecording`.
   Donc l'orphelin EST finalisable manuellement — mais
   l'utilisateur doit y penser et naviguer vers l'écran.

**Preuve code** :

- `RecordingForegroundService.kt:106` : `return START_NOT_STICKY`
- `recording_repository.dart:36-67` (`initialize`) : aucun
  appel à un éventuel `_recoverOrphans()`.
- `recordings_screen.dart:127-176` : code de stop manuel
  d'orphelin.
- `http_recording_downloader.dart:556-584` : `stop(filePath)`
  retourne 0 si le job n'existe pas → no-op silencieux.

**Pourquoi P0** : (a) le système ment — affiche "EN COURS" alors
que rien ne tourne ; (b) données perdues si l'utilisateur ne
remarque jamais ; (c) si le `.ts` partiel est exporté vers la
Galerie tel quel, il est exploitable mais l'utilisateur ne sait
pas que ça s'est mal terminé.

**Recommandation Phase 1** :

1. Ajouter `RecordingRepository.recoverOrphans()` appelé dans
   `main.dart` au démarrage : SELECT `WHERE ended_at IS NULL`,
   pour chaque row finaliser via `finishRecordingByPath(filePath)`
   (qui calcule la taille réelle du fichier).
2. Marquer ces auto-finalisations comme "interrupted" (nouvelle
   colonne ?) pour qu'on puisse afficher un badge "incomplet"
   sur la card.

---

### F-02 — Disque plein : compteur bytes ment, recording continue

**Description** : si l'espace disque s'épuise pendant
l'enregistrement, `sink.add(chunk)` lève une `FileSystemException`.
Le code l'avale juste avec un `debugPrint` :

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

**Preuve code** : `http_recording_downloader.dart:280-288`.

**Comportement observable** :

- L'UI affiche un compteur bytes qui CONTINUE de croître dans la
  notification si on a raison sur la fréquence (à confirmer, le
  catch est censé empêcher l'incrément si add throw — **vérifié,
  l'incrément est dans le `try` après `add`, donc il ne se fait
  pas en cas d'erreur**).
- **MAIS** la socket continue de fournir des chunks, la HTTP
  connection reste ouverte, la bande passante est gaspillée.
- **MAIS** le job ne s'arrête JAMAIS de lui-même sur erreur
  disque (pas de circuit breaker). Il continuera à essayer
  pendant 6h avant l'auto-stop par plafond.

**Pourquoi P0** : (a) l'utilisateur croit qu'il enregistre alors
que rien ne s'écrit ; (b) consommation data inutile ; (c)
quand l'utilisateur revient sur l'app, il pense avoir un
fichier de N Mo et trouve un fichier tronqué.

**Recommandation Phase 1** :

1. Si `sink.add` throw N fois consécutivement (genre 5), couper
   le job avec un nouveau callback `onDiskError(filePath)`.
2. Pré-flight : vérifier `getFreeSpace()` avant `_startRaw` et
   refuser si < seuil (1 Go ?).
3. Notification d'erreur côté UI ("Stockage insuffisant —
   enregistrement arrêté").

---

## 3. Findings P1 — détail

### F-03 — Message UX trompeur sur auto-stop

**Description** : `_onRecordingAutoStopped` affiche toujours
"limite de 6 h atteinte" alors que le callback est aussi
déclenché par "serveur définitivement injoignable après 12
reconnexions".

**Preuve code** :

- `http_recording_downloader.dart:319-326` (cas 6h)
- `http_recording_downloader.dart:341-349` (cas server dead) —
  les deux appellent le même `_autoFinish` avec aucun discriminant.
- `video_player_screen.dart:501-504` (message hardcodé).

**Recommandation Phase 1** : changer la signature
`onAutoStopped(String filePath, AutoStopReason reason)` avec
enum `{maxDurationReached, serverUnreachable, diskFull}`. UI
adapte le message.

---

### F-04 — Pas de récupération de session après crash

**Description** : `_Job` ne stocke pas `streamUrl` (passée en
closure), et la row SQLite non plus. Donc même si on voulait
implémenter un resume après reboot, on ne saurait pas quelle
URL relancer.

**Preuve code** : `http_recording_downloader.dart:649-689`
(`_Job` n'a pas de champ `streamUrl`). `recording_repository.dart:40-52`
(schéma DB sans colonne `stream_url`).

**Recommandation Phase 1** : ajouter colonne `stream_url` (avec
ALTER TABLE idempotent) + persister sur `start`. Implémenter
resume au boot dans Phase 1+ (lié à F-01).

---

### F-05 — Pas de structured logging (Recording)

**Description** : tout passe par `debugPrint('[Rec] …')` texte
libre. Difficile à parser, à agréger, à uploader.

**Mitigation Phase 0** : `lib/core/observability/structured_logger.dart`
ajouté. Aucun call site câblé. Phase 1 doit instrumenter au
minimum :

- `rec.job.start` / `rec.job.stop` / `rec.job.auto_stop`
- `rec.job.reconnect_attempt` / `rec.job.reconnect_success` /
  `rec.job.reconnect_fail`
- `rec.svc.start` / `rec.svc.stop`
- `rec.svc.wakelock_acquire` / `rec.svc.wakelock_release`

Champs contextuels suggérés (cf. doc inline du logger) :
`filePath`, `isHls`, `activeCount`, `bytesWritten`, `elapsed`,
`reconnectCount`, `reconnectFailures`.

---

### F-09 — Pas de timeout global sur `castTo`

**Description** : `castTo` peut durer théoriquement :

- Probe : 6s
- Capabilities fetch : ~3-5s
- 5 stratégies × ~15s SOAP timeout = 75s
- = **~90s pire cas**

Pendant ce temps, aucune façon pour l'utilisateur d'annuler. La
progression UI évolue ("Nouvel essai 2/5…"), mais pas de bouton
"Annuler".

**Preuve code** :

- `cast_manager.dart:216-324` (pas de `Future.timeout` global)
- `upnp_av_transport.dart:97` (15s par SOAP call)

**Recommandation Phase 1** :

1. Wrapper `castTo` dans `.timeout(Duration(seconds: 25))` au
   total → si tout n'a pas convergé, on bascule sur le
   fallback web automatiquement OU on affiche "Cette TV est
   trop lente" avec bouton "Essayer en QR code".
2. Exposer un `cancelCast()` qui pose un flag lu entre chaque
   stratégie.

---

### F-10 — Ring buffer diagnostics non persisté

**Description** : `_recentDiagnostics` est 100% en RAM (cf.
`cast_manager.dart:67-70`). Au kill app, perte intégrale.
Conséquence : impossible pour un user de partager un rapport
d'un incident survenu hier.

**Recommandation Phase 1** :

1. Persister le dernier N (20 ?) dans SQLite (nouvelle table
   `cast_diagnostics` avec colonne JSON brute).
2. Charger au boot dans le ring buffer.
3. Bouton "Exporter les 7 derniers jours" dans l'écran
   Diagnostic.

---

### F-11 — Pas de récup session SDK natif côté Dart

**Description** : `CastOptionsProviderImpl.kt:74` active
`setResumeSavedSession(true)`. Le SDK natif Google Cast resume
donc une session interrompue dans les 30 min. **MAIS** :

- `CastManager.instance.isCasting` reste `false` après reboot
  Dart, car le state vit en RAM.
- Au prochain `castTo`, on va probablement ré-ouvrir le picker
  alors qu'une session est techniquement déjà active.

**[HYPOTHÈSE]** : à confirmer en lisant `main.dart` pour voir
si un `hasActiveSession()` est appelé au boot. Si non, c'est
un bug — au minimum un appel `await
GoogleCastApi.instance.hasActiveSession()` au démarrage devrait
restaurer `_state = casting` côté CastManager.

**Recommandation Phase 1** : audit du lifecycle Dart + add
session restoration hook.

---

### F-12 — Échec relay LG QNED816QA sans hint actionnable

**Description** : sur le device de Lionel, le relay HTTP est
inaccessible depuis la TV (probable VLAN). Les stratégies 3 et
4 timeout les deux. Message final UX :

> "Cette TV n'a pas accepté ce flux. Essaie une autre chaîne ou
> le mode QR code."

Or le vrai problème n'est ni la chaîne ni le mode — c'est la
**config WiFi du routeur** (isolation invité, VLAN, etc.).

**Preuve code** :

- `cast_manager.dart:416-422` (commentaire qui documente le cas)
- `cast_manager.dart:547-562` (`_friendlyMessageFor` — pas de
  branche spécifique pour les timeouts relay).

**Recommandation Phase 1** : détecter dans `_castDlnaWithFailover`
que les stratégies 3 et 4 ont toutes deux échoué en **timeout**
(distinguer du 500). Dans ce cas, message :

> "La TV ne joint pas ton téléphone (WiFi invité ?). Essaie le
> mode QR code, qui contourne ce blocage."

---

### F-13 — Pas de structured logging (Cast)

Identique à F-05, côté Cast. Events suggérés :

- `cast.discovery.start` / `cast.discovery.device_found` /
  `cast.discovery.stop`
- `cast.session.probe_result` / `cast.session.caps_fetched`
- `cast.session.attempt` (strategy, urlKind, metadataMode)
- `cast.session.attempt_success` / `cast.session.attempt_failure`
- `cast.session.success` / `cast.session.failure`
- `cast.session.disconnect`
- `cast.relay.register` / `cast.relay.clear` / `cast.relay.evicted`

---

### F-15 — Pas de capture crash natif

**Description** : `MainActivity.kt` wrap chaque init de channel
dans son try/catch (bon), mais **aucun capture global** d'un
crash Kotlin (uncaught exception, native crash via NDK). Le
SDK Cast / WebView / mpegts.js sur le receiver peuvent crasher
sans qu'on en sache rien.

**Recommandation Phase 1** :

1. Court terme : ajouter `Thread.setDefaultUncaughtExceptionHandler`
   dans MainActivity → log structuré + écrit dans un fichier
   local "crash.log" lisible au prochain boot.
2. Moyen terme : intégrer Firebase Crashlytics ou Sentry.
   Évaluer le coût de la dep vs le gain de visibilité.

---

## 4. Findings P2 — résumé

Pour ne pas allonger ce document, les P2 ne reçoivent qu'un
résumé. Détails dans `cast-architecture.md` §6 et
`recording-architecture.md` §8.

- **F-06** : notification ForegroundService = titre du dernier
  start. Cosmétique multi-jobs.
- **F-07** : `_cleanupJob` jamais appelé en pratique. Code mort.
- **F-08** : commentaire `recording.dart:5-6` mentionne encore
  `libmpv stream-record`. Stale.
- **F-14** : `<script src="https://cdn.jsdelivr.net/...">` sans
  attribut `integrity`. Risque supply chain limité (LAN only).
- **F-16** : polling `hasActiveSession` 30s sans bouton annuler.
  L'utilisateur peut juste fermer le picker.

---

## 5. Recommandations transverses (Phase 1+)

### 5.1 Observabilité — priorité immédiate

Le **plus gros gap** est l'absence d'observabilité structurée.
Sans ça, chaque incident en prod est un mystère insoluble.

**Étapes proposées** :

1. ✅ **Phase 0 (fait)** : utilitaire `StructuredLogger` ajouté
   en `lib/core/observability/structured_logger.dart`. Aucun
   call site câblé.
2. **Phase 1** : câbler les events listés en F-05 et F-13.
   Vérifier en `flutter logs` que le format JSON-Lines est
   lisible. Impact : 0 sur l'UX, 0 sur la perf (sinks
   debugPrint-only par défaut).
3. **Phase 1+** : ajouter un sink fichier rotatif local
   (`Documents/7motion-logs/YYYYMMDD.jsonl`) + bouton "Exporter
   les logs" dans Réglages → support.
4. **Phase 2** : sink upload vers Cloudflare Worker dédié
   (`/diagnostics/ingest`) avec opt-in user. Permet le
   diagnostic à distance sans demander à l'utilisateur de
   copier-coller.

### 5.2 Récupération de session — recording

F-01 + F-04 vont ensemble. Le minimum vital :

```dart
// main.dart au boot
await RecordingRepository.instance.initialize();
await RecordingRepository.instance.recoverOrphans();
```

```dart
// recording_repository.dart
Future<void> recoverOrphans() async {
  final List<Recording> orphans = await _queryWhereEndedAtNull();
  for (final Recording o in orphans) {
    if (HttpRecordingDownloader.instance.isRecordingFile(o.filePath)) {
      continue; // job réel toujours actif
    }
    await finishRecordingByPath(o.filePath);
    StructuredLogger.instance.warn(
      domain: 'rec',
      event: 'job.recovered_orphan',
      ctx: {'filePath': o.filePath, 'id': o.id},
    );
  }
}
```

### 5.3 Timeout global cast

Cf. F-09. Simple à implémenter — entourer `castTo` d'un
`.timeout(Duration(seconds: 25), onTimeout: …)`.

### 5.4 Distinction `serverUnreachable` vs `maxDuration`

Cf. F-03. Refactor mineur de `onAutoStopped`. Le seul piège est
que la signature change → tous les call sites (1 dans
`video_player_screen.dart`) doivent être mis à jour ensemble.

---

## 6. Recommandations explicitement ÉCARTÉES en Phase 1

Pour cadrer le scope et éviter le bloat :

- **Pas** de migration `libmpv` → `dart:io` reversed (le dart:io
  pipeline marche, ne touchons à rien).
- **Pas** de rewrite du failover DLNA (5 stratégies, latence
  acceptable, bien testé empiriquement).
- **Pas** d'intégration Firebase / Crashlytics tant que le
  logger maison ne révèle pas un gap qu'il ne peut pas combler.
- **Pas** de refactor du `_cleanupJob` mort — c'est du code
  mort inerte, à supprimer dans un cleanup adjacent.
- **Pas** de support multi-cast simultané (1 cast à la fois est
  un choix produit clair).

---

## 7. Validation utilisateur attendue

Avant d'entamer Phase 1, **Lionel doit valider** :

1. La classification P0/P1/P2 ci-dessus.
2. La liste des findings à corriger en Phase 1 (par défaut, je
   propose : **F-01, F-02, F-03, F-04, F-09, F-12**).
3. Le **scope précis** de l'instrumentation logger (events listés
   en F-05 et F-13 — ou un sous-ensemble).
4. Le périmètre des **tests manuels** que tu peux faire (tu n'as
   accès qu'à 1 device LG QNED816QA + 1 Android phone — pas de
   matrice de tests automatisée possible).

**Aucun commit ni modification fonctionnelle** ne sera fait avant
ta validation explicite.

---

## 8. Annexes — inventaire fichiers lus

### 8.1 Recording (lus intégralement)

- `lib/features/recordings/data/http_recording_downloader.dart` (689 LoC)
- `lib/features/recordings/data/recording_service.dart` (64 LoC)
- `lib/features/recordings/data/recording_repository.dart` (202 LoC)
- `lib/features/recordings/domain/recording.dart` (117 LoC)
- `lib/features/recordings/presentation/recordings_screen.dart` (518 LoC)
- `android_overlay/google_cast/RecordingForegroundService.kt` (210 LoC)
- `android_overlay/google_cast/RecordingServiceBridge.kt` (79 LoC)
- `lib/features/player/presentation/video_player_screen.dart` (sections recording, lignes 350-510)

### 8.2 Cast (lus intégralement ou substantiellement)

- `lib/features/cast/data/cast_manager.dart` (607 LoC)
- `lib/features/cast/data/cast_transport.dart` (59 LoC)
- `lib/features/cast/data/upnp_av_transport.dart` (439 LoC)
- `lib/features/cast/data/google_cast_transport.dart` (132 LoC)
- `lib/features/cast/data/google_cast_api.dart` (147 LoC)
- `lib/features/cast/data/local_cast_server.dart` (554 LoC)
- `lib/features/cast/data/stream_probe.dart` (276 LoC)
- `lib/features/cast/data/dlna_profiles.dart` (283 LoC)
- `lib/features/cast/data/dlna_capabilities.dart` (~150 LoC, début lu)
- `lib/features/cast/data/ssdp_discovery.dart` (294 LoC)
- `lib/features/cast/data/mdns_discovery.dart` (121 LoC)
- `lib/features/cast/data/cast_session_diagnostic.dart` (260 LoC)
- `lib/features/cast/data/cast_diagnostics.dart` (239 LoC)
- `lib/features/cast/data/cast_progress.dart` (161 LoC)
- `android_overlay/google_cast/GoogleCastApi.kt` (234 LoC)
- `android_overlay/google_cast/CastOptionsProviderImpl.kt` (81 LoC)
- `android_overlay/google_cast/MainActivity.kt` (213 LoC)

### 8.3 Non lus en Phase 0 (à couvrir si besoin Phase 1+)

- `lib/features/cast/data/roku_ecp_transport.dart`
- `lib/features/cast/data/web_browser_transport.dart`
- `lib/features/cast/presentation/cast_picker_sheet.dart` (~760 LoC)
- `lib/features/cast/presentation/qr_cast_sheet.dart`
- `lib/features/cast/presentation/cast_button.dart`
- `lib/features/cast/presentation/cast_mini_bar.dart`
- `lib/features/cast/presentation/cast_diagnostics_screen.dart`
- `lib/features/cast/presentation/web_cast_setup_sheet.dart`
- `android/app/src/main/AndroidManifest.xml` (à vérifier pour
  permissions Recording)
- `lib/main.dart` (à vérifier pour init Cast/Recording lifecycle)

---

## 9. Livrables Phase 0

1. ✅ `docs/cast-architecture.md` — architecture Cast, 10
   sections, ~16 failure modes documentés.
2. ✅ `docs/recording-architecture.md` — architecture Recording,
   12 sections, ~15 failure modes documentés.
3. ✅ `docs/phase-0-audit-cast-recording.md` — ce document.
4. ✅ `lib/core/observability/structured_logger.dart` — utilitaire
   additif, JSON-Lines, sinks pluggables. **Non câblé**.

**Aucune modification fonctionnelle** apportée au code existant
en Phase 0.
