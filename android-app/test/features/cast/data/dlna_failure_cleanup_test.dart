import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/data/upnp_av_transport.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

class _RejectingDlna extends UpnpAvTransport {
  _RejectingDlna(super.device);
  final List<String> urls = <String>[];
  int stops = 0;

  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'Test',
      String? imageUrl,
      bool assumeSuccessWhenUnknown = true}) async {
    urls.add(streamUrl);
    throw Exception('Le récepteur refuse ce format');
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

class _LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('échec total DLNA ferme relais et média avant de rendre le flux local',
      () async {
    await HttpOverrides.runWithHttpOverrides<Future<void>>(() async {
      const device = CastDevice(
          id: 'dlna-failure-fixture',
          name: 'TV test',
          kind: CastDeviceKind.dlna,
          host: '127.0.0.1',
          port: 8060,
          controlUrl: 'http://127.0.0.1/AVTransport/control');
      final receiver = _RejectingDlna(device);
      final manager = CastManager.forTesting(
        transportFactory: (_) => receiver,
        probe: (url) async => StreamProbeResult(
            originalUrl: url, finalUrl: url, success: true, mime: 'video/mp2t'),
        timeout: const Duration(seconds: 3),
      );
      final server = LocalCastServer.instance;
      server.debugLanIpResolver = (_) async => '127.0.0.1';
      int stopsAtError = -1;
      manager.addListener(() {
        if (manager.state == CastState.error) stopsAtError = receiver.stops;
      });
      final transport = MockClient((_) async => http.Response(
          '<Envelope><Body><GetProtocolInfoResponse>'
          '<Sink>http-get:*:video/mp2t:*</Sink>'
          '</GetProtocolInfoResponse></Body></Envelope>',
          200));
      final client = HttpClient();
      try {
        await expectLater(
            http.runWithClient(
                () => manager.castTo(device,
                    streamUrl: 'http://fixture.invalid/live/u/p/1.ts',
                    title: 'Journal'),
                () => transport),
            throwsException);
        expect(manager.state, CastState.error);
        expect(stopsAtError, 1,
            reason: 'la reprise locale ne doit pas précéder Stop distant');
        final relays = receiver.urls
            .where((url) => Uri.parse(url).path.startsWith('/relay/'))
            .toSet();
        expect(relays, isNotEmpty,
            reason: 'le test doit avoir traversé les vraies stratégies relais');
        for (final relay in relays) {
          final request = await client.openUrl('HEAD', Uri.parse(relay));
          final response = await request.close();
          expect(response.statusCode, HttpStatus.notFound,
              reason:
                  'aucun relais de la session en échec ne reste accessible');
          await response.drain<void>();
        }
      } finally {
        client.close(force: true);
        transport.close();
        await manager.disconnect();
        manager.dispose();
        await server.stop();
        server.debugLanIpResolver = null;
      }
    }, _LoopbackHttpOverrides());
  });
}
