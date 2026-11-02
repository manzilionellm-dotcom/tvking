// Contrat complet signal → vrai dépôt HTTP → accusés envoyés au panel.
// Aucun serveur n'est contacté : le client de zone intercepte aussi les ACK.
// La réponse du réglage reste suspendue pour prouver que « received » n'est
// jamais confondu avec « applied » avant la fin effective du traitement.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/ads/data/startup_ad_repository.dart';
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';
import 'package:tv_king/features/subscription/data/box_signal_client.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/signal_inbox.dart';
import 'package:tv_king/features/theme/data/remote_theme_repository.dart';

const _mac = 'MK:11:22:33:44:55';
const _secret = 'synthetic-fixture-secret-at-least-32-characters';
const _device = MethodChannel('com.manzilionellm.tvking/device');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  int nextOrder = 9000;
  final previousTv = AppPlatform.isTv;
  final previousZuno = AppPlatform.isZuno;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': _mac,
      'device.secret.v1': _secret,
    });
    PackageInfo.setMockInitialValues(
      appName: 'ZUNO',
      packageName: 'com.sevenmotion.zuno.tv',
      version: '1.14.0',
      buildNumber: '114',
      buildSignature: '',
    );
    messenger.setMockMethodCallHandler(_device, (call) async {
      if (call.method == 'getAndroidId') return 'synthetic-order-fixture';
      return null;
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    AppPlatform.configureZuno(isAndroidHandset: true);
    RepairFlags.orderAckOff = false;
    RemoteActivationWatch.instance.stopForTesting();
    SignalInbox.instance.resetForTesting();
    AnnouncementRepository.resetForTesting();
    StartupAdRepository.instance.resetForTesting();
  });

  tearDown(() {
    RemoteActivationWatch.instance.stopForTesting();
    AnnouncementRepository.resetForTesting();
    StartupAdRepository.instance.resetForTesting();
    SignalInbox.instance.resetForTesting();
    RepairFlags.orderAckOff = false;
    AppPlatform.isTv = previousTv;
    AppPlatform.isZuno = previousZuno;
    messenger.setMockMethodCallHandler(_device, null);
  });

  const responses = <String, (String, String)>{
    'message': (
      '/api/announcement',
      '{"id":71,"title":"Annonce de recette","body":"Texte reçu","expires_at":0}',
    ),
    'ad': (
      '/api/ad',
      '{"enabled":true,"url":"https://fixture.example.invalid/ad.mp4","skip":4,"freq":"daily"}',
    ),
    'theme': (
      '/api/theme',
      '{"appName":"Salon de recette","accent":"#1E8E4E","bg":"light"}',
    ),
  };

  for (final entry in responses.entries) {
    for (final status in <int>[200, 503]) {
      test(
          '${entry.key} HTTP $status : received puis '
          '${status == 200 ? "applied" : "failed"} par le vrai traitement',
          () async {
        final id = ++nextOrder;
        final orderId = 'ord_fixture_$id';
        final traceId = 'trace_fixture_$id';
        final received = Completer<void>();
        final finished = Completer<void>();
        final response = Completer<http.Response>();
        final acknowledgements = <Map<String, dynamic>>[];
        int configurationReads = 0;
        final previousTheme = RemoteThemeRepository.current.value;

        await http.runWithClient(() async {
          final processing =
              RemoteActivationWatch.instance.applyOrdersForTesting(
            <BoxOrder>[
              BoxOrder(
                id: id,
                kind: entry.key,
                fleet: false,
                orderId: orderId,
                traceId: traceId,
              ),
            ],
          );
          await received.future.timeout(const Duration(seconds: 2));
          expect(acknowledgements.map((ack) => ack['state']),
              <String>['received']);
          expect(SignalInbox.instance.appliedKinds, isEmpty);

          response.complete(http.Response(
            status == 200 ? entry.value.$2 : '{"error":"unavailable"}',
            status,
          ));
          expect(await processing, isTrue);
          // Les ACK sont best-effort et non bloquants dans l'app : on attend
          // ici leur vraie requête, pas un délai arbitraire ou un résultat pur.
          await finished.future.timeout(const Duration(seconds: 2));
        },
            () => MockClient((request) async {
                  if (request.method == 'POST' &&
                      request.url.path ==
                          '/api/box/ack/${Uri.encodeComponent(_mac)}') {
                    expect(request.headers['X-Device-Secret'], _secret);
                    final body =
                        jsonDecode(request.body) as Map<String, dynamic>;
                    final orders =
                        (body['orders'] as List).cast<Map<String, dynamic>>();
                    expect(orders, hasLength(1));
                    acknowledgements.add(orders.single);
                    if (orders.single['state'] == 'received') {
                      received.complete();
                    } else {
                      finished.complete();
                    }
                    return http.Response('{"ok":true}', 200);
                  }
                  expect(request.method, 'GET');
                  expect(request.url.path, entry.value.$1);
                  if (entry.key == 'theme') {
                    expect(request.url.queryParameters['platform'], 'tv');
                  }
                  configurationReads++;
                  return response.future;
                }));

        expect(configurationReads, 1);
        expect(acknowledgements, hasLength(2));
        final finalAck = acknowledgements.last;
        for (final ack in acknowledgements) {
          expect(ack['order_id'], orderId);
          expect(ack['trace_id'], traceId);
          expect(ack['app_version'], '1.14.0');
          expect(ack['received_at'], isA<int>());
        }
        expect(finalAck['applied_at'],
            greaterThanOrEqualTo(finalAck['received_at'] as int));
        if (status == 200) {
          expect(finalAck['state'], 'applied');
          expect(finalAck['result'], 'refreshed');
          expect(finalAck.containsKey('error_code'), isFalse);
          expect(SignalInbox.instance.appliedKinds, <String>[entry.key]);
          if (entry.key == 'message') {
            expect(AnnouncementRepository.latest.value?.title,
                'Annonce de recette');
          } else if (entry.key == 'ad') {
            expect(StartupAdRepository.instance.config.enabled, isTrue);
            expect(StartupAdRepository.instance.config.skip, 4);
          } else {
            expect(RemoteThemeRepository.current.value.appName,
                'Salon de recette');
          }
        } else {
          expect(finalAck['state'], 'failed');
          expect(finalAck['result'], 'side_effect_failed');
          expect(finalAck['error_code'], 'side_effect_failed');
          expect(SignalInbox.instance.appliedKinds, isEmpty);
          expect(AnnouncementRepository.latest.value, isNull);
          expect(StartupAdRepository.instance.config.enabled, isFalse);
          expect(RemoteThemeRepository.current.value, previousTheme);
        }
      });
    }
  }
}
