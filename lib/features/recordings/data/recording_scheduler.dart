// =========================================================
//  recording_scheduler.dart — Planificateur d'enregistrements (DVR)
// =========================================================
//  C'est le « cerveau » de l'enregistrement programmé :
//
//    schedule()  : depuis le guide, « enregistre cette émission ». Refuse
//                  un créneau qui chevauche un autre enregistrement (une
//                  ligne IPTV = une connexion), réserve le fichier, pose
//                  les alarmes NATIVES (Android) ou compte sur le tick
//                  Dart (autres plateformes).
//    cancel()    : retire la programmation, arrête la capture si en cours.
//    tick()      : toutes les 30 s et au démarrage — RÉCONCILIE l'état :
//                  lit ce que le natif a fait pendant que l'app dormait
//                  (capture faite → fiche « Mes enregistrements »), lance
//                  la capture Dart quand il n'y a pas de natif ou que
//                  l'alarme n'a pas pris, clôt à l'heure, marque « manqué ».
//
//  Le choix de l'action pour une entrée est une fonction PURE
//  ([SchedulePlanner.decide]) : testable sans base, sans natif, sans horloge.
//
//  Marge de sécurité : si le natif n'a toujours rien démarré 3 min après
//  le début effectif, le Dart (s'il tourne) prend le relais — et retire
//  les alarmes natives de ce créneau pour éviter un double départ.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/i18n/l10n_now.dart';
import '../../../core/observability/structured_logger.dart';
import '../../channels/domain/channel.dart';
import '../../epg/domain/epg_program.dart';
import '../../player/data/local_stream_relay.dart';
import '../domain/recording.dart';
import '../domain/scheduled_recording.dart';
import 'http_recording_downloader.dart';
import 'native_recording_scheduler.dart';
import 'recording_repository.dart';
import 'recording_storage_policy.dart';
import 'scheduled_recording_repository.dart';

/// Résultat d'une demande de programmation.
enum ScheduleResult {
  ok,

  /// Le créneau chevauche un autre enregistrement (autre chaîne).
  conflict,

  /// L'émission est déjà terminée.
  tooLate,

  /// Erreur technique (fichier, base…).
  failed,
}

/// Action à mener sur une entrée lors d'un tick.
enum ScheduleAction {
  none,

  /// Démarrer la capture Dart (pas de natif, ou natif muet).
  startDart,

  /// Arrêter la capture Dart (heure de fin atteinte).
  stopDart,

  /// Le natif capte : refléter « en cours » (créer la fiche si besoin).
  reflectNativeRecording,

  /// Le natif a fini : finaliser la fiche, marquer terminé.
  reflectNativeDone,

  /// Le natif a échoué : marquer échec.
  reflectNativeFailed,

  /// Créneau passé sans capture.
  markMissed,
}

/// Logique PURE de décision (une entrée, un instant, l'état natif).
abstract final class SchedulePlanner {
  /// Délai après le début effectif au-delà duquel un natif toujours
  /// « planned » est considéré comme n'ayant pas pris → repli Dart.
  static const Duration nativeGrace = Duration(minutes: 3);

  static ScheduleAction decide({
    required ScheduledRecording entry,
    required NativeRecordingStatus? native,
    required bool nativeSupported,
    required bool dartJobRunning,
    required int nowMs,
  }) {
    if (!entry.isActive) return ScheduleAction.none;
    final int start = entry.effectiveStartMs;
    final int stop = entry.effectiveStopMs;

    // 1) Le Dart capte déjà → on ne regarde que l'heure de fin.
    if (dartJobRunning) {
      return nowMs >= stop ? ScheduleAction.stopDart : ScheduleAction.none;
    }

    // 2) Le natif a quelque chose à dire.
    if (native != null) {
      if (native.isDone) return ScheduleAction.reflectNativeDone;
      if (native.isFailed) {
        // Échec natif AVANT la fin du créneau : le Dart peut rattraper.
        if (nowMs < stop && nowMs >= start) return ScheduleAction.startDart;
        return ScheduleAction.reflectNativeFailed;
      }
      if (native.isRecording) return ScheduleAction.reflectNativeRecording;
    }

    // 3) Rien ne capte encore.
    if (nowMs >= stop) {
      // Créneau passé. Une entrée « recording » sans job ni natif = capture
      // interrompue (app tuée) → on la clôt comme terminée si un fichier
      // existe, sinon manquée. Ici on ne sait pas si le fichier existe :
      // l'appelant tranchera (markMissed vérifie le fichier).
      return ScheduleAction.markMissed;
    }
    if (nowMs < start) return ScheduleAction.none;

    // Dans le créneau, personne ne capte.
    if (!nativeSupported) return ScheduleAction.startDart;
    // Natif présent mais muet : on lui laisse [nativeGrace] (alarme
    // inexacte, service qui démarre), puis le Dart prend la main.
    if (nowMs - start >= nativeGrace.inMilliseconds) {
      return ScheduleAction.startDart;
    }
    return ScheduleAction.none;
  }
}

class RecordingScheduler extends ChangeNotifier {
  RecordingScheduler._();
  static final RecordingScheduler instance = RecordingScheduler._();

  static const Duration tickEvery = Duration(seconds: 30);

  final ScheduledRecordingRepository _repo =
      ScheduledRecordingRepository.instance;
  final NativeRecordingScheduler _native = NativeRecordingScheduler.instance;

  Timer? _timer;
  bool _ticking = false;
  bool _started = false;

  /// Jobs Dart en cours : id programmation → fiche `recordings`.
  final Map<String, Recording> _dartJobs = <String, Recording>{};

  /// `true` si les alarmes exactes sont disponibles (affichage d'un conseil
  /// sinon). Rafraîchi au démarrage.
  bool exactAlarmsOk = true;

  bool get nativeSupported => _native.isSupported;

  /// Démarre le planificateur (boot). Idempotent, jamais bloquant.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _repo.initialize();
      await RecordingStoragePolicy.instance.load();
      if (_native.isSupported) {
        exactAlarmsOk = await _native.canScheduleExact();
      }
      await _repo.pruneOlderThan(const Duration(days: 14));
      await tick();
    } catch (e) {
      if (kDebugMode) debugPrint('[Scheduler] start: $e');
    }
    _timer?.cancel();
    _timer = Timer.periodic(tickEvery, (_) => tick());
  }

  // ---------------------------------------------------------------
  //  Programmer / annuler
  // ---------------------------------------------------------------

  /// Programme l'enregistrement de [program] sur [channel].
  Future<ScheduleResult> schedule({
    required Channel channel,
    required EpgProgram program,
    int marginBeforeMs = ScheduledRecording.defaultMarginBeforeMs,
    int marginAfterMs = ScheduledRecording.defaultMarginAfterMs,
  }) async {
    return scheduleRange(
      channel: channel,
      title: program.title,
      startMs: program.startTime,
      stopMs: program.stopTime,
      marginBeforeMs: marginBeforeMs,
      marginAfterMs: marginAfterMs,
    );
  }

  /// Programme un créneau libre (début/fin explicites).
  Future<ScheduleResult> scheduleRange({
    required Channel channel,
    required String title,
    required int startMs,
    required int stopMs,
    int marginBeforeMs = ScheduledRecording.defaultMarginBeforeMs,
    int marginAfterMs = ScheduledRecording.defaultMarginAfterMs,
  }) async {
    try {
      await _repo.initialize();
      final int now = DateTime.now().millisecondsSinceEpoch;
      if (stopMs <= now) return ScheduleResult.tooLate;

      final String path = await RecordingRepository.instance.createFilePath(
        channelName: channel.cleanName,
        programTitle: title,
        at: DateTime.fromMillisecondsSinceEpoch(startMs),
      );
      final ScheduledRecording entry = ScheduledRecording(
        id: ScheduledRecording.idFor(channel.id, startMs),
        channelId: channel.id,
        channelName: channel.cleanName,
        channelLogoUrl: channel.logoUrl,
        streamUrl: channel.streamUrl,
        programTitle: title,
        startMs: startMs,
        stopMs: stopMs,
        marginBeforeMs: marginBeforeMs,
        marginAfterMs: marginAfterMs,
        filePath: path,
        createdAt: now,
      );

      // Une connexion à la fois : deux chaînes différentes ne peuvent pas
      // être captées en même temps. La même chaîne, si (tee).
      for (final ScheduledRecording other in _repo.active) {
        if (other.channelId != entry.channelId && entry.overlaps(other)) {
          return ScheduleResult.conflict;
        }
      }

      await _repo.upsert(entry);
      if (_native.isSupported) {
        final bool ok = await _native.schedule(
          id: entry.id,
          url: entry.streamUrl,
          file: entry.filePath,
          title: '${entry.channelName} · $title',
          startMs: entry.effectiveStartMs,
          stopMs: entry.effectiveStopMs,
          notifTitle: l10nNow.playerRecording,
          channelName: l10nNow.recordingNotifChannelName,
          channelDesc: l10nNow.recordingNotifChannelDesc,
        );
        if (!ok && kDebugMode) {
          debugPrint('[Scheduler] alarmes natives non posées (${entry.id}) '
              '→ le tick Dart assurera le créneau si l\'app tourne');
        }
      }
      StructuredLogger.instance.info(
        domain: 'rec',
        event: 'schedule.add',
        ctx: <String, Object?>{
          'id': entry.id,
          'channel': entry.channelName,
          'start': entry.startMs,
          'stop': entry.stopMs,
          'native': _native.isSupported,
        },
      );
      notifyListeners();
      // Si le créneau est déjà ouvert (« enregistre l'émission en cours »),
      // on n'attend pas 30 s.
      if (entry.effectiveStartMs <= now) unawaited(tick());
      return ScheduleResult.ok;
    } catch (e) {
      if (kDebugMode) debugPrint('[Scheduler] schedule: $e');
      return ScheduleResult.failed;
    }
  }

  /// Annule une programmation ; arrête la capture si elle a commencé.
  Future<void> cancel(String id) async {
    final ScheduledRecording? entry = _repo.byId(id);
    if (entry == null) return;
    if (_native.isSupported) await _native.cancel(id);
    final Recording? job = _dartJobs.remove(id);
    if (job != null) {
      await _stopDartJob(entry, job);
      await _repo.upsert(entry.copyWith(status: ScheduledRecordingStatus.done));
    } else if (entry.status == ScheduledRecordingStatus.recording) {
      // Capture natif en cours : le natif a reçu STOP, la prochaine
      // réconciliation lira « done » et créera la fiche.
      await _repo.upsert(entry.copyWith(status: ScheduledRecordingStatus.recording));
      unawaited(Future<void>.delayed(const Duration(seconds: 2), tick));
    } else {
      await _repo.delete(id);
    }
    StructuredLogger.instance.info(
      domain: 'rec',
      event: 'schedule.cancel',
      ctx: <String, Object?>{'id': id},
    );
    notifyListeners();
  }

  /// Programmation active pour cette émission (icône du guide).
  ScheduledRecording? activeFor(String channelId, int startMs) =>
      _repo.activeFor(channelId, startMs);

  // ---------------------------------------------------------------
  //  Réconciliation périodique
  // ---------------------------------------------------------------

  Future<void> tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await _repo.initialize();
      final int now = DateTime.now().millisecondsSinceEpoch;
      Map<String, NativeRecordingStatus> natives =
          const <String, NativeRecordingStatus>{};
      if (_native.isSupported && _repo.active.isNotEmpty) {
        natives = <String, NativeRecordingStatus>{
          for (final NativeRecordingStatus s in await _native.statusAll())
            s.id: s,
        };
      }
      for (final ScheduledRecording entry in _repo.active) {
        final ScheduleAction action = SchedulePlanner.decide(
          entry: entry,
          native: natives[entry.id],
          nativeSupported: _native.isSupported,
          dartJobRunning: _dartJobs.containsKey(entry.id),
          nowMs: now,
        );
        await _apply(entry, action, natives[entry.id]);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Scheduler] tick: $e');
    } finally {
      _ticking = false;
    }
  }

  Future<void> _apply(
    ScheduledRecording entry,
    ScheduleAction action,
    NativeRecordingStatus? native,
  ) async {
    switch (action) {
      case ScheduleAction.none:
        return;
      case ScheduleAction.startDart:
        await _startDartJob(entry);
      case ScheduleAction.stopDart:
        final Recording? job = _dartJobs.remove(entry.id);
        if (job != null) await _stopDartJob(entry, job);
        await _repo.upsert(entry.copyWith(
          status: ScheduledRecordingStatus.done,
          bytes: job == null ? null : _bytesOf(job.filePath),
        ));
        unawaited(RecordingStoragePolicy.instance.enforce());
      case ScheduleAction.reflectNativeRecording:
        int? recId = entry.recordingId;
        if (recId == null) {
          final Recording rec = await _createRecordRow(entry,
              startedAt: native?.startedAt);
          recId = rec.id;
        }
        // On réécrit aussi quand les octets bougent : l'écran « Prévus »
        // affiche la taille qui grossit (preuve visible que ça enregistre).
        if (entry.status != ScheduledRecordingStatus.recording ||
            recId != entry.recordingId ||
            (native?.bytes ?? 0) != entry.bytes) {
          await _repo.upsert(entry.copyWith(
            status: ScheduledRecordingStatus.recording,
            recordingId: recId,
            bytes: native?.bytes,
          ));
        }
      case ScheduleAction.reflectNativeDone:
        if (entry.recordingId == null) {
          await _createRecordRow(entry, startedAt: native?.startedAt);
        }
        await RecordingRepository.instance.finishRecordingByPath(
          entry.filePath,
          reason: (native?.bytes ?? 0) == 0 ? 'serverUnreachable' : null,
        );
        await _repo.upsert(entry.copyWith(
          status: (native?.bytes ?? 0) > 0
              ? ScheduledRecordingStatus.done
              : ScheduledRecordingStatus.failed,
          bytes: native?.bytes,
          error: (native?.bytes ?? 0) > 0 ? null : 'empty',
        ));
        await _native.forget(entry.id);
        unawaited(RecordingStoragePolicy.instance.enforce());
      case ScheduleAction.reflectNativeFailed:
        await _repo.upsert(entry.copyWith(
          status: ScheduledRecordingStatus.failed,
          error: native?.error ?? 'native',
        ));
        await _native.forget(entry.id);
      case ScheduleAction.markMissed:
        // Un fichier non vide existe (capture interrompue par un kill) →
        // on le garde comme enregistrement terminé plutôt que de le perdre.
        final int bytes = _bytesOf(entry.filePath);
        if (bytes > 0) {
          if (entry.recordingId == null) await _createRecordRow(entry);
          await RecordingRepository.instance.finishRecordingByPath(
            entry.filePath,
            reason: 'interruptedByOsKill',
          );
          await _repo.upsert(entry.copyWith(
            status: ScheduledRecordingStatus.done,
            bytes: bytes,
          ));
        } else {
          await _repo.upsert(entry.copyWith(
            status: ScheduledRecordingStatus.missed,
          ));
        }
        if (_native.isSupported) await _native.forget(entry.id);
    }
    notifyListeners();
  }

  int _bytesOf(String path) {
    try {
      final File f = File(path);
      return f.existsSync() ? f.lengthSync() : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<Recording> _createRecordRow(
    ScheduledRecording entry, {
    int? startedAt,
  }) {
    return RecordingRepository.instance.startRecording(
      channelId: entry.channelId,
      channelName: entry.channelName,
      programTitle: entry.programTitle,
      filePath: entry.filePath,
      channelLogoUrl: entry.channelLogoUrl,
      streamUrl: entry.streamUrl,
      startedAt: startedAt,
    );
  }

  // ---------------------------------------------------------------
  //  Exécuteur DART (pas de natif, ou natif muet)
  // ---------------------------------------------------------------

  Future<void> _startDartJob(ScheduledRecording entry) async {
    if (_dartJobs.containsKey(entry.id)) return;
    // Le natif ne doit plus démarrer en double sur ce créneau.
    if (_native.isSupported) await _native.cancel(entry.id);

    if (!await RecordingStoragePolicy.instance.hasRoomToStart()) {
      await _repo.upsert(entry.copyWith(
        status: ScheduledRecordingStatus.failed,
        error: 'noSpace',
      ));
      return;
    }

    // Une seule connexion : si le lecteur lit DÉJÀ cette chaîne via le
    // relais, on se branche dessus (tee) — zéro connexion de plus.
    bool ok = false;
    bool viaRelay = false;
    if (LocalStreamRelay.instance.isPlaying(entry.streamUrl)) {
      ok = await LocalStreamRelay.instance.startRecording(
        realUrl: entry.streamUrl,
        filePath: entry.filePath,
      );
      viaRelay = ok;
    }
    if (!ok) {
      ok = await HttpRecordingDownloader.instance.start(
        streamUrl: entry.streamUrl,
        filePath: entry.filePath,
        onAutoStopped: (String path, AutoStopReason reason) {
          unawaited(_onDartAutoStopped(entry.id, path, reason));
        },
      );
    }
    if (!ok) {
      await _repo.upsert(entry.copyWith(
        status: ScheduledRecordingStatus.failed,
        error: 'startFailed',
      ));
      return;
    }
    final Recording rec = await _createRecordRow(entry);
    _dartJobs[entry.id] = rec;
    await _repo.upsert(entry.copyWith(
      status: ScheduledRecordingStatus.recording,
      recordingId: rec.id,
    ));
    StructuredLogger.instance.info(
      domain: 'rec',
      event: 'schedule.dart_start',
      ctx: <String, Object?>{'id': entry.id, 'relay': viaRelay},
    );
  }

  Future<void> _stopDartJob(ScheduledRecording entry, Recording job) async {
    try {
      await LocalStreamRelay.instance.stopRecording(entry.streamUrl);
    } catch (_) {}
    try {
      await HttpRecordingDownloader.instance.stop(filePath: entry.filePath);
    } catch (_) {}
    try {
      await RecordingRepository.instance.finishRecording(job);
    } catch (_) {}
  }

  Future<void> _onDartAutoStopped(
    String id,
    String path,
    AutoStopReason reason,
  ) async {
    final Recording? job = _dartJobs.remove(id);
    final ScheduledRecording? entry = _repo.byId(id);
    await RecordingRepository.instance.finishRecordingByPath(
      path,
      reason: reason.name,
    );
    if (entry != null) {
      final int bytes = _bytesOf(path);
      await _repo.upsert(entry.copyWith(
        status: bytes > 0
            ? ScheduledRecordingStatus.done
            : ScheduledRecordingStatus.failed,
        bytes: bytes,
        error: bytes > 0 ? null : reason.name,
        recordingId: job?.id,
      ));
    }
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _dartJobs.clear();
  }
}
