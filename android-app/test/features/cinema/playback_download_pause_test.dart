import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cinema/data/playback_download_pause.dart';

void main() {
  late Set<String> active;
  late List<String> events;
  late PlaybackDownloadPause gate;
  late Object ownerA;
  late Object ownerB;
  Future<void> Function(String)? beforePause;
  Future<void> Function(String)? beforeResume;

  setUp(() {
    active = <String>{'film'};
    events = <String>[];
    ownerA = Object();
    ownerB = Object();
    beforePause = null;
    beforeResume = null;
    gate = PlaybackDownloadPause(
      activeIds: () {
        events.add('read');
        return active;
      },
      pause: (id) async {
        events.add('pause:$id');
        await beforePause?.call(id);
        active.remove(id);
      },
      resume: (id) async {
        events.add('resume:$id');
        await beforeResume?.call(id);
        active.add(id);
      },
    );
  });

  test('réservation synchrone, avant la lecture des actifs', () async {
    final future = gate.reserve(owner: ownerA);
    expect(gate.hasOwners, isTrue);
    expect(events, isEmpty);
    await future;
    expect(active, isEmpty);
  });

  test('la fermeture tardive de A ne relance rien pendant B', () async {
    await gate.reserve(owner: ownerA);
    await gate.reserve(owner: ownerB); // aucun téléchargement encore actif
    await gate.release(owner: ownerA);
    expect(events.where((e) => e.startsWith('resume:')), isEmpty);
    expect(gate.holds('film'), isTrue);
    await gate.release(owner: ownerB);
    expect(active, <String>{'film'});
    expect(events.where((e) => e == 'resume:film').length, 1);
    expect(gate.pendingCount, 0);
  });

  test('B réserve avant le départ d’une reprise déjà en file', () async {
    await gate.reserve(owner: ownerA);
    final release = gate.release(owner: ownerA);
    final reserve = gate.reserve(owner: ownerB);
    await Future.wait([release, reserve]);
    expect(active, isEmpty);
    expect(events.where((e) => e.startsWith('resume:')), isEmpty);
    await gate.release(owner: ownerB);
    expect(active, <String>{'film'});
  });

  test('B arrivé pendant une reprise attend sa remise en pause ; IDs conservés',
      () async {
    active.add('episode');
    await gate.reserve(owner: ownerA);
    final entered = Completer<void>();
    final finish = Completer<void>();
    beforeResume = (id) async {
      if (id == 'film' && !entered.isCompleted) {
        entered.complete();
        await finish.future;
      }
    };
    final release = gate.release(owner: ownerA);
    await entered.future;
    var bReady = false;
    final reserve = gate.reserve(owner: ownerB).then((_) => bReady = true);
    expect(gate.hasOwners, isTrue);
    expect(bReady, isFalse);
    finish.complete();
    await Future.wait([release, reserve]);
    expect(bReady, isTrue);
    expect(active, isEmpty);
    expect(gate.holds('film'), isTrue);
    expect(gate.holds('episode'), isTrue);
    expect(events.where((e) => e == 'resume:episode'), isEmpty);
    await gate.release(owner: ownerB);
    expect(active, <String>{'film', 'episode'});
    expect(gate.pendingCount, 0);
  });

  test('A sort pendant sa pause, B garde la réservation dans la même file',
      () async {
    final entered = Completer<void>();
    final finish = Completer<void>();
    beforePause = (_) async {
      if (!entered.isCompleted) {
        entered.complete();
        await finish.future;
      }
    };
    final firstPause = gate.reserve(owner: ownerA);
    await entered.future;
    final release = gate.release(owner: ownerA);
    final nextPause = gate.reserve(owner: ownerB);
    finish.complete();
    await Future.wait([firstPause, release, nextPause]);
    expect(active, isEmpty);
    expect(events.where((e) => e.startsWith('resume:')), isEmpty);
    await gate.release(owner: ownerB);
    expect(active, <String>{'film'});
  });

  test('réserver deux fois le même propriétaire reste idempotent', () async {
    await gate.reserve(owner: ownerA);
    await gate.reserve(owner: ownerA);
    await gate.release(owner: ownerA);
    expect(gate.hasOwners, isFalse);
    expect(active, <String>{'film'});
    expect(events.where((e) => e == 'resume:film').length, 1);
  });

  test('le jeton legacy reste distinct des propriétaires explicites', () async {
    await gate.reserve();
    await gate.reserve();
    await gate.reserve(owner: ownerB);
    await gate.release();
    expect(gate.hasOwners, isTrue);
    expect(active, isEmpty);
    await gate.release(owner: ownerB);
    expect(gate.hasOwners, isFalse);
    expect(active, <String>{'film'});
  });

  test('une pause échouée reste réservée et peut être retentée', () async {
    beforePause = (_) async => throw StateError('pause failed');
    await expectLater(gate.reserve(owner: ownerA), throwsStateError);
    expect(gate.hasOwners, isTrue);
    expect(gate.holds('film'), isTrue);
    beforePause = null;
    await gate.reserve(owner: ownerA);
    expect(active, isEmpty);
    await gate.release(owner: ownerA);
    expect(active, <String>{'film'});
  });

  test('une reprise échouée conserve son ID et ne bloque pas la file',
      () async {
    await gate.reserve(owner: ownerA);
    beforeResume = (_) async => throw StateError('resume failed');
    await expectLater(gate.release(owner: ownerA), throwsStateError);
    expect(gate.holds('film'), isTrue);
    beforeResume = null;
    await gate.release(owner: ownerA);
    expect(active, <String>{'film'});
    expect(gate.pendingCount, 0);
  });
}
