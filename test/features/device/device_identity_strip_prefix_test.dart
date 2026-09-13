// =========================================================
//  device_identity_strip_prefix_test.dart
// =========================================================
//  Garantit que le CODE affiché/copié/envoyé au revendeur est NU
//  (sans le préfixe historique « MK: »), afin qu'un panel qui préfixe
//  déjà « MK » ne produise pas un doublon « MKMK:… ». L'identité interne
//  garde le préfixe — ce helper ne touche QUE la présentation.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/device/data/device_identity.dart';

void main() {
  group('DeviceIdentity.stripPrefix', () {
    test('retire le préfixe « MK: » et ne garde que les octets', () {
      expect(
        DeviceIdentity.stripPrefix('MK:24:2A:D0:0E:F3'),
        '24:2A:D0:0E:F3',
      );
    });

    test('insensible à la casse du préfixe', () {
      expect(DeviceIdentity.stripPrefix('mk:AA:BB:CC:DD:EE'), 'AA:BB:CC:DD:EE');
    });

    test('placeholder de chargement → nu lui aussi', () {
      expect(DeviceIdentity.stripPrefix('MK:??:??:??:??:??'), '??:??:??:??:??');
    });

    test('une valeur SANS préfixe MK est laissée intacte', () {
      expect(DeviceIdentity.stripPrefix('24:2A:D0:0E:F3'), '24:2A:D0:0E:F3');
      expect(DeviceIdentity.stripPrefix('AB:CD:EF:01:23:45'),
          'AB:CD:EF:01:23:45');
    });

    test('idempotent : re-striper ne change plus rien', () {
      final String once = DeviceIdentity.stripPrefix('MK:24:2A:D0:0E:F3');
      expect(DeviceIdentity.stripPrefix(once), once);
    });

    test('sans séparateur → intact (robustesse)', () {
      expect(DeviceIdentity.stripPrefix('MK'), 'MK');
      expect(DeviceIdentity.stripPrefix(''), '');
    });

    // Photo Lionel (13/09/2026) : tablette verrouillée, écran « Nos offres ».
    // L'app MOBILE affiche le code NU ; le Worker / RT parlent en MK:…
    test('tablette Lionel CD:18:EF:A1:A0 ↔ MAC interne MK:…', () {
      const String shown = 'CD:18:EF:A1:A0';
      const String internal = 'MK:CD:18:EF:A1:A0';
      expect(DeviceIdentity.stripPrefix(internal), shown);
      expect(DeviceIdentity.stripPrefix(shown), shown);
      expect(RegExp(r'^MK(?::[0-9A-F]{2}){5}$').hasMatch(internal), isTrue);
    });
  });
}
