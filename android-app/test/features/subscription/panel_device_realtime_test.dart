// Vrai HTTP/WebSocket local : les réglages du canal actuellement déployé
// atteignent les dépôts ZUNO TV et Mobile, sans inventer un accusé d'ordre.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/build_info.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/subscription/data/device_realtime_channel.dart';
import 'package:tv_king/features/subscription/data/remote_activation_watch.dart';
import 'package:tv_king/features/subscription/data/signal_inbox.dart';
import 'package:tv_king/features/theme/data/remote_theme_repository.dart';

const _run = bool.fromEnvironment('RUN_PANEL_CONNECTION');
const _mac = 'MK:11:22:33:44:88';
const _key = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _ticket = '12345678-1234-4123-8123-123456789abc';

class _RealHttp extends HttpOverrides {}

Future<void> _until(bool Function() ready, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final handset in <bool>[false, true]) {
    test(
        'canal actuel : vrais réglages ${handset ? 'mobile' : 'TV'} sous une seconde locale',
        () async {
      final previousHttp = HttpOverrides.current;
      final previousTv = AppPlatform.isTv;
      final previousZuno = AppPlatform.isZuno;
      HttpOverrides.global = _RealHttp();
      AppPlatform.configureZuno(isAndroidHandset: handset);
      FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
      RepairFlags.debugReset();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'device.virtual_mac.v1': _mac,
      });
      SignalInbox.instance.resetForTesting();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18789);
      WebSocket? peer;
      int ackPosts = 0, revision = 100;
      String themeName = 'Initial';
      bool holdAd = false;
      final adStarted = Completer<void>();
      final adGate = Completer<void>();
      final reads = <String, int>{};
      const paths = <String, String>{
        'message': '/api/announcement',
        'theme': '/api/theme',
        'home': '/api/home-layout',
        'featured': '/api/featured',
        'ad': '/api/ad',
        'pricing': '/api/pricing',
        'feedback': '/api/feedback-prompt',
        'servers': '/api/servers',
        'banner': '/api/banners',
        'force_update': '/api/app-version',
      };
      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/api/device-rt/ws') {
          expect(
              request.uri.queryParameters, <String, String>{'ticket': _ticket});
          peer = await WebSocketTransformer.upgrade(request);
          peer!.listen((_) {});
          return;
        }
        request.response.headers.contentType = ContentType.json;
        if (path == '/api/device-rt/ticket') {
          expect(request.method, 'POST');
          expect(request.headers.value('authorization'),
              'Bearer synthetic-device-token');
          expect(request.headers.value('x-device-key'), isNull);
          request.response
              .write(jsonEncode(<String, String>{'ticket': _ticket}));
        } else if (path.startsWith('/api/status/') ||
            path == '/api/heartbeat') {
          final key = request.headers.value('x-device-key');
          if (key != null) {
            expect(key, _key);
            expect(
                request.headers.value('x-device-id'), 'synthetic-android-id');
          }
          request.response.write(jsonEncode(<String, Object>{
            'device_token': 'synthetic-device-token',
            'exists': true,
            'status': 'active',
            'paid': true,
            'plan': 'lifetime',
            'expired': false,
            'frozen': false,
            'banned': false,
            'source_rev': 0,
          }));
        } else if (path.startsWith('/api/box/ack/')) {
          ackPosts++;
          request.response.write('{"ok":true}');
        } else if (paths.containsValue(path)) {
          reads[path] = (reads[path] ?? 0) + 1;
          if (path == '/api/ad' && holdAd) {
            holdAd = false;
            adStarted.complete();
            await adGate.future;
          }
          final bodies = <String, String>{
            '/api/announcement':
                '{"id":$revision,"title":"Message","body":"Reçu","expires_at":0}',
            '/api/theme': jsonEncode(<String, String>{
              'appName': themeName,
              'accent': '#F2F0E8',
              'bg': 'dark'
            }),
            '/api/home-layout': '{"items":[{"key":"recent","ribbon":"Reçu"}]}',
            '/api/featured': '{"name":"À la une","note":"Reçu"}',
            '/api/ad': '{"enabled":false}',
            '/api/pricing':
                '{"configured":true,"currency":"EUR","lifetime":"10"}',
            '/api/feedback-prompt': '{"enabled":false,"message":"Reçu"}',
            '/api/servers': '{"servers":[]}',
            '/api/banners': '{"items":[]}',
            '/api/app-version': '{"minBuildTs":0}',
          };
          request.response.write(bodies[path]);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('{}');
        }
        await request.response.close();
      });
      void send(String kind) {
        peer!.add(jsonEncode(<String, Object>{
          'v': 1,
          'type': kind,
          'version': ++revision,
          'at': DateTime.now().millisecondsSinceEpoch,
        }));
      }

      final measured = <String, int>{};
      try {
        RemoteActivationWatch.instance.start(
          allowSourceImport: false,
          deviceCredentials: () async => const DeviceRealtimeCredentials(
            deviceKey: _key,
            deviceId: 'synthetic-android-id',
          ),
        );
        final exercised = paths.keys
            .where((kind) => kind != 'force_update' || kBuildTs > 0)
            .toList();
        await _until(
            () =>
                peer != null &&
                exercised.every(SignalInbox.instance.appliedKinds.contains),
            'La reconnexion relit les réglages, même sans replay serveur.');
        for (final kind in exercised) {
          SignalInbox.instance.resetForTesting();
          final before = reads[paths[kind]] ?? 0;
          final watch = Stopwatch()..start();
          send(kind);
          await _until(
              () =>
                  (reads[paths[kind]] ?? 0) > before &&
                  SignalInbox.instance.appliedKinds.contains(kind),
              '$kind doit avoir été réellement relu et appliqué.');
          measured[kind] = watch.elapsedMilliseconds;
          expect(watch.elapsedMilliseconds, lessThan(1000));
        }
        SignalInbox.instance.resetForTesting();
        holdAd = true;
        send('ad');
        await adStarted.future.timeout(const Duration(seconds: 2));
        themeName = 'Thème indépendant';
        final watch = Stopwatch()..start();
        send('theme');
        await _until(
            () =>
                RemoteThemeRepository.current.value.appName == themeName &&
                SignalInbox.instance.appliedKinds.contains('theme'),
            'Un téléchargement publicitaire ne retient pas le thème.');
        measured['theme_while_ad_blocked'] = watch.elapsedMilliseconds;
        expect(watch.elapsedMilliseconds, lessThan(1000));
        expect(SignalInbox.instance.appliedKinds.contains('ad'), isFalse);
        adGate.complete();
        await _until(() => SignalInbox.instance.appliedKinds.contains('ad'),
            'La publicité finit ensuite réellement.');
        expect(ackPosts, 0,
            reason: 'Le canal sans order_id ne fabrique pas d’accusé legacy.');
        debugPrint(
            '[mesure réglages ${handset ? 'mobile' : 'TV'} locale, ms] ${jsonEncode(measured)}');
      } finally {
        if (!adGate.isCompleted) adGate.complete();
        RemoteActivationWatch.instance.stopForTesting();
        await peer?.close();
        await server.close(force: true);
        AppPlatform.isTv = previousTv;
        AppPlatform.isZuno = previousZuno;
        HttpOverrides.global = previousHttp;
      }
    }, skip: !_run);
  }
}
