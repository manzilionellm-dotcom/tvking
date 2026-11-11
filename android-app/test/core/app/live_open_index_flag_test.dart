import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(RepairFlags.debugReset);

  test('L1-05 : index actif par défaut, repli explicite et erreur sûre', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await RepairFlags.load();
    expect(RepairFlags.liveOpenIndexLegacy, isFalse);

    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.liveOpenIndexLegacyKey: true,
    });
    await RepairFlags.load();
    expect(RepairFlags.liveOpenIndexLegacy, isTrue);
    RepairFlags.debugReset();
    expect(RepairFlags.liveOpenIndexLegacy, isFalse);

    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.liveOpenIndexLegacyKey: 'préférence illisible',
    });
    await RepairFlags.load();
    expect(RepairFlags.liveOpenIndexLegacy, isFalse);
  });
}
