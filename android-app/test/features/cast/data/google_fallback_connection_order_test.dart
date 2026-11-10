import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/google_cast_transport.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

import 'ts_hls_segmenter_test.dart' show kPmtPid, pmtPacket, syntheticStream;

const _native = MethodChannel('com.manzilionellm.tvking/cast');

/// Les commandes Cast sont doublées, mais les sondes et le relais utilisent
/// leurs vrais clients HTTP. Tous les hôtes externes aboutissent à la fixture
/// loopback ; les événements open/close sont pris à la frontière du socket.
class _Network extends HttpOverrides {
  _Network(this.fixture);
  final _Fixture fixture;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _Client(super.createHttpClient(context), fixture);
}

class _Client implements HttpClient {
  _Client(this.inner, this.fixture);
  final HttpClient inner;
  final _Fixture fixture;
  bool supplierTs = false;
  bool closed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    if (url.host == fixture.providerHost) {
      if (url.path.endsWith('.ts')) {
        supplierTs = true;
        fixture.events.add('supplier.ts.open');
      } else if (url.path.endsWith('.m3u8')) {
        fixture.events.add('supplier.hls.open');
      }
    }
    final target = url.host == '127.0.0.1'
        ? url
        : url.replace(
            scheme: 'http', host: '127.0.0.1', port: fixture.server.port);
    return inner.getUrl(target);
  }

  @override
  void close({bool force = false}) {
    if (supplierTs && !closed) fixture.events.add('supplier.ts.close');
    closed = true;
    inner.close(force: force);
  }

  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  set idleTimeout(Duration value) => inner.idleTimeout = value;
  @override
  set userAgent(String? value) => inner.userAgent = value;
  @override
  set autoUncompress(bool value) => inner.autoUncompress = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fixture {
  _Fixture(this.server, this.providerHost, {this.dolby = false});
  final HttpServer server;
  final String providerHost;
  final bool dolby;
  final events = <String>[];
  final hold = Completer<void>();
  String get upstream => 'http://$providerHost/live/user/password/1.ts';
  int get tsOpens => events.where((e) => e == 'supplier.ts.open').length;
  int get hlsOpens => events.where((e) => e == 'supplier.hls.open').length;

  static Future<_Fixture> create(String id, {bool dolby = false}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _Fixture(server, '$id.fixture.invalid', dolby: dolby);
    server.listen(fixture.serve);
    return fixture;
  }

  Future<void> serve(HttpRequest request) async {
    try {
      if (request.uri.path == '/cast-sign') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, Object>{
          'ok': true,
          'url': 'http://127.0.0.1:${server.port}/proxy.ts',
        }));
      } else if (request.uri.path == '/proxy.ts') {
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.add(List<int>.filled(32768, 1));
      } else if (request.uri.path.endsWith('.m3u8')) {
        request.response.headers.set('Content-Type', 'application/x-mpegURL');
        request.response.write('#EXTM3U\n#EXTINF:3,\n1.ts\n');
      } else {
        final bytes = syntheticStream(seconds: 10.0);
        if (dolby) {
          for (int offset = 0; offset < bytes.length; offset += 188) {
            final pid = ((bytes[offset + 1] & 0x1f) << 8) | bytes[offset + 2];
            if (pid == kPmtPid) {
              bytes.setRange(offset, offset + 188,
                  pmtPacket(cc: bytes[offset + 3] & 0x0f, audioType: 0x81));
            }
          }
        }
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.bufferOutput = false;
        request.response.add(bytes);
        await request.response.flush();
        await hold.future;
      }
      await request.response.close();
    } catch (_) {
      // Fermeture du vrai client fournisseur attendue au changement de flux.
    }
  }

  Future<void> dispose() async {
    await LocalCastServer.instance.stop();
    if (!hold.isCompleted) hold.complete();
    await server.close(force: true);
  }
}

CastDevice _device({bool exo = false}) => CastDevice(
    id: exo ? 'shield' : 'chromecast',
    name: exo ? 'NVIDIA SHIELD' : 'Chromecast',
    kind: CastDeviceKind.googleCast,
    host: '127.0.0.1',
    port: 8009,
    controlUrl: '');

Future<void> _emit(String method, Map<String, Object> values) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final delivered = Completer<void>();
  // ignore: deprecated_member_use
  await messenger.handlePlatformMessage(
      _native.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, values)),
      (_) => delivered.complete());
  await delivered.future;
  await Future<void>.delayed(Duration.zero);
}

Future<void> _failed(Map args) => _emit('onSessionEvent', <String, Object>{
      'event': 'load_failed',
      'errorCode': 2100,
      'loadId': args['loadId'] as String,
    });

Future<void> _playing(Map args) =>
    _emit('onMediaStateChanged', <String, Object>{
      'playerState': 'playing',
      'isPlaying': true,
      'isPaused': false,
      'isBuffering': false,
      'loadId': args['loadId'] as String,
      'contentId': args['streamUrl'] as String,
    });

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline))
      throw StateError('Condition non atteinte');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    await LocalCastServer.instance.stop();
    LocalCastServer.instance.debugLanIpResolver = (_) async => '127.0.0.1';
  });
  tearDown(() async {
    await LocalCastServer.instance.stop();
    LocalCastServer.instance.debugLanIpResolver = null;
    messenger.setMockMethodCallHandler(_native, null);
  });

  for (final exo in <bool>[false, true]) {
    test(
        'custom échoué : fermeture effective avant ${exo ? 'présonde directe' : 'relais'}',
        () async {
      final fixture =
          await _Fixture.create('custom-${exo ? 'direct' : 'relay'}');
      await HttpOverrides.runWithHttpOverrides(() async {
        bool owner = true;
        bool closed = false;
        bool switching = false;
        final checkedOldReceiver = Completer<void>();
        final transport = GoogleCastTransport(_device(exo: exo))
          ..sessionIsCurrent = () => owner;
        messenger.setMockMethodCallHandler(_native, (call) async {
          if (call.method == 'isCastAvailable' ||
              call.method == 'hasActiveSession') return true;
          if (call.method == 'setReceiverApplicationId') {
            final id = (call.arguments as Map)['appId'];
            if (id == kCastDefaultReceiverAppId) {
              switching = true;
              return 'switching';
            }
            return 'ok';
          }
          if (call.method == 'currentReceiverApplicationId') {
            if (!checkedOldReceiver.isCompleted) checkedOldReceiver.complete();
            if (!closed) return null;
            fixture.events.add('receiver.default.ready');
            return kCastDefaultReceiverAppId;
          }
          if (call.method == 'loadMedia') {
            final args = call.arguments as Map;
            if (!switching) {
              await _failed(args);
            } else {
              if (!exo) await _until(() => fixture.tsOpens == 1);
              await _playing(args);
            }
            return true;
          }
          return null;
        });
        final pending = transport.playStream(streamUrl: fixture.upstream);
        unawaited(pending.catchError((Object _) {}));
        try {
          await checkedOldReceiver.future.timeout(const Duration(seconds: 3));
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(fixture.tsOpens, 0);
          expect(fixture.hlsOpens, 0,
              reason:
                  'setReceiver a répondu, mais l’ancienne application reste active');
          closed = true;
          await pending.timeout(const Duration(seconds: 3));
          final open = exo ? 'supplier.hls.open' : 'supplier.ts.open';
          expect(fixture.events.indexOf('receiver.default.ready'),
              lessThan(fixture.events.indexOf(open)));
        } finally {
          owner = false;
          closed = true;
          await pending
              .catchError((Object _) {})
              .timeout(const Duration(seconds: 2), onTimeout: () {});
          await fixture.dispose();
        }
      }, _Network(fixture));
    });
  }

  for (final refuse in <bool>[false, true]) {
    test(
        'direct échoué : ${refuse ? 'STOP refusé interdit le relais' : 'relais attend ACK STOP'}',
        () async {
      final fixture =
          await _Fixture.create('direct-${refuse ? 'refused' : 'ack'}');
      CastProxyVerdictMemo.instance
          .remember(fixture.providerHost, blocked: true);
      await HttpOverrides.runWithHttpOverrides(() async {
        bool owner = true;
        final stopped = Completer<void>();
        final ack = Completer<void>();
        final transport = GoogleCastTransport(_device(exo: true))
          ..sessionIsCurrent = () => owner;
        int loads = 0;
        messenger.setMockMethodCallHandler(_native, (call) async {
          if (call.method == 'isCastAvailable' ||
              call.method == 'hasActiveSession') return true;
          if (call.method == 'setReceiverApplicationId') return 'ok';
          if (call.method == 'loadMedia') {
            final args = call.arguments as Map;
            if (++loads == 1) {
              await _failed(args);
            } else {
              await _until(() => fixture.tsOpens == 1);
              await _playing(args);
            }
            return true;
          }
          if (call.method == 'stop') {
            stopped.complete();
            await ack.future;
            if (refuse) throw PlatformException(code: 'STOP_FAILED');
            fixture.events.add('stop.ack');
          }
          return null;
        });
        final pending = transport.playStream(streamUrl: fixture.upstream);
        unawaited(pending.catchError((Object _) {}));
        try {
          await stopped.future.timeout(const Duration(seconds: 3));
          expect(fixture.hlsOpens, 1, reason: 'seulement la présonde initiale');
          expect(fixture.tsOpens, 0);
          ack.complete();
          if (refuse) {
            await expectLater(pending, throwsA(isA<PlatformException>()));
            expect(fixture.tsOpens, 0);
            expect(loads, 1);
            expect(transport.lastRelayUrl, isNull);
          } else {
            await pending.timeout(const Duration(seconds: 3));
            expect(fixture.events.indexOf('stop.ack'),
                lessThan(fixture.events.indexOf('supplier.ts.open')));
          }
        } finally {
          owner = false;
          if (!ack.isCompleted) ack.complete();
          await pending
              .catchError((Object _) {})
              .timeout(const Duration(seconds: 2), onTimeout: () {});
          await fixture.dispose();
        }
      }, _Network(fixture));
    });
  }

  test('sauvetage AC3 : ferme socket relais et attend STOP avant présonde HLS',
      () async {
    final fixture = await _Fixture.create('audio-rescue', dolby: true);
    CastProxyVerdictMemo.instance.remember(fixture.providerHost, blocked: true);
    CastProxyVerdictMemo.directTv.remember(fixture.providerHost, blocked: true);
    await HttpOverrides.runWithHttpOverrides(() async {
      bool owner = true;
      final stopped = Completer<void>();
      final ack = Completer<void>();
      final transport = GoogleCastTransport(_device(exo: true))
        ..sessionIsCurrent = () => owner;
      int loads = 0;
      messenger.setMockMethodCallHandler(_native, (call) async {
        if (call.method == 'isCastAvailable' ||
            call.method == 'hasActiveSession') return true;
        if (call.method == 'setReceiverApplicationId') return 'ok';
        if (call.method == 'loadMedia') {
          final args = call.arguments as Map;
          if (++loads == 1) {
            final url = args['streamUrl'] as String;
            await _until(
                () => LocalCastServer.instance.hlsAudioCodecFor(url) == 'ac3');
            await _failed(args);
          } else {
            await _playing(args);
          }
          return true;
        }
        if (call.method == 'stop') {
          stopped.complete();
          await ack.future;
          fixture.events.add('stop.ack');
        }
        return null;
      });
      final pending = transport.playStream(streamUrl: fixture.upstream);
      unawaited(pending.catchError((Object _) {}));
      try {
        await stopped.future.timeout(const Duration(seconds: 3));
        expect(fixture.events, contains('supplier.ts.close'));
        expect(fixture.hlsOpens, 0);
        expect(transport.lastRelayUrl, isNull);
        ack.complete();
        await pending.timeout(const Duration(seconds: 3));
        expect(fixture.events.indexOf('supplier.ts.close'),
            lessThan(fixture.events.indexOf('supplier.hls.open')));
        expect(fixture.events.indexOf('stop.ack'),
            lessThan(fixture.events.indexOf('supplier.hls.open')));
        expect(loads, 2);
      } finally {
        owner = false;
        if (!ack.isCompleted) ack.complete();
        await pending
            .catchError((Object _) {})
            .timeout(const Duration(seconds: 2), onTimeout: () {});
        await fixture.dispose();
      }
    }, _Network(fixture));
  });
}
