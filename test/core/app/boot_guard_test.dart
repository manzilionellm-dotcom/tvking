// =========================================================
//  boot_guard_test.dart — disjoncteur anti « app qui redémarre en boucle »
// =========================================================
//  Vérifie que BootGuard passe en MODE SANS ÉCHEC après plusieurs
//  démarrages RAPPROCHÉS (crash-loop), et PAS lors d'un démarrage isolé.
//  C'est ce mode qui fait sauter le ré-import de la source distante au boot
//  (l'étape « qui scanne »), cassant la boucle décrite par l'utilisateur.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/boot_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('démarrage isolé : pas de mode sans échec', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await BootGuard.instance.beginBoot();
    expect(BootGuard.instance.safeMode, isFalse);
  });

  test('3 démarrages rapprochés → mode sans échec (boucle détectée)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // Boot 1 et 2 : encore sous le seuil, on laisse démarrer normalement.
    await BootGuard.instance.beginBoot();
    expect(BootGuard.instance.safeMode, isFalse);
    await BootGuard.instance.beginBoot();
    expect(BootGuard.instance.safeMode, isFalse);

    // Boot 3 rapproché (les appels sont quasi instantanés, donc dans la
    // fenêtre de 20 s) → seuil atteint → MODE SANS ÉCHEC : le ré-import de la
    // source distante sera sauté au boot, ce qui casse la boucle de scan.
    await BootGuard.instance.beginBoot();
    expect(BootGuard.instance.safeMode, isTrue);
  });
}
