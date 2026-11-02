import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.manzilionellm.tvking/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'le vrai heartbeat transporte le matériel sans changer le produit ZUNO',
    () async {
      int infoReads = 0;
      final requests = <Map<String, dynamic>>[];
      PackageInfo.setMockInitialValues(
        appName: 'ZUNO',
        packageName: 'com.sevenmotion.zuno.tv',
        version: '1.14.0',
        buildNumber: '114',
        buildSignature: '',
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getAndroidId') return 'synthetic-test-id';
        if (call.method != 'getDeviceInfo') return null;
        // Pont pas prêt au premier ping : unknown, puis vraie fiche au suivant.
        if (++infoReads == 1) throw PlatformException(code: 'not_ready');
        return <String, String>{
          'deviceKind': 'android_phone',
          'model': 'SM-S938B',
          'manufacturer': 'Samsung',
          'release': '16',
          'sdk': '36',
          'build': 'test-build',
        };
      });
      final previousTv = AppPlatform.isTv;
      final previousZuno = AppPlatform.isZuno;
      // Une édition TV installée sur téléphone reste le produit ZUNO, mais le
      // matériel déclaré au panel doit bien être android_phone.
      AppPlatform.configureZuno(isAndroidHandset: false);
      try {
        await http.runWithClient(
          () async {
            await SubscriptionBackend.heartbeat('MK:11:22:33:44:55');
            await SubscriptionBackend.heartbeat('MK:11:22:33:44:55');
          },
          () => MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/heartbeat');
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              '{"exists":true,"status":"active","paid":false}',
              200,
            );
          }),
        );
        expect(requests, hasLength(2));
        expect(requests.first['deviceKind'], 'unknown');
        expect(requests.last['deviceKind'], 'android_phone');
        expect(requests.last['model'], 'SM-S938B');
        expect(requests.last['manufacturer'], 'Samsung');
        expect(requests.last['android'], '16');
        expect(requests.last['appVersion'], '1.14.0');
        expect(requests.every((body) => body['platform'] == 'tv'), isTrue);
        expect(infoReads, 2);
      } finally {
        AppPlatform.isTv = previousTv;
        AppPlatform.isZuno = previousZuno;
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
