import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/google_cast_api.dart';
import 'package:tv_king/features/cast/data/google_cast_transport.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';

class _Transport implements CastTransport {
  final List<String> urls = <String>[];
  final Completer<void> entered = Completer<void>();
  Completer<void>? playGate;
  Completer<void>? stopGate;
  int stops = 0;

  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'Test',
      String? imageUrl}) async {
    urls.add(streamUrl);
    if (!entered.isCompleted) entered.complete();
    if (playGate != null) await playGate!.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (stopGate != null) await stopGate!.future;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
}

class _GoogleTransport extends GoogleCastTransport {
  _GoogleTransport(super.device);
  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'Test',
      String? imageUrl}) async {}
}

CastDevice _device(String id, {bool google = false}) => CastDevice(
    id: id,
    name: id,
    kind: google ? CastDeviceKind.googleCast : CastDeviceKind.roku,
    host: '192.0.2.1',
    port: 8060,
    controlUrl: 'http://192.0.2.1');

Channel _channel(String id, {int list = 1, String? name}) => Channel(
    id: id,
    name: name ?? id,
    category: 'Actualités',
    playlistId: list,
    streamUrl: 'https://fixture.invalid/$list/$id.ts',
    isLive: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel native = MethodChannel('com.manzilionellm.tvking/cast');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Transport first;
  late _Transport second;
  late CastManager manager;

  setUp(() {
    ActiveProfile.instance.set(ProfileIds.origin);
    first = _Transport();
    second = _Transport();
    manager = CastManager.forTesting(
      transportFactory: (device) => device.id == 'first' ? first : second,
      probe: (url) async =>
          StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
    );
  });
  tearDown(() async {
    if (first.stopGate?.isCompleted == false) first.stopGate!.complete();
    if (second.stopGate?.isCompleted == false) second.stopGate!.complete();
    if (first.playGate?.isCompleted == false) first.playGate!.complete();
    if (second.playGate?.isCompleted == false) second.playGate!.complete();
    await manager.disconnect();
    manager.dispose();
    ActiveProfile.instance.set(ProfileIds.origin);
    messenger.setMockMethodCallHandler(native, null);
  });

  Future<void> castFirst() => manager.castTo(_device('first'),
      streamUrl: _channel('a').streamUrl, title: 'a');

  test('playlist distante filtre profil et adultes, identité inclut la liste',
      () {
    ActiveProfile.instance.set(ProfileIds.origin, playlistIds: <int>[1, 2]);
    final a = _channel('same', list: 1);
    final b = _channel('same', list: 2);
    manager.setCastPlaylist(<Channel>[
      a,
      b,
      _channel('foreign', list: 3),
      _channel('adult', name: 'XXX')
    ], b);
    expect(manager.currentCastChannel, same(b));
    manager.setCastPlaylist(<Channel>[a, _channel('adult', name: 'XXX')],
        _channel('adult', name: 'XXX'));
    expect(manager.currentCastChannel, isNull);
  });

  test('un appel brut Adultes sans droit ne lance aucun transport', () async {
    await manager.castTo(_device('first'),
        streamUrl: _channel('x').streamUrl,
        title: 'XXX',
        channelGenre: 'Adultes');
    expect(first.urls, isEmpty);
    expect(manager.hasActiveSession, isFalse);
  });

  test('deux zaps avant résolution jouent seulement la dernière sélection',
      () async {
    final channels = <Channel>[_channel('a'), _channel('b'), _channel('c')];
    await castFirst();
    manager.setCastPlaylist(channels, channels.first);
    final one = manager.zapCastNext();
    final two = manager.zapCastNext();
    await Future.wait(<Future<void>>[one, two]);
    expect(first.urls,
        <String>[channels.first.streamUrl, channels.last.streamUrl]);
    expect(manager.currentCastChannel, same(channels.last));
  });

  test('changement de profil pendant connexion ne ressuscite pas ancien flux',
      () async {
    first.playGate = Completer<void>();
    final pending = castFirst();
    await first.entered.future;
    ActiveProfile.instance.set('other', playlistIds: <int>[2]);
    first.playGate!.complete();
    await pending;
    expect(first.stops, 1);
    expect(manager.hasActiveSession, isFalse);
    expect(manager.hasTarget, isFalse);
    expect(manager.currentCastChannel, isNull);
  });

  test('retrait des listes du même profil ferme la session et la cible',
      () async {
    ActiveProfile.instance.set(ProfileIds.origin, playlistIds: <int>[1]);
    await castFirst();
    manager.setCastPlaylist(
        <Channel>[_channel('a'), _channel('b')], _channel('a'));
    ActiveProfile.instance.set(ProfileIds.origin, playlistIds: <int>[]);
    expect(manager.hasTarget, isFalse);
    expect(manager.currentCastChannel, isNull);
    expect(first.stops, 1);
  });

  test('reprise native inconnue au boot est fermée sans droit local', () async {
    final calls = <String>[];
    final disconnected = Completer<void>();
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call.method);
      if (call.method == 'disconnect') disconnected.complete();
      return null;
    });
    manager.debugNativeSessionEvent(
        const CastNativeSessionEvent('resumed_at_boot'));
    await disconnected.future;
    expect(calls, <String>['stop', 'disconnect']);
    expect(manager.state, CastState.idle);
  });

  test('désélection Google sans transport ne commande pas le SDK', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call.method);
      return null;
    });
    manager.selectDevice(_device('google', google: true));
    await manager.disconnect();
    expect(calls, isEmpty);
    expect(manager.hasTarget, isFalse);
  });

  test('annuler pré-vol Google ne lance ni transport ni Stop natif', () async {
    final entered = Completer<void>();
    final probe = Completer<StreamProbeResult>();
    final calls = <String>[];
    int transports = 0;
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call.method);
      return null;
    });
    final local = CastManager.forTesting(
      transportFactory: (_) {
        transports++;
        return _Transport();
      },
      probe: (url) {
        entered.complete();
        return probe.future;
      },
    );
    const url = 'https://fixture.invalid/video.mp4';
    try {
      final pending = local.castTo(_device('google', google: true),
          streamUrl: url, title: 'Vidéo');
      await entered.future;
      await local.disconnect();
      probe.complete(
          StreamProbeResult(originalUrl: url, finalUrl: url, success: true));
      await pending;
      expect(calls, isEmpty);
      expect(transports, 0);
      expect(local.hasActiveSession, isFalse);
    } finally {
      if (!probe.isCompleted) {
        probe.complete(
            StreamProbeResult(originalUrl: url, finalUrl: url, success: true));
      }
      await local.disconnect();
      local.dispose();
    }
  });

  test('réponse Stop Google tardive ne déconnecte pas nouvelle session',
      () async {
    final entered = Completer<void>();
    final reply = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call.method);
      if (call.method == 'stop') {
        entered.complete();
        await reply.future;
      }
      return null;
    });
    bool owner = true;
    final transport = GoogleCastTransport(_device('google', google: true));
    final stopping = transport.stop(mayDisconnect: () => owner);
    await entered.future;
    owner = false;
    reply.complete();
    await stopping;
    expect(calls, <String>['stop']);
  });

  test('ancien Stop Google ne stoppe pas le nouveau Roku au pré-vol', () async {
    final entered = Completer<void>();
    final reply = Completer<void>();
    int stops = 0;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'stop' && ++stops == 1) {
        entered.complete();
        await reply.future;
      }
      return null;
    });
    final google = _GoogleTransport(_device('google', google: true));
    final active = _Transport();
    final local = CastManager.forTesting(
      transportFactory: (device) => device.id == 'google' ? google : active,
      probe: (url) async =>
          StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
    );
    try {
      await local.castTo(_device('google', google: true),
          streamUrl: _channel('a').streamUrl, title: 'a');
      final old = local.castTo(_device('stale'),
          streamUrl: _channel('b').streamUrl, title: 'b');
      await entered.future;
      await local.castTo(_device('latest'),
          streamUrl: _channel('c').streamUrl, title: 'c');
      reply.complete();
      await old;
      expect(active.stops, 0);
      expect(active.urls, <String>[_channel('c').streamUrl]);
      expect(local.device?.id, 'latest');
    } finally {
      if (!reply.isCompleted) reply.complete();
      await local.disconnect();
      local.dispose();
    }
  });

  test('échec LOAD pendant repli conserve réservation distante connecting',
      () async {
    first.playGate = Completer<void>();
    final pending = manager.castTo(_device('first', google: true),
        streamUrl: _channel('a').streamUrl, title: 'a');
    await first.entered.future;
    manager
        .debugNativeSessionEvent(const CastNativeSessionEvent('load_failed'));
    expect(manager.state, CastState.connecting);
    expect(manager.hasActiveSession, isTrue);
    first.playGate!.complete();
    await pending;
    expect(manager.state, CastState.casting);
  });

  test('changer de TV attend Stop puis transmet média et liste complets',
      () async {
    await castFirst();
    manager.setCastPlaylist(
        <Channel>[_channel('a'), _channel('b')], _channel('a'));
    first.stopGate = Completer<void>();
    final switching = manager.switchDevice(_device('second'));
    expect(second.urls, isEmpty);
    first.stopGate!.complete();
    await switching;
    expect(first.stops, 1);
    expect(second.urls, <String>[_channel('a').streamUrl]);
    expect(manager.device?.id, 'second');
    expect(manager.canZapOnCast, isTrue);
  });

  test('annuler changement de TV pendant Stop ne lance pas nouvelle TV',
      () async {
    await castFirst();
    first.stopGate = Completer<void>();
    bool cancelled = false;
    final switching =
        manager.switchDevice(_device('second'), isCancelled: () => cancelled);
    cancelled = true;
    first.stopGate!.complete();
    await switching;
    expect(second.urls, isEmpty);
    expect(manager.hasTarget, isFalse);
  });
}
