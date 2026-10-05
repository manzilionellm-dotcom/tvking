// =========================================================
//  repair_flags_test.dart — Les interrupteurs de repli sont
//  coupés par défaut, et leur clé est celle qu'on pose en adb.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(RepairFlags.debugReset);

  test('ordre du panel : import immédiat par défaut, repli par la clé',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await RepairFlags.load();
    expect(RepairFlags.sourceOrderWaitsIdle, isFalse,
        reason: 'défaut = la liste du panel arrive même pendant la lecture');
    expect(RepairFlags.sourceOrderWaitsIdleKey, 'zuno.source.order_waits_idle');

    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.sourceOrderWaitsIdleKey: true,
    });
    await RepairFlags.load();
    expect(RepairFlags.sourceOrderWaitsIdle, isTrue,
        reason: 'le repli rétablit l\'attente du retour à l\'accueil');

    RepairFlags.debugReset();
    expect(RepairFlags.sourceOrderWaitsIdle, isFalse);
  });
}
