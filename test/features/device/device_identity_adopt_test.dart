// =========================================================
//  device_identity_adopt_test.dart — adopter un MAC régénéré
// =========================================================
//  Le panel pousse un nouveau numéro (RT / heartbeat). L'identité
//  interne DOIT changer : sinon « YOUR REFERENCE NUMBER » reste
//  l'ancien CD:18:EF:A1:A0 zombie.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/device/data/device_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DeviceIdentity.instance.debugResetCache();
  });

  group('DeviceIdentity.normalizeMac', () {
    test('référence affichée → MK: interne', () {
      expect(
        DeviceIdentity.normalizeMac('CD:18:EF:A1:A0'),
        'MK:CD:18:EF:A1:A0',
      );
    });

    test('déjà préfixé, casse normalisée', () {
      expect(
        DeviceIdentity.normalizeMac('mk:cd:18:ef:a1:a0'),
        'MK:CD:18:EF:A1:A0',
      );
    });

    test('hex collé sans deux-points', () {
      expect(
        DeviceIdentity.normalizeMac('cd18efa1a0'),
        'MK:CD:18:EF:A1:A0',
      );
    });
  });

  group('DeviceIdentity.adopt', () {
    test('persiste le nouveau MAC et notifie', () async {
      var ticks = 0;
      void tick() => ticks++;
      DeviceIdentity.instance.addListener(tick);
      addTearDown(() => DeviceIdentity.instance.removeListener(tick));

      final bool ok =
          await DeviceIdentity.instance.adopt('CD:18:EF:A1:A0');
      expect(ok, isTrue);
      expect(DeviceIdentity.instance.macSync, 'MK:CD:18:EF:A1:A0');
      expect(ticks, greaterThanOrEqualTo(1));

      final bool again =
          await DeviceIdentity.instance.adopt('MK:CD:18:EF:A1:A0');
      expect(again, isFalse);
    });

    test('refuse un garbage', () async {
      expect(await DeviceIdentity.instance.adopt('PAS-UNE-MAC'), isFalse);
      expect(DeviceIdentity.instance.macSync.contains('??'), isTrue);
    });
  });

  group('newMacFromReassigned', () {
    test('lit new_mac du payload Worker', () {
      expect(
        DeviceIdentity.newMacFromReassigned(<String, Object?>{
          'old_mac': 'MK:CD:18:EF:A1:A0',
          'new_mac': 'MK:11:22:33:44:55',
        }),
        'MK:11:22:33:44:55',
      );
    });

    test('null si payload incomplet', () {
      expect(DeviceIdentity.newMacFromReassigned(null), isNull);
      expect(DeviceIdentity.newMacFromReassigned(<String, Object?>{}), isNull);
    });
  });
}
