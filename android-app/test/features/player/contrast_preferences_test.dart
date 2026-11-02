import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/player/data/image_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(ImagePrefs.resetForTesting);
  tearDown(ImagePrefs.resetForTesting);

  test('installation et mise à jour sans préférence : contraste demandé',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    expect(ImagePrefs.lightContrast, isTrue);
    expect(NativeVideoController.defaultLightContrast, isTrue);
  });

  test('une désactivation explicite survit au redémarrage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ImagePrefs.load();
    await ImagePrefs.setLightContrast(false);
    ImagePrefs.resetForTesting();
    await ImagePrefs.load();
    expect(ImagePrefs.lightContrast, isFalse);
    expect(NativeVideoController.defaultLightContrast, isFalse);
    await ImagePrefs.setLightContrast(true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ImagePrefs.contrastKey), isTrue);
  });
}
