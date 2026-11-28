import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/data/upnp_av_transport.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

void main() {
  test('Le relais utilise le vrai préfixe LAN annoncé par Android', () {
    const links = [
      ['10.1.0.4/16'],
      ['10.1.30.8/23'],
    ];
    expect(vpnRelayAddress('10.1.31.30', links), '10.1.30.8');
    expect(vpnRelayAddress('10.1.45.30', links), '10.1.0.4');
    expect(vpnRelayAddress('televiseur.local', links), isNull);
    expect(vpnRelayAddress('', [links.last]), '10.1.30.8');
    expect(vpnRelayAddress('10.1.31.30', const []), isNull);
    expect(vpnRelayAddress('10.1.31.30', const [['0.0.0.0/0', '::1/128']]), isNull);
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  test('La sonde IPTV et la demande des capacités DLNA se chevauchent', () async {
    const lab = bool.fromEnvironment('NOVATUBE_TV') &&
        bool.fromEnvironment('NOVATUBE_SEVEN_MOTION_CAST');
    if (!lab) return;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('com.sevenmotion.zuno/cast-capability');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'isHandset');
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
      await CastPlatform.initializeZuno();
      HttpOverrides.global = previousHttp;
    });
    await CastPlatform.initializeZuno();
    final renderer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => renderer.close(force: true));
    final requested = Completer<void>();
    renderer.listen((request) async {
      await request.drain<void>();
      if (!requested.isCompleted) requested.complete();
      request.response.write('<GetProtocolInfoResponse><Sink>http-get:*:video/mp2t:*</Sink></GetProtocolInfoResponse>');
      await request.response.close();
    });
    final holdProbe = Completer<StreamProbeResult>();
    final manager = CastManager.forTesting(
      transportFactory: UpnpAvTransport.new,
      timeout: const Duration(seconds: 15),
      probe: (_) => holdProbe.future,
    );
    addTearDown(manager.dispose);
    final receiver = CastDevice(id: 'vpn-test-${renderer.port}', name: 'Test',
        kind: CastDeviceKind.dlna, host: '127.0.0.1', port: renderer.port,
        controlUrl: 'http://127.0.0.1:${renderer.port}/AVTransport');
    const stream = 'http://stream.invalid/programme.ts';
    final cast = expectLater(manager.castTo(receiver, streamUrl: stream, title: 'Test'),
        throwsA(isA<Exception>()));
    try {
      await requested.future.timeout(const Duration(seconds: 5));
      expect(holdProbe.isCompleted, isFalse);
    } finally {
      holdProbe.complete(const StreamProbeResult(
          originalUrl: stream, finalUrl: stream, success: false, errorCode: 403));
      await cast;
    }
  });
}
