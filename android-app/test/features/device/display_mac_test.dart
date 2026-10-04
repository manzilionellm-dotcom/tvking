// =========================================================
//  display_mac_test.dart — La MAC vue par le client, sans « MK: »
// =========================================================
//  MAC factices uniquement. L'identifiant interne n'est jamais modifié :
//  on ne teste que ce qui s'affiche et ce qui part dans WhatsApp.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/device/domain/display_mac.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';

void main() {
  tearDown(RepairFlags.debugReset);

  test('le préfixe MK: disparaît à l\'affichage, casse et espaces ignorés', () {
    expect(displayMac('MK:AD:A6:98:70:6A'), 'AD:A6:98:70:6A');
    expect(displayMac('mk:ad:a6:98:70:6a'), 'ad:a6:98:70:6a');
    expect(displayMac('  MK:AD:A6:98:70:6A  '), 'AD:A6:98:70:6A');
  });

  test('sans préfixe, vide ou pas encore chargée : rendue telle quelle', () {
    expect(displayMac('AD:A6:98:70:6A'), 'AD:A6:98:70:6A');
    expect(displayMac(''), '');
    expect(displayMac('…'), '…');
    expect(displayMac('MK:'), 'MK:', reason: 'rien après le préfixe : on ne rend pas une chaîne vide');
  });

  test('interrupteur de repli : l\'ancien affichage revient à l\'identique', () {
    expect(displayMac('MK:AD:A6:98:70:6A', showPrefix: true), 'MK:AD:A6:98:70:6A');
  });

  test('message WhatsApp : code sans MK:, repli possible', () {
    final String url = tvWhatsAppUrl('MK:AD:A6:98:70:6A');
    final String text = Uri.parse(url).queryParameters['text']!;
    expect(text, contains('Mon code : AD:A6:98:70:6A'));
    expect(text, isNot(contains('MK:')));

    RepairFlags.macShowPrefix = true;
    final String old = Uri.parse(tvWhatsAppUrl('MK:AD:A6:98:70:6A')).queryParameters['text']!;
    expect(old, contains('Mon code : MK:AD:A6:98:70:6A'));
  });

  test('MAC pas encore chargée : pas de code dans le message', () {
    final String text = Uri.parse(tvWhatsAppUrl('…')).queryParameters['text']!;
    expect(text, isNot(contains('Mon code')));
  });
}
