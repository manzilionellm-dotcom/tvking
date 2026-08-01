// Tests du réglage « Reprise au démarrage » (n°2) : défaut DÉSACTIVÉ,
// persistance SharedPreferences, notification des écouteurs.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/tv/data/boot_resume.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('désactivé par défaut (opt-in, jamais une surprise)', () async {
    await BootResume.instance.load();
    expect(BootResume.instance.enabled, isFalse);
  });

  test('activation persistée + écouteurs notifiés', () async {
    int notified = 0;
    BootResume.instance.addListener(() => notified++);
    await BootResume.instance.setEnabled(true);
    expect(BootResume.instance.enabled, isTrue);
    expect(notified, greaterThan(0));
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('tv.boot_resume.v1'), isTrue);
    await BootResume.instance.setEnabled(false);
    expect(BootResume.instance.enabled, isFalse);
  });
}
