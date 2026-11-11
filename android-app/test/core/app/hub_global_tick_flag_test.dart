import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(RepairFlags.debugReset);

  test('L1-06 : écouteurs locaux par défaut, repli explicite et erreur sûre',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await RepairFlags.load();
    expect(RepairFlags.hubGlobalTickLegacy, isFalse);

    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.hubGlobalTickLegacyKey: true,
    });
    await RepairFlags.load();
    expect(RepairFlags.hubGlobalTickLegacy, isTrue);
    RepairFlags.debugReset();
    expect(RepairFlags.hubGlobalTickLegacy, isFalse);

    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.hubGlobalTickLegacyKey: 'préférence illisible',
    });
    await RepairFlags.load();
    expect(RepairFlags.hubGlobalTickLegacy, isFalse);
  });
}
