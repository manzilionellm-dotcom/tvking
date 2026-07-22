// =========================================================
//  app_pin_settings_test.dart — PIN durci (haché + anti-brute-force)
// =========================================================
//  Audit 2026-07-22 : le PIN protégeant l'app ET le Mode Enfants était
//  stocké EN CLAIR et sans aucune limitation d'essais. Ces tests verrouillent
//  le durcissement : hachage salé, verrouillage progressif, migration.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/security/data/app_pin_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final AppPinSettings pin = AppPinSettings.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    pin.clock = DateTime.now; // horloge par défaut
  });

  test('PIN par défaut accepté sur install fraîche', () async {
    expect(await pin.verify('0000'), isTrue);
    expect(await pin.verify('1234'), isFalse);
  });

  test('setPin ne stocke JAMAIS le PIN en clair', () async {
    await pin.setPin('4271');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    // Aucune valeur de préférence ne doit contenir le PIN en clair.
    for (final String k in prefs.getKeys()) {
      final Object? v = prefs.get(k);
      if (v is String) {
        expect(v.contains('4271'), isFalse, reason: 'clé $k fuit le PIN');
      }
    }
    expect(await pin.verify('4271'), isTrue);
    expect(await pin.verify('0000'), isFalse);
  });

  test('migration : ancien PIN en clair est re-haché au 1er succès', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'security.app_pin_value': '5555', // ancien format clair
    });
    expect(await pin.verify('5555'), isTrue);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('security.app_pin_value'), isFalse,
        reason: 'le clair est effacé après migration');
    expect(prefs.containsKey('security.app_pin_hash'), isTrue);
    // Toujours vérifiable après migration.
    expect(await pin.verify('5555'), isTrue);
  });

  test('verrouillage progressif : au-delà du seuil, blocage temporel', () async {
    await pin.setPin('1111');
    // 4 essais ratés « gratuits ».
    for (int i = 0; i < 4; i++) {
      expect(await pin.verify('0000'), isFalse);
    }
    expect(await pin.lockoutRemaining(), Duration.zero);
    // 5e raté → blocage armé.
    expect(await pin.verify('0000'), isFalse);
    final Duration locked = await pin.lockoutRemaining();
    expect(locked > Duration.zero, isTrue);
    // Même le BON PIN est refusé pendant le blocage.
    expect(await pin.verify('1111'), isFalse);
  });

  test('le blocage expire avec le temps puis le bon PIN repasse', () async {
    await pin.setPin('2222');
    DateTime now = DateTime(2026, 1, 1, 12);
    pin.clock = () => now;
    for (int i = 0; i < 5; i++) {
      await pin.verify('9999');
    }
    expect(await pin.lockoutRemaining() > Duration.zero, isTrue);
    // On avance de 31 s (le 1er palier est 30 s).
    now = now.add(const Duration(seconds: 31));
    expect(await pin.lockoutRemaining(), Duration.zero);
    expect(await pin.verify('2222'), isTrue);
  });

  test('un succès remet le compteur d\'échecs à zéro', () async {
    await pin.setPin('3333');
    await pin.verify('0000');
    await pin.verify('0000');
    expect(await pin.verify('3333'), isTrue); // succès
    // Après reset, on peut de nouveau rater sans être bloqué tout de suite.
    for (int i = 0; i < 4; i++) {
      expect(await pin.verify('0000'), isFalse);
    }
    expect(await pin.lockoutRemaining(), Duration.zero);
  });
}
