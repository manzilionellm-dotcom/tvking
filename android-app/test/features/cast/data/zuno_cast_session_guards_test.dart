import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/cast_url_resolver.dart';
import 'package:tv_king/features/cast/data/google_cast_transport.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/player/domain/live_fallback.dart';

class _Transport implements CastTransport {
  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'Test',
      String? imageUrl}) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
}

const _device = CastDevice(
    id: 'test',
    name: 'TV',
    kind: CastDeviceKind.roku,
    host: '192.0.2.1',
    port: 8060,
    controlUrl: 'http://192.0.2.1');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('ouvrir et fermer la découverte préserve une lecture distante active',
      () async {
    final manager = CastManager.forTesting(
      transportFactory: (_) => _Transport(),
      probe: (url) async =>
          StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
    );
    try {
      await manager.castTo(_device,
          streamUrl: 'https://fixture.invalid/live.ts', title: 'Direct');
      await manager.startDiscovery();
      expect(manager.isDiscovering, isTrue);
      expect(manager.isCasting, isTrue);
      expect(manager.hasActiveSession, isTrue);
      manager.stopDiscovery();
      expect(manager.state, CastState.casting);
      expect(manager.currentTitle, 'Direct');
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });
  test('annulation pendant réponse SDK interdit picker et LOAD tardifs',
      () async {
    const channel = MethodChannel('com.manzilionellm.tvking/cast');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final entered = Completer<void>();
    final reply = Completer<bool>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'isCastAvailable') {
        entered.complete();
        return reply.future;
      }
      return true;
    });
    bool current = true;
    final transport = GoogleCastTransport(CastDevice(
        id: 'cast',
        name: 'TV',
        kind: CastDeviceKind.googleCast,
        host: '192.0.2.1',
        port: 8009,
        controlUrl: ''))
      ..sessionIsCurrent = () => current;
    try {
      final operation =
          transport.playStream(streamUrl: 'https://fixture.invalid/video.mp4');
      final rejected = expectLater(operation, throwsException);
      await entered.future;
      current = false;
      reply.complete(true);
      await rejected;
      expect(calls, ['isCastAvailable']);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  test('zap distant réutilise le format de flux validé par le lecteur Zuno',
      () async {
    LiveFallback.resetMemory();
    const raw = 'http://fixture.invalid/u/p/123.ts';
    const winner = 'http://fixture.invalid/live/u/p/123.ts';
    LiveFallback.remember(raw, winner);
    try {
      final channel = Channel(
          id: '123',
          name: 'Direct',
          category: 'Info',
          streamUrl: raw,
          isLive: true);
      expect(await CastUrlResolver.resolve(channel), winner);
    } finally {
      LiveFallback.resetMemory();
    }
  });

  test('PLAYING reçu avant réponse LOAD est conservé sans faux timeout',
      () async {
    const channel = MethodChannel('com.manzilionellm.tvking/cast');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'setReceiverApplicationId') return 'ok';
      if (call.method == 'isCastAvailable' || call.method == 'hasActiveSession')
        return true;
      if (call.method == 'loadMedia') {
        final delivered = Completer<void>();
        // L'événement natif précède volontairement la réponse de LOAD.
        // ignore: deprecated_member_use
        await messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(MethodCall(
              'onMediaStateChanged',
              <String, Object>{
                'playerState': 'playing',
                'isPlaying': true,
                'isPaused': false,
                'isBuffering': false,
                'loadId': (call.arguments as Map)['loadId'] as String,
                'contentId': (call.arguments as Map)['streamUrl'] as String,
              },
            )),
            (_) => delivered.complete());
        await delivered.future;
        await Future<void>.delayed(Duration.zero);
        return true;
      }
      return null;
    });
    final transport = GoogleCastTransport(const CastDevice(
        id: 'fast',
        name: 'TV',
        kind: CastDeviceKind.googleCast,
        host: '192.0.2.1',
        port: 8009,
        controlUrl: ''));
    try {
      await transport
          .playStream(streamUrl: 'https://fixture.invalid/video.mp4')
          .timeout(const Duration(seconds: 1));
      expect(calls.where((method) => method == 'loadMedia'), hasLength(1));
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('ancien PLAYING ou LOAD échoué ne valide pas la commande suivante',
      () async {
    const channel = MethodChannel('com.manzilionellm.tvking/cast');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final loads = <Map<Object?, Object?>>[];
    final secondLoad = Completer<void>();
    Future<void> emit(String method, Map<String, Object> payload) async {
      final delivered = Completer<void>();
      // ignore: deprecated_member_use
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall(method, payload)),
          (_) => delivered.complete());
      await delivered.future;
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> playing(String id, String url) =>
        emit('onMediaStateChanged', <String, Object>{
          'playerState': 'playing',
          'isPlaying': true,
          'isPaused': false,
          'isBuffering': false,
          'loadId': id,
          'contentId': url,
        });
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setReceiverApplicationId') return 'ok';
      if (call.method == 'isCastAvailable' || call.method == 'hasActiveSession')
        return true;
      if (call.method == 'loadMedia') {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        loads.add(args);
        if (loads.length == 1) {
          await playing(args['loadId'] as String, args['streamUrl'] as String);
        } else {
          secondLoad.complete();
        }
        return true;
      }
      return null;
    });
    bool owner = true;
    final transport = GoogleCastTransport(const CastDevice(
        id: 'correlation',
        name: 'TV',
        kind: CastDeviceKind.googleCast,
        host: '192.0.2.1',
        port: 8009,
        controlUrl: ''))
      ..sessionIsCurrent = () => owner;
    Future<void>? pending;
    try {
      await transport.playStream(streamUrl: 'https://fixture.invalid/a.mp4');
      bool finished = false;
      Object? failure;
      pending = transport
          .playStream(streamUrl: 'https://fixture.invalid/b.mp4')
          .then<void>((_) => finished = true, onError: (Object e) {
        failure = e;
        finished = true;
      });
      await secondLoad.future;
      final oldId = loads.first['loadId'] as String;
      final currentId = loads.last['loadId'] as String;
      final oldUrl = loads.first['streamUrl'] as String;
      final currentUrl = loads.last['streamUrl'] as String;
      expect(currentId, isNot(oldId));

      await playing(oldId, oldUrl);
      expect(finished, isFalse,
          reason: 'PLAYING déjà envoyé par l’ancien LOAD');
      await playing(currentId, oldUrl);
      expect(finished, isFalse,
          reason: 'le SDK peut encore exposer l’ancien MediaInfo');
      await emit('onSessionEvent', <String, Object>{
        'event': 'load_failed',
        'errorCode': 2100,
        'loadId': oldId,
      });
      expect(finished, isFalse,
          reason: 'réponse tardive d’une commande remplacée');
      await emit('onSessionEvent', <String, Object>{
        'event': 'load_failed',
        'errorCode': 2100,
      });
      expect(finished, isFalse,
          reason: 'une réponse non corrélée ne possède pas le LOAD');

      await playing(currentId, currentUrl);
      await pending.timeout(const Duration(seconds: 1));
      expect(failure, isNull);
      expect(finished, isTrue);
    } finally {
      owner = false;
      if (pending != null) await pending.timeout(const Duration(seconds: 1));
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('échec LOAD corrélé avant sa réponse est remonté immédiatement',
      () async {
    const channel = MethodChannel('com.manzilionellm.tvking/cast');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setReceiverApplicationId') return 'ok';
      if (call.method == 'isCastAvailable' || call.method == 'hasActiveSession')
        return true;
      if (call.method == 'loadMedia') {
        final delivered = Completer<void>();
        // ignore: deprecated_member_use
        await messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(MethodCall(
              'onSessionEvent',
              <String, Object>{
                'event': 'load_failed',
                'errorCode': 2100,
                'loadId': (call.arguments as Map)['loadId'] as String,
              },
            )),
            (_) => delivered.complete());
        await delivered.future;
        await Future<void>.delayed(Duration.zero);
        return true;
      }
      return null;
    });
    final transport = GoogleCastTransport(const CastDevice(
        id: 'failed',
        name: 'TV',
        kind: CastDeviceKind.googleCast,
        host: '192.0.2.1',
        port: 8009,
        controlUrl: ''));
    try {
      await expectLater(
          transport
              .playStream(streamUrl: 'https://fixture.invalid/video.mp4')
              .timeout(const Duration(seconds: 1)),
          throwsA(isA<Exception>()
              .having((e) => '$e', 'code natif', contains('2100'))));
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
