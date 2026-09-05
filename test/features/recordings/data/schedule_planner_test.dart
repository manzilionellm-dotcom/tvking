// =========================================================
//  schedule_planner_test.dart — Décisions du magnétoscope (logique PURE)
// =========================================================
//  Ce que ces tests verrouillent :
//    1. SchedulePlanner.decide : quelle action à quel instant, selon ce
//       que dit le natif (rien / en cours / fini / échec) et selon qu'un
//       job Dart tourne déjà — sans base, sans natif, sans horloge.
//    2. ScheduledRecording.overlaps : deux créneaux qui se touchent.
//    3. RecordingStoragePolicy.selectForPurge : quota → plus anciens
//       d'abord, jamais un enregistrement en cours.
//    4. Les noms de statut (écrits en SQLite) restent stables.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/recordings/data/native_recording_scheduler.dart';
import 'package:tv_king/features/recordings/data/recording_scheduler.dart';
import 'package:tv_king/features/recordings/data/recording_storage_policy.dart';
import 'package:tv_king/features/recordings/domain/recording.dart';
import 'package:tv_king/features/recordings/domain/scheduled_recording.dart';

ScheduledRecording _entry({
  int start = 1_000_000,
  int stop = 1_600_000, // 10 min
  ScheduledRecordingStatus status = ScheduledRecordingStatus.planned,
  String channelId = 'tf1',
}) {
  return ScheduledRecording(
    id: ScheduledRecording.idFor(channelId, start),
    channelId: channelId,
    channelName: channelId.toUpperCase(),
    streamUrl: 'http://panel/live/u/p/1.ts',
    startMs: start,
    stopMs: stop,
    marginBeforeMs: 60_000,
    marginAfterMs: 120_000,
    filePath: '/tmp/x.ts',
    createdAt: 0,
    status: status,
  );
}

NativeRecordingStatus _native(String state, {int bytes = 0}) =>
    NativeRecordingStatus(id: 'x', state: state, bytes: bytes);

void main() {
  group('SchedulePlanner.decide', () {
    final ScheduledRecording e = _entry();
    // Créneau EFFECTIF : [940 000 ; 1 720 000].
    const int before = 900_000;
    const int inside = 1_100_000;
    const int justStarted = 950_000; // 10 s après le début effectif
    const int after = 1_800_000;

    test('avant le créneau : rien', () {
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: null,
            nativeSupported: true,
            dartJobRunning: false,
            nowMs: before),
        ScheduleAction.none,
      );
    });

    test('sans natif (PC) : le Dart démarre dès le début effectif', () {
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: null,
            nativeSupported: false,
            dartJobRunning: false,
            nowMs: justStarted),
        ScheduleAction.startDart,
      );
    });

    test('natif présent mais muet : délai de grâce, puis repli Dart', () {
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: null,
            nativeSupported: true,
            dartJobRunning: false,
            nowMs: justStarted),
        ScheduleAction.none,
        reason: 'on laisse 3 min à l\'alarme native',
      );
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: null,
            nativeSupported: true,
            dartJobRunning: false,
            nowMs: inside),
        ScheduleAction.startDart,
        reason: 'au-delà de la grâce, le Dart prend la main',
      );
    });

    test('natif en cours → refléter « en cours »', () {
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: _native('recording', bytes: 42),
            nativeSupported: true,
            dartJobRunning: false,
            nowMs: inside),
        ScheduleAction.reflectNativeRecording,
      );
    });

    test('natif terminé → finaliser', () {
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: _native('done', bytes: 999),
            nativeSupported: true,
            dartJobRunning: false,
            nowMs: after),
        ScheduleAction.reflectNativeDone,
      );
    });

    test('natif en échec PENDANT le créneau → le Dart rattrape', () {
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: _native('failed'),
            nativeSupported: true,
            dartJobRunning: false,
            nowMs: inside),
        ScheduleAction.startDart,
      );
    });

    test('natif en échec APRÈS le créneau → échec constaté', () {
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: _native('failed'),
            nativeSupported: true,
            dartJobRunning: false,
            nowMs: after),
        ScheduleAction.reflectNativeFailed,
      );
    });

    test('job Dart en cours : rien avant la fin, stop à la fin', () {
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: null,
            nativeSupported: false,
            dartJobRunning: true,
            nowMs: inside),
        ScheduleAction.none,
      );
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: null,
            nativeSupported: false,
            dartJobRunning: true,
            nowMs: after),
        ScheduleAction.stopDart,
      );
    });

    test('créneau passé sans capture → manqué', () {
      expect(
        SchedulePlanner.decide(
            entry: e,
            native: null,
            nativeSupported: true,
            dartJobRunning: false,
            nowMs: after),
        ScheduleAction.markMissed,
      );
    });

    test('entrée inactive (annulée / terminée) → jamais rien', () {
      for (final ScheduledRecordingStatus s in <ScheduledRecordingStatus>[
        ScheduledRecordingStatus.done,
        ScheduledRecordingStatus.missed,
        ScheduledRecordingStatus.failed,
        ScheduledRecordingStatus.cancelled,
      ]) {
        expect(
          SchedulePlanner.decide(
              entry: _entry(status: s),
              native: _native('recording'),
              nativeSupported: true,
              dartJobRunning: false,
              nowMs: inside),
          ScheduleAction.none,
          reason: 'statut $s',
        );
      }
    });
  });

  group('ScheduledRecording', () {
    test('overlaps : marges comprises, jamais avec soi-même', () {
      final ScheduledRecording a = _entry(start: 1_000_000, stop: 1_600_000);
      // b commence 1 min après la fin officielle de a : les MARGES (2 min
      // après / 1 min avant) se chevauchent → conflit.
      final ScheduledRecording b =
          _entry(start: 1_660_000, stop: 2_000_000, channelId: 'm6');
      expect(a.overlaps(b), isTrue);
      expect(b.overlaps(a), isTrue);
      expect(a.overlaps(a), isFalse);
      // c commence bien après : libre.
      final ScheduledRecording c =
          _entry(start: 3_000_000, stop: 3_600_000, channelId: 'm6');
      expect(a.overlaps(c), isFalse);
    });

    test('idFor est stable pour (chaîne, début) → reprogrammer remplace', () {
      expect(ScheduledRecording.idFor('tf1', 42),
          ScheduledRecording.idFor('tf1', 42));
      expect(ScheduledRecording.idFor('tf1', 42),
          isNot(ScheduledRecording.idFor('m6', 42)));
    });

    test('toMap/fromMap : aller-retour sans perte', () {
      final ScheduledRecording e = _entry().copyWith(
        status: ScheduledRecordingStatus.recording,
        recordingId: 7,
        bytes: 1234,
        error: 'x',
      );
      final ScheduledRecording back = ScheduledRecording.fromMap(e.toMap());
      expect(back.id, e.id);
      expect(back.status, ScheduledRecordingStatus.recording);
      expect(back.recordingId, 7);
      expect(back.bytes, 1234);
      expect(back.error, 'x');
      expect(back.effectiveStartMs, e.effectiveStartMs);
      expect(back.effectiveStopMs, e.effectiveStopMs);
    });

    test('noms de statut (clés SQLite) stables', () {
      expect(ScheduledRecordingStatus.planned.name, 'planned');
      expect(ScheduledRecordingStatus.recording.name, 'recording');
      expect(ScheduledRecordingStatus.done.name, 'done');
      expect(ScheduledRecordingStatus.missed.name, 'missed');
      expect(ScheduledRecordingStatus.failed.name, 'failed');
      expect(ScheduledRecordingStatus.cancelled.name, 'cancelled');
    });
  });

  group('RecordingStoragePolicy.selectForPurge', () {
    Recording rec(int id, int startedAt, int size, {bool live = false}) =>
        Recording(
          id: id,
          channelId: 'c',
          channelName: 'C',
          filePath: '/tmp/$id.ts',
          startedAt: startedAt,
          endedAt: live ? null : startedAt + 1000,
          fileSizeBytes: size,
        );

    test('sans limite (0) → rien', () {
      expect(
          RecordingStoragePolicy.selectForPurge(
              <Recording>[rec(1, 1, 100), rec(2, 2, 100)], 0),
          isEmpty);
    });

    test('sous la limite → rien', () {
      expect(
          RecordingStoragePolicy.selectForPurge(
              <Recording>[rec(1, 1, 100), rec(2, 2, 100)], 250),
          isEmpty);
    });

    test('au-dessus → les plus ANCIENS d\'abord, juste ce qu\'il faut', () {
      final List<Recording> victims = RecordingStoragePolicy.selectForPurge(
        <Recording>[rec(3, 30, 100), rec(1, 10, 100), rec(2, 20, 100)],
        150,
      );
      expect(victims.map((Recording r) => r.id), <int>[1, 2]);
    });

    test('un enregistrement EN COURS n\'est jamais supprimé', () {
      final List<Recording> victims = RecordingStoragePolicy.selectForPurge(
        <Recording>[rec(1, 10, 100, live: true), rec(2, 20, 100)],
        50,
      );
      expect(victims.map((Recording r) => r.id), <int>[2]);
    });
  });
}
