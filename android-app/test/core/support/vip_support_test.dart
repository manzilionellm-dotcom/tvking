import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/support/vip_support.dart';

void main() {
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
}
