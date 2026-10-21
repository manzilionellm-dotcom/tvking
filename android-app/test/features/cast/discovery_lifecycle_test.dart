import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

class _Transport implements CastTransport {
  Completer<void>? playGate;
  final Completer<void> playing = Completer<void>();
  int stops = 0;

  @override
  Future<void> playStream({
    required String streamUrl,
    String title = 'Test',
    String? imageUrl,
  }) async {
    if (!playing.isCompleted) playing.complete();
    if (playGate != null) await playGate!.future;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {
    stops++;
  }
}

CastDevice _device(int number) => CastDevice(
      id: 'receiver-$number',
      name: 'Récepteur $number',
      kind: CastDeviceKind.roku,
      host: '192.0.2.$number',
      port: 8060,
      controlUrl: 'http://192.0.2.$number',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CastManager manager;
  late _Transport transport;
  late List<StreamController<CastDevice>> scans;
  late int probes;

  setUp(() {
    CastPlatform.resetForTesting();
    transport = _Transport();
    scans = <StreamController<CastDevice>>[];
    probes = 0;
    manager = CastManager.forTesting(
      transportFactory: (_) => transport,
      probe: (url) async {
        probes++;
        return StreamProbeResult(
          originalUrl: url,
          finalUrl: url,
          success: true,
        );
      },
      discoverSsdp: (_) {
        // Ces streams sont les seules sources de découverte du test.
        // Aucune socket SSDP/mDNS et aucune TV réelle ne sont sollicitées.
        final StreamController<CastDevice> scan =
            StreamController<CastDevice>.broadcast(sync: true);
        scans.add(scan);
        return scan.stream;
      },
    );
  });

  tearDown(() async {
    manager.stopDiscovery();
    manager.stopWarmup();
    await manager.disconnect();
    manager.dispose();
    for (final StreamController<CastDevice> scan in scans) {
      await scan.close();
    }
    CastPlatform.resetForTesting();
  });

  Future<void> cast() => manager.castTo(
        _device(1),
        streamUrl: 'http://stream.invalid/live.ts',
        title: 'Test',
      );

  testWidgets(
    'rafraîchir les appareils conserve un Cast actif jusque après le délai',
    (tester) async {
      await cast();
      final int revision = manager.sessionRevision;
      final List<CastState> states = <CastState>[];
      manager.addListener(() => states.add(manager.state));
      await manager.startDiscovery(timeout: const Duration(milliseconds: 50));
      expect(manager.isDiscovering, isTrue);
      expect(manager.isCasting, isTrue);
      expect(manager.state, CastState.casting);
      scans.single.add(_device(2));
      await tester.pump(const Duration(milliseconds: 60));
      expect(manager.isDiscovering, isFalse);
      expect(manager.state, CastState.casting);
      expect(manager.sessionRevision, revision);
      expect(manager.discoveredDevices.single.id, 'receiver-2');
      expect(states.every((state) => state == CastState.casting), isTrue);
      expect(transport.stops, 0);
      expect(probes, 1);
    },
  );

  testWidgets('arrêter la découverte conserve aussi la pause distante', (
    tester,
  ) async {
    await cast();
    await manager.pause();
    await manager.startDiscovery(timeout: const Duration(milliseconds: 50));
    expect(manager.state, CastState.paused);
    expect(manager.isCasting, isTrue);
    manager.stopDiscovery();
    await tester.pump(const Duration(milliseconds: 60));
    expect(manager.state, CastState.paused);
    expect(manager.isDiscovering, isFalse);
    expect(transport.stops, 0);
  });

  testWidgets('la découverte ne masque jamais un démarrage en attente', (
    tester,
  ) async {
    // Le Completer d'attente doit naître dans l'horloge de ce test widget,
    // pas dans le setUp extérieur à cette horloge.
    transport = _Transport();
    transport.playGate = Completer<void>();
    final Future<void> pending = cast();
    await transport.playing.future;
    await manager.startDiscovery(timeout: const Duration(milliseconds: 50));
    expect(manager.state, CastState.connecting);
    await tester.pump(const Duration(milliseconds: 60));
    expect(manager.state, CastState.connecting);
    transport.playGate!.complete();
    await pending;
    expect(manager.state, CastState.casting);
  });

  testWidgets(
    'annuler un scan puis rescanner ignore les événements et le délai anciens',
    (tester) async {
      await manager.startDiscovery(timeout: const Duration(milliseconds: 20));
      final StreamController<CastDevice> old = scans.single;
      manager.stopDiscovery();
      await manager.startDiscovery(
        timeout: const Duration(milliseconds: 80),
        keepExisting: false,
      );
      old.add(_device(2));
      scans.last.add(_device(3));
      await tester.pump(const Duration(milliseconds: 30));
      expect(manager.isDiscovering, isTrue);
      expect(manager.discoveredDevices.map((device) => device.id), <String>[
        'receiver-3',
      ]);
      await tester.pump(const Duration(milliseconds: 60));
      expect(manager.state, CastState.idle);
      expect(manager.isDiscovering, isFalse);
    },
  );

  testWidgets('un scan arrêté ne recrée pas de scan différé après stopWarmup', (
    tester,
  ) async {
    manager.startWarmup(
      initialDelay: const Duration(milliseconds: 20),
      interval: const Duration(milliseconds: 50),
    );
    manager.stopWarmup();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scans, isEmpty);
    expect(manager.isDiscovering, isFalse);
  });

  testWidgets(
    'une notification peut annuler le scan avant toute ouverture réseau',
    (tester) async {
      void cancel() {
        if (manager.isDiscovering) manager.stopDiscovery();
      }

      manager.addListener(cancel);
      await manager.startDiscovery(timeout: const Duration(milliseconds: 20));
      manager.removeListener(cancel);
      await tester.pump(const Duration(milliseconds: 30));
      expect(scans, isEmpty);
      expect(manager.isDiscovering, isFalse);
    },
  );

  testWidgets(
    'l’édition TV ne démarre ni découverte ni Cast même appelée directement',
    (tester) async {
      CastPlatform.configureZuno(ZunoEdition.television);
      await manager.startDiscovery();
      manager.startWarmup(
        initialDelay: const Duration(milliseconds: 20),
        interval: const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(cast(), throwsUnsupportedError);
      expect(scans, isEmpty);
      expect(probes, 0);
      expect(manager.state, CastState.idle);
      expect(manager.isDiscovering, isFalse);
      expect(transport.playing.isCompleted, isFalse);
    },
  );
}
