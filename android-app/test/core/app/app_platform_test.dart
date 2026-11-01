import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/support/vip_support.dart';

void main() {
  tearDown(() {
    AppPlatform.isTv = false;
    AppPlatform.isZuno = false;
  });

  test('7 MOTION garde son identité mobile par défaut', () {
    expect(AppPlatform.id, 'mobile');
    expect(AppPlatform.isZuno, isFalse);
    expect(AppPlatform.isTv, isFalse);
    expect(AppPlatform.deviceKind, 'mobile');
  });

  for (final handset in <bool>[true, false]) {
    test(
        'ZUNO distingue ${handset ? 'téléphone' : 'TV'} sans changer de marque',
        () {
      AppPlatform.configureZuno(isAndroidHandset: handset);
      expect(AppPlatform.isZuno, isTrue);
      expect(AppPlatform.isTv, !handset);
      expect(AppPlatform.deviceKind, handset ? 'mobile' : 'tv');
      // Le backend emploie encore platform comme namespace PRODUIT :
      // ZUNO téléphone garde le thème et les mises à jour de ZUNO.
      expect(AppPlatform.id, 'tv');
      expect(AppPlatform.zunoEditionName, handset ? 'ZUNO Mobile' : 'ZUNO TV');

      final message = VipSupport.composeSupportMessage(
        appName: AppPlatform.zunoEditionName,
        mac: 'MK:FB:88:05:2B:68',
        status: 'non vérifié',
        version: 'revue',
      );
      expect(message, contains('Application : ${AppPlatform.zunoEditionName}'));
      expect(message, isNot(contains('7 MOTION')));
      expect(message, contains('MAC : MK:FB:88:05:2B:68'));
    });
  }

  test('une initialisation TV remplace une ancienne détection téléphone', () {
    AppPlatform.configureZuno(isAndroidHandset: true);
    AppPlatform.configureZuno(isAndroidHandset: false);
    expect(AppPlatform.id, 'tv');
    expect(AppPlatform.deviceKind, 'tv');
    expect(AppPlatform.isTv, isTrue);
    expect(AppPlatform.zunoEditionName, 'ZUNO TV');
  });
}
