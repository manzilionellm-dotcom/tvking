import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.manzilionellm.tvking/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'un ancien pont sans type garde modèle et version avec un type inconnu',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'ZUNO',
        packageName: 'com.sevenmotion.zuno.tv',
        version: '1.14.0',
        buildNumber: '114',
        buildSignature: '',
      );
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getDeviceInfo'
            ? <String, String>{'model': 'ancien-appareil', 'release': '11'}
            : 'synthetic-test-id',
      );
      Map<String, dynamic>? sent;
      try {
        await http.runWithClient(
          () => SubscriptionBackend.heartbeat('MK:11:22:33:44:55'),
          () => MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              '{"exists":true,"status":"active","paid":false}',
              200,
            );
          }),
        );
        expect(sent, isNotNull);
        expect(sent!['deviceKind'], 'unknown');
        expect(sent!['model'], 'ancien-appareil');
        expect(sent!['android'], '11');
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
