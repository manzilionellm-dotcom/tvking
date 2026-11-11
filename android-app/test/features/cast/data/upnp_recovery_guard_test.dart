import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/cast/data/upnp_av_transport.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

const _device = CastDevice(
    id: 'guard',
    name: 'Récepteur de test',
    kind: CastDeviceKind.dlna,
    host: '127.0.0.1',
    port: 8060,
    controlUrl: 'http://127.0.0.1:8060/control');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppPlatform.configureZuno(isAndroidHandset: false);
    RepairFlags.debugReset();
  });
  tearDown(() {
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
  });

  for (final waiting in [
    'Stop',
    'GetTransportInfo',
    'SetAVTransportURI',
    'Play'
  ]) {
    test('révocation pendant $waiting interdit la commande SOAP suivante',
        () async {
      bool current = true;
      String state = 'STOPPED';
      final entered = Completer<void>();
      final release = Completer<void>();
      final actions = <String>[];
      final client = MockClient((request) async {
        final action =
            request.headers['SOAPAction']!.split('#').last.replaceAll('"', '');
        actions.add(action);
        if (action == waiting && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        if (action == 'Play') state = 'PLAYING';
        return http.Response(
            '<Envelope><Body>'
            '<CurrentTransportState>$state</CurrentTransportState>'
            '</Body></Envelope>',
            200);
      });
      await http.runWithClient(() async {
        final operation = UpnpAvTransport(_device).recoverStream(
            streamUrl: 'http://fixture.invalid/live.ts',
            title: 'Journal',
            isCurrent: () => current);
        final rejected =
            expectLater(operation, throwsA(isA<UpnpSessionObsolete>()));
        await entered.future;
        final before = List<String>.of(actions);
        current = false;
        release.complete();
        await rejected;
        expect(actions, before);
      }, () => client);
    });
  }

  test('Stop de nettoyage reste permis après révocation de la session',
      () async {
    final actions = <String>[];
    await http.runWithClient(() async {
      final transport = UpnpAvTransport(_device)
        ..sessionIsCurrent = () => false;
      await transport.stop();
      await expectLater(
          transport.resume(), throwsA(isA<UpnpSessionObsolete>()));
      expect(actions, ['Stop']);
    },
        () => MockClient((request) async {
              actions.add(request.headers['SOAPAction']!
                  .split('#')
                  .last
                  .replaceAll('"', ''));
              return http.Response('<Envelope/>', 200);
            }));
  });

  test('le repli ne peut contourner la garde obligatoire de session', () async {
    RepairFlags.dlnaWatchdogLegacy = true;
    final transport = UpnpAvTransport(_device)..sessionIsCurrent = () => false;
    await expectLater(
        transport.playStream(streamUrl: 'http://fixture.invalid/live.ts'),
        throwsA(isA<UpnpSessionObsolete>()));
  });

  test('7 MOTION ignore le nouveau callback de protection ZUNO', () async {
    AppPlatform.isZuno = false;
    final actions = <String>[];
    String state = 'STOPPED';
    await http.runWithClient(() async {
      final transport = UpnpAvTransport(_device)
        ..sessionIsCurrent = () => false;
      await transport.playStream(streamUrl: 'http://fixture.invalid/live.ts');
      expect(actions.where((action) => action == 'Play'), hasLength(1));
    },
        () => MockClient((request) async {
              final action = request.headers['SOAPAction']!
                  .split('#')
                  .last
                  .replaceAll('"', '');
              actions.add(action);
              if (action == 'Play') state = 'PLAYING';
              return http.Response(
                  '<CurrentTransportState>$state</CurrentTransportState>', 200);
            }));
  });
}
