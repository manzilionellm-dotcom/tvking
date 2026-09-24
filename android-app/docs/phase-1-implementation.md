# Phase 1 — Implementation notes

> Donne suite a l'audit Phase 0 (`docs/phase-0-audit-cast-recording.md`).
> Periode : 2026-05-31.
> Scope : 2 P0 (F-01, F-02) + 4 P1 (F-03, F-04, F-09, F-12)
> explicitement autorises par l'utilisateur.

---

## 1. Findings traites

| ID | Sujet | Niveau | Fichiers modifies | Risque reduit |
|---|---|---|---|---|
| F-01 | Recover SQLite orphans apres OS kill | **P0** | `recording_repository.dart`, `main.dart` | L'UI ne ment plus apres kill OS — les fiches `ended_at IS NULL` sont finalisees au boot. |
| F-02 | Stop recording safely on disk-full / sink failure | **P0** | `http_recording_downloader.dart` | Le downloader coupe apres 5 echecs `sink.add` consecutifs au lieu de gaspiller indefiniment data + batterie. |
| F-03 | Auto-stop reason (6h vs server vs disk) | P1 | `http_recording_downloader.dart`, `video_player_screen.dart`, `recording.dart`, `recording_repository.dart` | Message UX precis. Plus de "limite 6h" trompeur quand cause = serveur ou disque. |
| F-04 | Persist streamUrl | P1 | `recording.dart`, `recording_repository.dart`, `video_player_screen.dart`, `http_recording_downloader.dart` | Pre-requis pour resume Phase 2+. Aussi : diagnostic / support — on saura quelle URL retester. |
| F-09 | Global timeout on castTo | P1 | `cast_manager.dart` | L'utilisateur ne reste plus 60-90s devant un picker bloque ; au pire 25s puis hint QR. |
| F-12 | Relay-unreachable UX hint | P1 | `cast_manager.dart` | Sur les TVs VLAN/AP-isolees (cas LG QNED816QA observe), le message pointe vers la vraie cause (WiFi invite) au lieu de "essaie une autre chaine". |
| F-08 | Stale comment "libmpv stream-record" | P2 | `recording_repository.dart` (header) | Cosmetique — fait au passage. |

---

## 2. Fichiers modifies

```
lib/
├── main.dart                                                     (+8 lignes)
├── core/
│   └── observability/
│       └── structured_logger.dart                                (deja livre Phase 0, non touche)
├── features/
│   ├── cast/
│   │   └── data/
│   │       └── cast_manager.dart                                 (+98 lignes — F-09, F-12 + logs)
│   ├── player/
│   │   └── presentation/
│   │       └── video_player_screen.dart                          (+25 lignes — appels avec reason)
│   └── recordings/
│       ├── data/
│       │   ├── http_recording_downloader.dart                    (+120 lignes — enum, F-02, F-03, logs)
│       │   └── recording_repository.dart                         (+85 lignes — migrations, recoverOrphans)
│       └── domain/
│           └── recording.dart                                    (+25 lignes — champs streamUrl + autoStopReason)

test/                                                             (NOUVEAU dossier)
├── core/observability/
│   └── structured_logger_test.dart                               (NOUVEAU — 5 tests)
└── features/
    ├── cast/data/
    │   └── relay_failure_detection_test.dart                     (NOUVEAU — 6 tests)
    └── recordings/data/
        └── auto_stop_reason_test.dart                            (NOUVEAU — 3 tests)

docs/
└── phase-1-implementation.md                                     (CE FICHIER)
```

**Total** : 7 fichiers source touches + 3 fichiers de tests + 1 doc = **11 fichiers**.
Aucune dependance externe ajoutee. Aucun refactor structurel.

---

## 3. Tests ajoutes

Pas de SQLite ni d'IO dans les tests — tout est pur logique testable
sur le Dart VM sans extension native.

### 3.1 `structured_logger_test.dart` (5 tests)

- Format JSON-Lines : champs canoniques (`ts`, `lvl`, `domain`, `event`)
  + ISO 8601 UTC + serialisation de `ctx`.
- Omission de `ctx` quand vide (compacite logs).
- Couverture des 3 niveaux `info`/`warn`/`error`.
- Fan-out a plusieurs sinks dans l'ordre d'ajout.
- Resilience : un sink defaillant n'empeche pas les autres de recevoir
  l'evenement.

### 3.2 `auto_stop_reason_test.dart` (3 tests)

- Verrouille les `.name` des 3 valeurs de `AutoStopReason` — ces noms
  sont **persistes en SQLite** (colonne `auto_stop_reason`), un rename
  silencieux casse la lecture des fiches existantes.
- Verifie qu'on n'a que 3 valeurs (alarme si on en ajoute une, pour
  forcer la mise a jour du `_autoStopMessage(...)` UX).
- Verrouille `kMaxRecordingDuration = 6h` (changement de cette duree
  impacte la communication utilisateur).

### 3.3 `relay_failure_detection_test.dart` (6 tests)

- 6 cas couvrant la regle "bothRelayStrategiesFailed" : aucune
  tentative, une seule strategie relay testee, succes d'une des relay,
  echec des deux, cas edge avec une directe reussie.

### 3.4 Couverture des transitions critiques

| Transition | Test ? | Note |
|---|---|---|
| Logger emission + fan-out | Oui | `structured_logger_test.dart` |
| AutoStopReason persistance | Oui | `auto_stop_reason_test.dart` (verrouille les noms) |
| Decision UX cast WiFi-isolation | Oui | `relay_failure_detection_test.dart` |
| `recoverOrphans()` finalise les fiches `ended_at IS NULL` | **Non** | Necessite mock SQLite (`sqflite_common_ffi`) — dep additionnelle hors scope Phase 1. **Test manuel device requis.** |
| `castTo` timeout fires apres 25s | **Non** | Necessite un mock du transport DLNA + un `fakeAsync`. Reportable Phase 2. **Test manuel device requis.** |
| Sink-error counter declenche `diskError` au seuil | **Non** | Necessite mock filesystem. **Test manuel device requis.** |

---

## 4. Notes de validation (sans device, sans IDE)

Aucun toolchain Flutter/Dart disponible dans cet environnement — j'ai
fait l'audit par lecture + verification manuelle :

1. Tous les `_autoFinish(...)` ont le nouveau second arg `AutoStopReason`
   (4 sites, verifies via grep).
2. Tous les callers de `onAutoStopped` (interne + externe) utilisent la
   nouvelle signature `(filePath, reason)` (3 sites callback + 1 site
   wire dans `_startRaw`/`_startHls`).
3. Le seul call site externe de `RecordingRepository.startRecording`
   (`video_player_screen.dart:424`) passe maintenant `streamUrl`.
4. Les deux callers externes de `CastManager.castTo`
   (`cast_picker_sheet.dart:122` + `cast_diagnostics.dart:129`) catchent
   deja `on Exception` — la nouvelle `TimeoutException` rethrown en
   `Exception` y est gobee proprement.
5. `recoverOrphans()` est wire APRES `initialize()` dans `main.dart` via
   `.then(...)`, donc l'ordre est garanti.
6. Les 3 colonnes ALTER TABLE (`channel_logo_url` historique +
   `stream_url` + `auto_stop_reason` nouveaux) suivent le meme pattern
   try/catch `DatabaseException` idempotent.

Risques residuels listes section 6.

---

## 5. Instructions de test device

### 5.1 F-01 — Orphan recovery (P0)

Cas a reproduire : "Mes enregistrements" affiche "EN COURS" alors qu'il
n'y a aucun enregistrement actif.

1. Lance une chaine, tape REC.
2. Verifie le badge "REC" actif + la card "EN COURS" dans Mes
   enregistrements.
3. Va dans Reglages > Apps > 7 MOTION > **Forcer l'arret** (simulate kill OS).
4. Rouvre l'app.
5. **Attendu** : la card precedemment "EN COURS" est maintenant
   finalisee (duree affichee, taille reelle du fichier). Plus de
   badge "EN COURS" mensonger.
6. Dans `adb logcat | grep StructuredLogger`, tu dois voir une ligne
   JSON `event:"job.recovered_orphan"`.

### 5.2 F-02 — Disk-full safe stop (P0)

Cas a reproduire : remplir le stockage pendant un enregistrement.

Option A — facile : remplir le stockage AVANT de demarrer un long
enregistrement, puis lancer un recording 4K, observer apres ~30s.

Option B — sans remplir : tu peux temporairement faire en sorte que le
sink throw en redirigeant le filePath vers un repertoire en lecture
seule. Methode propre : changer `getRecordingsDir()` pour pointer vers
`/system/` (read-only). Mais c'est invasif.

**Attendu en cas d'erreur disque** :
1. Au bout de 5 chunks consecutifs en erreur, l'enregistrement
   s'arrete tout seul.
2. Toast : "Enregistrement arrêté : stockage insuffisant ou écriture
   impossible. Vérifie l'espace libre."
3. Logcat : 5 events `job.disk_error` (warn) puis 1 event `job.auto_stop`
   avec `reason: "diskError"`.
4. La fiche en base a `auto_stop_reason = 'diskError'`.

### 5.3 F-03 — Auto-stop reason UX

Cas serveur mort :
1. Lance un enregistrement.
2. Coupe ton internet (mode avion) pour > 12 tentatives de reconnect
   (chaque tentative attend 2-16s, donc ~3-5 min total pour atteindre
   12 fails).
3. **Attendu** : toast "Enregistrement arrêté : ton serveur IPTV ne
   répond plus." (et NON pas "limite de 6 h atteinte").

Cas plafond 6h : difficilement testable sans patcher `kMaxRecordingDuration`.
Pour le tester rapidement, changer temporairement la constante a
`Duration(minutes: 2)`, lancer un recording, attendre 2 minutes.

### 5.4 F-04 — streamUrl persiste

Apres un recording :
```
adb shell run-as com.manzilionellm.tvking \
  sqlite3 databases/<your-db>.db \
  "SELECT id, channel_name, stream_url FROM recordings ORDER BY id DESC LIMIT 1;"
```
**Attendu** : la colonne `stream_url` contient bien l'URL IPTV
(token Xtream visible — c'est normal en local).

### 5.5 F-09 — Cast global timeout

1. Caste vers ta TV LG QNED816QA en ne la sortant PAS de standby (la
   force a etre lente sur le SOAP).
2. **Attendu** : au bout de 25s max, message "La TV met trop de temps
   à répondre. Essaie le mode QR code." Plus jamais 60-90s d'attente.
3. Logcat : event `cast.session.global_timeout` (warn).

### 5.6 F-12 — Relay-unreachable hint

1. Si possible, mets ton telephone sur le WiFi invite Freebox/Livebox
   (qui isole les clients entre eux), TV LG sur le WiFi principal.
2. Caste depuis le tel.
3. Les strategies direct (0/1/2) vont peut-etre marcher selon ta TV —
   pour forcer le test du hint, deconnecter la TV d'internet
   apres la decouverte ne marche pas (il faut que le SOAP arrive).
4. **Attendu** dans le cas LG QNED816QA habituel (les 2 relay
   echouent) : "Ta TV ne joint pas le téléphone (WiFi invité ou
   isolation AP ?). Essaie le mode QR code, il contourne ce blocage."
5. Logcat : event `cast.session.relay_unreachable` (warn).

---

## 6. Risques restants (Phase 2+ candidates)

| Risque | Severite | Commentaire |
|---|---|---|
| `recoverOrphans()` non testable sans mock SQLite | Faible | Verification manuelle device suffit en Phase 1 ; si le risque grandit, ajouter `sqflite_common_ffi` en dev_dep Phase 2. |
| `.timeout()` n'interrompt pas vraiment le Future inner | Faible-Moyen | Documente inline cast_manager.dart:255-263. SOAPs en cours continuent leur course (timeouts 15s x N), exception asynchrone unhandled possible. Phase 2 : annulation cooperative via flag verifie entre chaque strategie. |
| Pas de quota / pre-flight `getFreeSpace()` | Faible | F-02 corrige le REACTIVE ("on s'arrete quand ca casse"). Le PROACTIVE ("refuser de demarrer si < 1 Go libre") est P2 et hors scope. |
| Pas de UI badge "interrupted" sur les fiches recuperees | Cosmetique | La donnee est en base (`auto_stop_reason = 'interruptedByOsKill'`). Phase 2 peut ajouter un badge orange "incomplet" dans la card. |
| Notification ForegroundService toujours unique | Cosmetique | F-06 P2 du Phase 0, pas dans le scope autorise. |
| `_cleanupJob` toujours present comme code mort | Cosmetique | F-07 P2 du Phase 0, pas dans le scope. |
| Diagnostics cast toujours en RAM (perdus au kill) | Moyen | F-10 P1 du Phase 0, **non autorise** Phase 1. A reporter Phase 2 si vous voulez du support distance. |
| Crashs Kotlin natifs non captures | Moyen | F-15 P1 du Phase 0, non autorise Phase 1. |
| Resume apres kill OS pas implemente | Moyen-Eleve | F-04 prepare le terrain (stream_url persiste) mais le **resume effectif** demande Phase 2 (relancer downloader + service au boot, decider si on append au .ts partiel ou si on cree un nouveau). |

---

## 7. Hypotheses non verifiees [HYPOTHESE]

Marquees explicitement dans le code et ici :

1. **[HYPOTHESE]** Le wrapper `.timeout()` de `castTo` ne fuit pas
   gravement de memoire malgre l'absence de vraie annulation. Justifie
   par le fait que les HttpClient internes se ferment via leur propre
   `connectionTimeout` / `idleTimeout`. A confirmer si jamais des
   logs Sentry/Crashlytics remontent des leaks Dart isolate.
2. **[HYPOTHESE]** Le seuil `_kMaxConsecutiveSinkErrors = 5` est un
   compromis raisonnable. Calibre sans donnees empiriques — a ajuster
   selon retours device (peut-etre 3 suffisent, peut-etre 10 evitent
   des faux positifs sur SD card lente).
3. **[HYPOTHESE]** L'OS Android tue rarement le process durant un
   enregistrement quand le ForegroundService est actif (c'est tout
   l'interet de ce service). Donc F-01 traite un cas rare mais reel
   (force-stop manuel, low-memory extreme). Pas de metrique pour
   quantifier la frequence.
4. **[HYPOTHESE]** Le pattern "les 2 strategies relay ont echoue ⇒
   WiFi isolation" est le cas dominant. Il existe d'autres causes
   possibles (la TV refuse les 2 par bug firmware), mais le message
   UX "essaie le QR code" reste actionnable dans tous les cas.

---

## 8. Ce qui n'est PAS dans Phase 1

Confirme par scope utilisateur :

- F-05, F-13 (structured logging — instrument plus de call sites).
  Phase 1 instrument SEULEMENT les transitions critiques liees aux
  fixes (recording start/stop/auto_stop/disk_error/reconnect, cast
  success/failure/timeout/relay_unreachable). Pas de coverage
  exhaustive.
- F-06, F-07, F-08 (P2 — cosmetique). F-08 fait au passage car trivial,
  les autres reportes.
- F-10, F-11, F-14, F-15, F-16 (Phase 2+).
- Pas de migration `libmpv` → autre lib.
- Pas de refactor du `_cleanupJob` mort.
- Pas de nouvelle UI (badge interrupted, bouton cancel cast, etc.).

---

## 9. Prochaine session

Quand tu auras teste sur device, fais-moi un retour bref de chaque
case 5.1 a 5.6. Si OK : on planifie Phase 2 (probablement F-10
diagnostics persistance + F-11 session restoration cast). Si KO :
on corrige avant.
