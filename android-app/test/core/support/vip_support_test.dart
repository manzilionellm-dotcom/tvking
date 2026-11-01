import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/subscription/data/subscription_backend.dart';
import 'package:tv_king/core/support/vip_support.dart';
import 'package:tv_king/core/app/app_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('brouillon WhatsApp support', () {
    test('indique ZUNO, la MAC, le statut confirmé et la version', () {
      final String message = VipSupport.composeSupportMessage(
        appName: 'ZUNO',
        mac: 'MK:FB:88:05:2B:68',
        status: 'payant',
        version: '109 (1793314563)',
      );
      expect(message, contains('Application : ZUNO'));
      expect(message, contains('MAC : MK:FB:88:05:2B:68'));
      expect(message, contains('Statut : payant'));
      expect(message, contains('Version : 109 (1793314563)'));
      expect(message, isNot(contains('password=')));
      expect(message, isNot(contains('get.php')));
    });

    test('conserve le message d\'activation et ne répète pas la MAC', () {
      final String message = VipSupport.composeSupportMessage(
        appName: 'ZUNO',
        mac: 'MK:FB:88:05:2B:68',
        status: 'test',
        version: '109',
        customMessage: 'Bonjour, je veux activer ma MAC MK:FB:88:05:2B:68',
      );
      expect(message, contains('je veux activer'));
      expect('MK:FB:88:05:2B:68'.allMatches(message).length, 1);
      expect(message, contains('Statut : test'));
    });

    test('ne transforme pas un statut inconnu en abonnement payé', () {
      final String message = VipSupport.composeSupportMessage(
        appName: '',
        mac: '',
        status: '',
        version: '',
      );
      expect(message, contains('Application : ZUNO'));
      expect(message, contains('MAC : indisponible'));
      expect(message, contains('Statut : non vérifié'));
      expect(message, isNot(contains('Statut : payant')));
      expect(message, contains('Version : indisponible'));
    });
  });
  test('le support résume le compte sans transformer un essai en paiement', () {
    final DateTime now = DateTime.utc(2026, 11, 1);
    RemoteSubscriptionStatus status(Map<String, Object> values) =>
        RemoteSubscriptionStatus.fromJson(
            <String, dynamic>{'exists': true, ...values});
    expect(
        VipSupport.subscriptionStatus(RemoteSubscriptionStatus.unknown,
            now: now),
        'non vérifié');
    expect(
        VipSupport.subscriptionStatus(status(<String, Object>{'days_left': 1}),
            now: now),
        'test');
    expect(
        VipSupport.subscriptionStatus(status(<String, Object>{'paid': true}),
            now: now),
        'payant');
    expect(
        VipSupport.subscriptionStatus(
            status(<String, Object>{'paid': true, 'banned': true}),
            now: now),
        'bloqué');
    expect(
        VipSupport.subscriptionStatus(
            status(<String, Object>{'paid': true, 'frozen': true}),
            now: now),
        'suspendu');
    expect(
        VipSupport.subscriptionStatus(status(<String, Object>{'expired': true}),
            now: now),
        'expiré');
    expect(
        VipSupport.subscriptionStatus(
            status(<String, Object>{'status': 'active'}),
            now: now),
        'non actif');
  });

  test(
      'diagnostic borné, sans lien fournisseur ni secret, même dans un texte libre',
      () {
    final String message = VipSupport.composeSupportMessage(
      appName: 'ZUNO',
      mac: 'MK:FB:88:05:2B:68',
      status: 'test',
      version: '110',
      customMessage:
          'Aide https://private.invalid/get.php?username=alice&password=secret',
      edition: 'ZUNO téléphone',
      device: 'Pixel Android 16',
      locale: 'ar',
      subscriptionDetails: 'échéance UTC 2026-11-02',
      sourceCount: 2,
      channelCount: 1400,
      syncState: 'hors ligne',
      importState: 'saving',
      previousSessionAbrupt: true,
      previousExitReason: 'LOW_MEMORY (https://private.invalid?token=secret)',
    );
    expect(message, contains('MAC : MK:FB:88:05:2B:68'));
    expect(message, contains('Chaînes chargées : 1400'));
    expect(message, contains('Session précédente : arrêt inattendu'));
    expect(message, contains('Raison Android : LOW_MEMORY'));
    for (final String forbidden in <String>[
      'private.invalid',
      'alice',
      'secret',
      'get.php'
    ]) {
      expect(message, isNot(contains(forbidden)));
    }
    expect(message.length, lessThan(2000));
    final String invalid = VipSupport.composeSupportMessage(
      appName: 'ZUNO',
      mac: 'password=private',
      status: '',
      version: '',
      customMessage: List<String>.filled(1000, 'très long').join(),
      previousExitReason: 'unknown password=private',
    );
    expect(invalid, contains('MAC : indisponible'));
    expect(invalid, isNot(contains('private')));
    expect(invalid, isNot(contains('Raison Android')));
    expect(invalid.length, lessThan(400));
  });

  test(
      'ouverture fluide : un plugin muet ne bloque pas le brouillon, deux taps ouvrent une fois',
      () async {
    final bool previousZuno = AppPlatform.isZuno;
    final bool previousTv = AppPlatform.isTv;
    AppPlatform.configureZuno(isAndroidHandset: true);
    addTearDown(() {
      AppPlatform.isZuno = previousZuno;
      AppPlatform.isTv = previousTv;
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:FB:88:05:2B:68',
    });
    PackageInfo.setMockInitialValues(
      appName: 'ZUNO',
      packageName: 'test.zuno',
      version: '110',
      buildNumber: '123',
      buildSignature: '',
    );
    const MethodChannel device =
        MethodChannel('com.manzilionellm.tvking/device');
    const MethodChannel launcher =
        MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final Completer<Object?> silentPlugin = Completer<Object?>();
    messenger.setMockMethodCallHandler(device, (_) => silentPlugin.future);
    final List<Uri> opened = <Uri>[];
    messenger.setMockMethodCallHandler(launcher, (call) async {
      opened.add(Uri.parse((call.arguments as Map)['url'] as String));
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(device, null);
      messenger.setMockMethodCallHandler(launcher, null);
      if (!silentPlugin.isCompleted) silentPlugin.complete(null);
    });
    final List<bool> results = await Future.wait<bool>(<Future<bool>>[
      VipSupport.openWhatsApp(customMessage: 'Bonjour'),
      VipSupport.openWhatsApp(customMessage: 'Second appui'),
    ]).timeout(const Duration(seconds: 2));
    expect(results, <bool>[true, true]);
    expect(opened, hasLength(1));
    expect(opened.single.host, 'wa.me');
    expect(opened.single.path, '/447307410512');
    final String draft = opened.single.queryParameters['text']!;
    expect(draft, contains('MAC : MK:FB:88:05:2B:68'));
    expect(draft, contains('Version : 110 (123)'));
    expect(draft, contains('Application : ZUNO Mobile'));
    expect(draft, contains('Édition : ZUNO Mobile'));
    expect(AppPlatform.id, 'tv');
    expect(draft, contains('Appareil : indisponible'));
    expect(draft, isNot(contains('Second appui')));
  });
}
