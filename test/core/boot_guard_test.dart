// =========================================================
//  boot_guard_test.dart — Disjoncteur anti-boucle de redémarrage
// =========================================================
//  Vérifie la NOUVELLE sémantique (jalon + phase) :
//    • 3 démarrages NON réussis d'affilée → mode sans échec ;
//    • markBootSucceeded() est le SEUL reset du compteur.
//  C'est le correctif du bug « se connecte puis se ferme » → on le verrouille
//  par un test pour qu'il ne régresse jamais.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/boot_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Base de préférences vierge à chaque test (compteur de boucle remis à 0).
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('3 boots non réussis d\'affilée → mode sans échec', () async {
    final BootGuard g = BootGuard.instance;
    await g.beginBoot();
    expect(g.isInSafeMode, isFalse); // 1er
    await g.beginBoot();
    expect(g.isInSafeMode, isFalse); // 2e
    await g.beginBoot();
    expect(g.isInSafeMode, isTrue); // 3e → boucle détectée
  });

  test('markBootSucceeded() remet le compteur à zéro', () async {
    final BootGuard g = BootGuard.instance;
    await g.beginBoot();
    await g.beginBoot();
    await g.markBootSucceeded(); // boot réussi → oubli des échecs
    await g.beginBoot();
    expect(g.isInSafeMode, isFalse);
  });

  test('un boot réussi entre deux échecs empêche la fausse boucle', () async {
    final BootGuard g = BootGuard.instance;
    await g.beginBoot();
    await g.markBootSucceeded();
    await g.beginBoot();
    await g.markBootSucceeded();
    await g.beginBoot();
    expect(g.isInSafeMode, isFalse);
  });
}
