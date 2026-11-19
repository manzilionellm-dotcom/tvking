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
  final Completer<void> playing = Completer<void>();
  int stops = 0;
  @override
  Future<void> playStream({required String streamUrl, String title = 'Test', String? imageUrl}) async {
    if (!playing.isCompleted) playing.complete();
    if (playGate != null) await playGate!.future;
  }
  @override
  Future<void> stop() async { stops++; if (stopGate != null) await stopGate!.future; }
  @override
  Future<void> pause() async { if (pauseGate != null) await pauseGate!.future; }
  @override
  Future<void> resume() async {}
}
CastDevice _device(String id) => CastDevice(id: id, name: id, kind: CastDeviceKind.roku,
  host: '192.0.2.1', port: 8060, controlUrl: 'http://192.0.2.1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Transport first;
  late _Transport second;
  late CastManager manager;
  setUp(() {
    first = _Transport(); second = _Transport();
    manager = CastManager.forTesting(
      transportFactory: (d) => d.id == 'first' ? first : second,
      probe: (url) async => StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
      timeout: const Duration(milliseconds: 150),
    );
  });
  tearDown(() async { await manager.disconnect(); manager.dispose(); });
  Future<void> cast(String id) => manager.castTo(_device(id), streamUrl: 'http://stream.invalid/live.ts', title: id);

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
  test('ancien stop lent ne nettoie pas le nouveau récepteur', () async {
    await cast('first');
    first.stopGate = Completer<void>();
    final Future<void> stopping = manager.disconnect();
    await cast('second');
    first.stopGate!.complete();
    await stopping;
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
}
