import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/player/data/image_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ImagePrefs.resetForTesting);
  tearDown(ImagePrefs.resetForTesting);

  // Sans choix enregistré : image d'origine (sortie directe du décodeur).
  test('installation et mise à jour sans préférence : contraste coupé',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    expect(ImagePrefs.lightContrast, isFalse);
    expect(NativeVideoController.defaultLightContrast, isFalse);
  });

  test('un contraste allumé explicitement survit au redémarrage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    await ImagePrefs.setLightContrast(true);
    ImagePrefs.resetForTesting();
    await ImagePrefs.load();
    expect(ImagePrefs.lightContrast, isTrue);
    expect(NativeVideoController.defaultLightContrast, isTrue);
    await ImagePrefs.setLightContrast(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ImagePrefs.contrastKey), isFalse);
  });
}
