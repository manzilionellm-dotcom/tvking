import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/google_cast_api.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

class _Transport implements CastTransport {
  Completer<void>? playGate;
  Completer<void>? stopGate;
  Completer<void>? pauseGate;
  Object? playError;
  void Function()? onStop;
  final Completer<void> playing = Completer<void>();
  final Completer<void> stopping = Completer<void>();
  int stops = 0;
  @override
  Future<void> playStream({
    required String streamUrl,
    String title = 'Test',
    String? imageUrl,
  }) async {
    if (!playing.isCompleted) playing.complete();
    if (playGate != null) await playGate!.future;
    if (playError != null) throw playError!;
  }

  @override
  Future<void> stop() async {
    stops++;
    onStop?.call();
    if (!stopping.isCompleted) stopping.complete();
    if (stopGate != null) await stopGate!.future;
  }

  @override
  Future<void> pause() async {
    if (pauseGate != null) await pauseGate!.future;
  }

  @override
  Future<void> resume() async {}
}

CastDevice _device(String id) => CastDevice(
      id: id,
      name: id,
      kind: CastDeviceKind.roku,
      host: '192.0.2.1',
      port: 8060,
      controlUrl: 'http://192.0.2.1',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Transport first;
  late _Transport second;
  late CastManager manager;
  late List<String> probed;
  setUp(() {
    first = _Transport();
    second = _Transport();
    probed = <String>[];
    manager = CastManager.forTesting(
      transportFactory: (d) => d.id == 'first' ? first : second,
      probe: (url) async {
        probed.add(url);
        return StreamProbeResult(
          originalUrl: url,
          finalUrl: url,
          success: true,
        );
      },
      timeout: const Duration(milliseconds: 150),
    );
  });
  tearDown(() async {
    await manager.disconnect();
    manager.dispose();
  });
  Future<void> cast(String id, {Object? owner, CastDevice? device}) =>
      manager.castTo(
        device ?? _device(id),
        streamUrl: 'http://stream.invalid/$id.ts',
        title: id,
        owner: owner,
      );

  CastDevice googleDevice() => const CastDevice(
        id: 'first',
        name: 'Google synthétique',
        kind: CastDeviceKind.googleCast,
        host: '192.0.2.2',
        port: 8009,
        controlUrl: 'http://192.0.2.2',
      );

  test('timeout ancien ne stoppe jamais une nouvelle session', () async {
    first.playGate = Completer<void>();
    final Future<void> old = cast('first');
    await first.playing.future;
    await cast('second');
    await old;
    expect(manager.state, CastState.casting);
    expect(manager.currentTitle, 'second');
    expect(second.stops, 0);
    first.playGate!.complete();
  });
  test('déconnexion pendant play ne ressuscite pas la session', () async {
    first.playGate = Completer<void>();
    final Future<void> pending = cast('first');
    await first.playing.future;
    await manager.disconnect();
    first.playGate!.complete();
    await pending;
    expect(manager.state, CastState.idle);
    expect(manager.device, isNull);
  });
  test('le nouveau probe attend le stop lent sans perdre sa session', () async {
    await cast('first');
    first.stopGate = Completer<void>();
    final Future<void> stopping = manager.disconnect();
    await first.stopping.future;
    final Future<void> next = cast('second');
    expect(probed, hasLength(1), reason: 'pas de second flux avant le Stop');
    expect(second.playing.isCompleted, isFalse);
    first.stopGate!.complete();
    await stopping;
    await next;
    expect(manager.device?.id, 'second');
    expect(manager.state, CastState.casting);
  });
  test('pause ancienne et événement Google ne touchent pas Roku', () async {
    await cast('first');
    first.pauseGate = Completer<void>();
    final Future<void> pausing = manager.pause();
    await cast('second');
    first.pauseGate!.complete();
    await pausing;
    manager.debugNativeSessionEvent(const CastNativeSessionEvent('ended'));
    expect(manager.state, CastState.casting);
    expect(manager.device?.id, 'second');
  });

  test('un zap Roku attend aussi le Stop avant son probe', () async {
    await cast('first');
    first.stopGate = Completer<void>();
    final Future<void> next = cast('second');
    await first.stopping.future;
    expect(probed, hasLength(1));
    first.stopGate!.complete();
    await next;
    expect(probed, hasLength(2));
    expect(manager.device?.id, 'second');
  });

  test(
    'B annulé pendant le Stop de A ne laisse pas C doubler le Stop',
    () async {
      await cast('first');
      first.stopGate = Completer<void>();
      final Future<void> middle = cast('obsolete');
      await first.stopping.future;
      final Object owner = Object();
      final Future<void> latest = cast('second', owner: owner);
      expect(probed, hasLength(1));
      first.stopGate!.complete();
      await Future.wait(<Future<void>>[middle, latest]);
      expect(probed, <String>[
        'http://stream.invalid/first.ts',
        'http://stream.invalid/second.ts',
      ]);
      expect(manager.ownsSession(owner), isTrue);
      expect(second.stops, 0);
    },
  );

  test(
    'une ancienne route ne peut ni piloter ni arrêter le nouveau Cast',
    () async {
      final Object oldOwner = Object();
      final Object newOwner = Object();
      await cast('first', owner: oldOwner);
      final int oldRevision = manager.sessionRevision;
      await cast('second', owner: newOwner);
      expect(await manager.disconnectIfOwned(oldRevision), isFalse);
      expect(await manager.disconnectForOwner(oldOwner), isFalse);
      expect(
        await manager.castChannelOnCurrentSession(
          streamUrl: 'http://stream.invalid/obsolete.ts',
          title: 'ancien',
          owner: oldOwner,
        ),
        isFalse,
      );
      expect(manager.ownsSession(newOwner), isTrue);
      expect(manager.state, CastState.casting);
      expect(probed, hasLength(2));
      expect(second.stops, 0);
    },
  );

  test(
    'le propriétaire peut annuler son démarrage avant la première lecture',
    () async {
      final Object owner = Object();
      first.playGate = Completer<void>();
      final Future<void> pending = cast('first', owner: owner);
      expect(
        manager.ownsSession(owner),
        isTrue,
        reason: 'identité disponible dès l’appel, avant le premier await',
      );
      await first.playing.future;
      expect(await manager.disconnectForOwner(owner), isTrue);
      first.playGate!.complete();
      await pending;
      expect(manager.state, CastState.idle);
      expect(manager.ownsSession(owner), isFalse);
      expect(first.stops, 1);
    },
  );

  test('le zap garde le propriétaire et change la révision', () async {
    final Object owner = Object();
    await cast('first', owner: owner);
    final int before = manager.sessionRevision;
    expect(
      await manager.castChannelOnCurrentSession(
        streamUrl: 'http://stream.invalid/next.ts',
        title: 'suivante',
      ),
      isTrue,
    );
    expect(manager.ownsSession(owner), isTrue);
    expect(manager.sessionRevision, greaterThan(before));
    expect(await manager.disconnectIfOwned(before), isFalse);
    expect(manager.currentTitle, 'suivante');
  });

  test(
    'idle expose déjà la fermeture et le propriétaire peut encore l’attendre',
    () async {
      final Object owner = Object();
      await cast('first', owner: owner);
      first.stopGate = Completer<void>();
      bool cleanupFinished = false;
      bool ownerFinished = false;
      final Future<void> externalStop = manager.disconnect();
      expect(manager.state, CastState.idle);
      expect(manager.ownsSession(owner), isFalse);
      final Future<void> cleanup = manager.waitForSessionCleanup().then((_) {
        cleanupFinished = true;
      });
      final Future<bool> ownerStop = manager.disconnectForOwner(owner).then((
        value,
      ) {
        ownerFinished = true;
        return value;
      });
      await first.stopping.future;
      expect(cleanupFinished, isFalse);
      expect(ownerFinished, isFalse);
      first.stopGate!.complete();
      await externalStop;
      await cleanup;
      expect(await ownerStop, isTrue);
      expect(
        first.stops,
        1,
        reason: 'attendre le même Stop, sans en envoyer un autre',
      );
    },
  );

  test(
    'un échec expose sa fermeture avant error et conserve son propriétaire',
    () async {
      final Object owner = Object();
      first.playError = StateError('échec synthétique');
      first.stopGate = Completer<void>();
      await expectLater(cast('first', owner: owner), throwsStateError);
      await first.stopping.future;
      expect(manager.state, CastState.error);
      expect(manager.ownsSession(owner), isTrue);
      bool completed = false;
      final Future<void> cleanup = manager.waitForSessionCleanup().then((_) {
        completed = true;
      });
      await Future<void>.value();
      expect(completed, isFalse);
      first.stopGate!.complete();
      await cleanup;
      expect(completed, isTrue);
      expect(first.stops, 1);
    },
  );

  test('timeout garde une identité terminale après nettoyage', () async {
    final Object owner = Object();
    first.playGate = Completer<void>();
    first.onStop = () => manager.debugNativeSessionEvent(
          const CastNativeSessionEvent('ended'),
        );
    await expectLater(
      cast('first', owner: owner, device: googleDevice()),
      throwsA(isA<TimeoutException>()),
    );
    expect(manager.state, CastState.error);
    expect(manager.ownsSession(owner), isTrue);
    expect(first.stops, 1);
    first.playGate!.complete();
    await Future<void>.value();
    expect(manager.state, CastState.error);
  });

  test(
    'suspension Google garde le transfert jusqu’à la reprise native',
    () async {
      final Object owner = Object();
      await cast('first', owner: owner, device: googleDevice());
      manager.debugNativeSessionEvent(
        const CastNativeSessionEvent('suspended'),
      );
      expect(manager.isSuspended, isTrue);
      expect(manager.state, CastState.casting);
      expect(manager.isCasting, isTrue);
      expect(manager.ownsSession(owner), isTrue);
      expect(
        await manager.castChannelOnCurrentSession(
          streamUrl: 'http://stream.invalid/next.ts',
          title: 'suivante',
          owner: owner,
        ),
        isFalse,
      );
      manager.debugNativeSessionEvent(const CastNativeSessionEvent('resumed'));
      expect(manager.isSuspended, isFalse);
      expect(manager.state, CastState.casting);
      expect(first.stops, 0);
    },
  );

  test(
    'refus Google tardif annule le démarrage et rend son nettoyage attendable',
    () async {
      final Object owner = Object();
      first.playGate = Completer<void>();
      first.stopGate = Completer<void>();
      final Future<void> pending = cast(
        'first',
        owner: owner,
        device: googleDevice(),
      );
      await first.playing.future;
      manager.debugNativeSessionEvent(
        const CastNativeSessionEvent('load_failed'),
      );
      await first.stopping.future;
      expect(manager.state, CastState.error);
      expect(manager.ownsSession(owner), isTrue);
      first.playGate!.complete();
      await pending;
      expect(
        manager.state,
        CastState.error,
        reason: 'aucune résurrection après play',
      );
      bool completed = false;
      final Future<void> cleanup = manager.waitForSessionCleanup().then((_) {
        completed = true;
      });
      await Future<void>.value();
      expect(completed, isFalse);
      first.stopGate!.complete();
      await cleanup;
      expect(first.stops, 1);
    },
  );

  test('la fin native est nettoyée avant qu’un listener ouvre le Cast suivant',
      () async {
    await cast('first', owner: Object(), device: googleDevice());
    final Object nextOwner = Object();
    Future<void>? next;
    void restart() {
      if (manager.state == CastState.idle && next == null) {
        next = cast('second', owner: nextOwner);
      }
    }

    manager.addListener(restart);
    manager.debugNativeSessionEvent(const CastNativeSessionEvent('ended'));
    manager.removeListener(restart);
    expect(next, isNotNull);
    await next;
    expect(manager.device?.id, 'second');
    expect(manager.ownsSession(nextOwner), isTrue);
    expect(manager.state, CastState.casting);
    expect(second.stops, 0);
  });
}
