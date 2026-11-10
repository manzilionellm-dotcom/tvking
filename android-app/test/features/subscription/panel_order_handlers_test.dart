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
import 'package:tv_king/features/country_home/data/featured_repository.dart';
import 'package:tv_king/features/simple_home/data/home_layout_repository.dart';
import 'package:tv_king/features/pricing/data/pricing_repository.dart';
import 'package:tv_king/features/playlists/data/default_servers.dart';
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';
import 'package:tv_king/features/subscription/data/box_signal_client.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/signal_inbox.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';
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
    PricingRepository.resetForTesting();
    DefaultServersApi.resetForTesting();
    StartupAdRepository.instance.resetForTesting();
  });

  tearDown(() {
    RemoteActivationWatch.instance.stopForTesting();
    AnnouncementRepository.resetForTesting();
    PricingRepository.resetForTesting();
    DefaultServersApi.resetForTesting();
    StartupAdRepository.instance.resetForTesting();
    SignalInbox.instance.resetForTesting();
    RepairFlags.orderAckOff = false;
    AppPlatform.isTv = previousTv;
    AppPlatform.isZuno = previousZuno;
    messenger.setMockMethodCallHandler(_device, null);
  });

  test(
      'statut occupé : APPLIED exige une lecture réellement postérieure à l’ordre',
      () async {
    final id = ++nextOrder;
    final oldStarted = Completer<void>();
    final newStarted = Completer<void>();
    final received = Completer<void>();
    final finished = Completer<void>();
    final oldResponse = Completer<http.Response>();
    final newResponse = Completer<http.Response>();
    final states = <String>[];
    int reads = 0;
    String status(bool frozen) => jsonEncode(<String, Object>{
          'exists': true,
          'status': frozen ? 'frozen' : 'active',
          'paid': true,
          'plan': 'lifetime',
          'expired': false,
          'frozen': frozen,
          'banned': false,
          'source_rev': 0,
        });
    await http.runWithClient(() async {
      final beforeOrder = SubscriptionState.instance.refreshRemote();
      await oldStarted.future.timeout(const Duration(seconds: 2));
      final processing = RemoteActivationWatch.instance.applyOrdersForTesting([
        BoxOrder(
            id: id, kind: 'resume', fleet: false, orderId: 'fresh_status_$id'),
      ]);
      await received.future.timeout(const Duration(seconds: 2));
      expect(states, ['received']);
      expect(SignalInbox.instance.appliedKinds, isEmpty);
      oldResponse.complete(http.Response(status(true), 200));
      await beforeOrder;
      await newStarted.future.timeout(const Duration(seconds: 2));
      expect(states, ['received'],
          reason: 'La réponse partie avant l’ordre est insuffisante.');
      expect(SubscriptionState.instance.remote.frozen, isTrue);
      newResponse.complete(http.Response(status(false), 200));
      expect(await processing, isTrue);
      await finished.future.timeout(const Duration(seconds: 2));
      expect(states, ['received', 'applied']);
      expect(SubscriptionState.instance.remote.frozen, isFalse);
      expect(SignalInbox.instance.appliedKinds, ['resume']);
      expect(reads, 2);
    },
        () => MockClient((request) async {
              if (request.method == 'POST' &&
                  request.url.path.startsWith('/api/box/ack/')) {
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                final ack =
                    (body['orders'] as List).single as Map<String, dynamic>;
                states.add(ack['state'] as String);
                if (ack['state'] == 'received') {
                  received.complete();
                } else {
                  finished.complete();
                }
                return http.Response('{"ok":true}', 200);
              }
              expect(request.url.path, '/api/status/$_mac');
              reads++;
              if (reads == 1) {
                oldStarted.complete();
                return oldResponse.future;
              }
              newStarted.complete();
              return newResponse.future;
            }));
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

  // Ces lectures UI partent avant l'ordre. Leurs anciennes réponses ne doivent
  // donc pas suffire à l'ACK, même lorsqu'elles sont parfaitement valides.
  const freshness = <String, (String, String, String)>{
    'message': (
      '/api/announcement',
      '{"id":72,"title":"old","body":"Texte"}',
      '{"id":73,"title":"new","body":"Texte"}'
    ),
    'home': (
      '/api/home-layout',
      '{"items":[{"key":"recent","ribbon":"old"}]}',
      '{"items":[{"key":"recent","ribbon":"new"}]}'
    ),
    'featured': (
      '/api/featured',
      '{"name":"old","note":""}',
      '{"name":"new","note":""}'
    ),
    'pricing': (
      '/api/pricing',
      '{"configured":true,"currency":"EUR","lifetime":"10"}',
      '{"configured":true,"currency":"EUR","lifetime":"20"}'
    ),
    'servers': (
      '/api/servers',
      '{"servers":[{"id":"1","label":"old","url":"https://old.invalid"}]}',
      '{"servers":[{"id":"1","label":"new","url":"https://new.invalid"}]}'
    ),
  };

  Future<void> uiRead(String kind) async {
    switch (kind) {
      case 'message':
        await AnnouncementRepository.fetchLatest();
      case 'home':
        await HomeLayoutRepository.instance.refresh();
      case 'featured':
        await FeaturedRepository.instance.refresh();
      case 'pricing':
        await PricingRepository.fetch();
      case 'servers':
        await DefaultServersApi.fetch(forceRefresh: true);
    }
  }

  String currentValue(String kind) => switch (kind) {
        'message' => AnnouncementRepository.latest.value!.title,
        'home' => HomeLayoutRepository.instance.config('recent')!.ribbon,
        'featured' => FeaturedRepository.instance.name,
        'pricing' => PricingRepository.current.lifetime,
        'servers' => DefaultServersApi.current.value.single.label,
        _ => throw StateError('type de recette inconnu'),
      };

  for (final entry in freshness.entries) {
    for (final status in [200, 503]) {
      test('${entry.key} : ACK attend la lecture post-ordre HTTP $status',
          () async {
        final id = ++nextOrder;
        final oldStarted = Completer<void>();
        final newStarted = Completer<void>();
        final received = Completer<void>();
        final finished = Completer<void>();
        final oldResponse = Completer<http.Response>();
        final newResponse = Completer<http.Response>();
        final states = <String>[];
        int reads = 0;
        await http.runWithClient(() async {
          final ui = uiRead(entry.key);
          await oldStarted.future.timeout(const Duration(seconds: 2));
          final processing =
              RemoteActivationWatch.instance.applyOrdersForTesting([
            BoxOrder(
                id: id,
                kind: entry.key,
                fleet: false,
                orderId: 'fresh_order_$id',
                traceId: 'fresh_trace_$id'),
          ]);
          await received.future.timeout(const Duration(seconds: 2));
          expect(states, ['received']);
          oldResponse.complete(http.Response(entry.value.$2, 200));
          await ui;
          await newStarted.future.timeout(const Duration(seconds: 2));
          expect(reads, 2);
          expect(states, ['received']);
          expect(SignalInbox.instance.appliedKinds, isEmpty);
          expect(
              currentValue(entry.key), entry.key == 'pricing' ? '10' : 'old');
          newResponse.complete(http.Response(
              status == 200 ? entry.value.$3 : '{"error":"unavailable"}',
              status));
          expect(await processing, isTrue);
          await finished.future.timeout(const Duration(seconds: 2));
          expect(states, ['received', status == 200 ? 'applied' : 'failed']);
          expect(
              currentValue(entry.key),
              status == 200
                  ? (entry.key == 'pricing' ? '20' : 'new')
                  : (entry.key == 'pricing' ? '10' : 'old'));
        },
            () => MockClient((request) async {
                  if (request.method == 'POST' &&
                      request.url.path ==
                          '/api/box/ack/${Uri.encodeComponent(_mac)}') {
                    final body =
                        jsonDecode(request.body) as Map<String, dynamic>;
                    final ack =
                        (body['orders'] as List).single as Map<String, dynamic>;
                    states.add(ack['state'] as String);
                    if (ack['state'] == 'received') {
                      received.complete();
                    } else {
                      finished.complete();
                    }
                    return http.Response('{"ok":true}', 200);
                  }
                  expect(request.method, 'GET');
                  expect(request.url.path, entry.value.$1);
                  reads++;
                  if (reads == 1) {
                    oldStarted.complete();
                    return oldResponse.future;
                  }
                  expect(reads, 2);
                  newStarted.complete();
                  return newResponse.future;
                }));
      });
    }
  }
}
