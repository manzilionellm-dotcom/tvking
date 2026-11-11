import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(RepairFlags.debugReset);

  test('L1-02 : mémorisation et regroupement actifs, repli explicite', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await RepairFlags.load();
    expect(RepairFlags.hubIndexLegacy, isFalse);
    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.hubIndexLegacyKey: true,
    });
    await RepairFlags.load();
    expect(RepairFlags.hubIndexLegacy, isTrue);
    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.hubIndexLegacyKey: 'valeur invalide',
    });
    await RepairFlags.load();
    expect(RepairFlags.hubIndexLegacy, isFalse);
  });
}
