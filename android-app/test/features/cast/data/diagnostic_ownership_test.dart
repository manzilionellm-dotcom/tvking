import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_diagnostics.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';

class _Transport implements CastTransport {
  final Completer<void> entered = Completer<void>();
  final Completer<void> playGate = Completer<void>();
  int plays = 0;
  int stops = 0;
  bool hold = true;
  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'Test',
      String? imageUrl}) async {
    plays++;
    if (!entered.isCompleted) entered.complete();
    if (hold) await playGate.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
}

CastDevice _device(String id) => CastDevice(
    id: id,
    name: id,
    kind: CastDeviceKind.roku,
    host: '192.0.2.1',
    port: 8060,
    controlUrl: 'http://192.0.2.1');

Channel _channel(String id, {int list = 1, String? name}) => Channel(
    id: id,
    name: name ?? id,
    category: 'Actualités',
    playlistId: list,
    streamUrl: 'https://fixture.invalid/$id.ts',
    isLive: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CastManager manager;
  late _Transport first;
  late _Transport second;
  late DiagnosticBatchRunner runner;
  setUp(() {
    ActiveProfile.instance.set(ProfileIds.origin, playlistIds: <int>[1]);
    first = _Transport();
    second = _Transport()..hold = false;
    manager = CastManager.forTesting(
      transportFactory: (device) => device.id == 'first' ? first : second,
      probe: (url) async =>
          StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
      timeout: const Duration(seconds: 2),
    );
    runner = DiagnosticBatchRunner(
        device: _device('first'),
        channels: <Channel>[_channel('a'), _channel('b')],
        manager: manager,
        interTestPause: Duration.zero);
  });
  tearDown(() async {
    if (!first.playGate.isCompleted) first.playGate.complete();
    runner.dispose();
    await manager.disconnect();
    manager.dispose();
    ActiveProfile.instance.set(ProfileIds.origin);
  });

  test('échantillon exclut adulte et chaînes des autres profils', () {
    final selected = pickDiagnosticChannels(<Channel>[
      _channel('ordinary'),
      _channel('foreign', list: 2),
      _channel('adult', name: 'XXX'),
    ], 3);
    expect(selected.map((channel) => channel.id), <String>['ordinary']);
  });

  test('annuler le diagnostic stoppe immédiatement sa tentative', () async {
    final pending = runner.run();
    await first.entered.future;
    runner.cancel();
    expect(first.stops, 1);
    expect(manager.hasActiveSession, isFalse);
    first.playGate.complete();
    await pending;
    expect(first.plays, 1);
    expect(runner.isRunning, isFalse);
  });

  test('diagnostic périmé ne déconnecte pas une sélection plus récente',
      () async {
    final pending = runner.run();
    await first.entered.future;
    await manager.castTo(_device('second'),
        streamUrl: _channel('new').streamUrl, title: 'new');
    runner.cancel();
    first.playGate.complete();
    await pending;
    expect(second.stops, 0);
    expect(manager.device?.id, 'second');
    expect(manager.state, CastState.casting);
  });

  test('changer de profil interrompt le lot et interdit le test suivant',
      () async {
    final pending = runner.run();
    await first.entered.future;
    ActiveProfile.instance.set('other', playlistIds: <int>[2]);
    first.playGate.complete();
    await pending;
    expect(runner.isCancelled, isTrue);
    expect(first.plays, 1);
    expect(manager.hasTarget, isFalse);
  });
}
