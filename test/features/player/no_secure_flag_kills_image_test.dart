// FLAG_SECURE ON (pas de capture) + rendu TEXTURE (l'image sort).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String _code(File f) => f
      .readAsStringSync()
      .split('\n')
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('MainActivity BLOQUE les captures (setFlags FLAG_SECURE)', () {
    final String code =
        _code(File('android_overlay/google_cast/MainActivity.kt'));
    expect(code, contains('window.setFlags'));
    expect(code, contains('FLAG_SECURE'));
    expect(code.contains('clearFlags'), isFalse);
  });

  test('défaut rendu = texture (compatible FLAG_SECURE)', () {
    final String dart = _code(
        File('packages/native_video_player/lib/native_video_player.dart'));
    expect(dart, contains('return texture'));
    final String kt = _code(File(
      'packages/native_video_player/android/src/main/kotlin/'
      'com/manzilionellm/native_video_player/NativeVideoPlayerPlugin.kt',
    ));
    expect(kt, contains('"texture"'));
    expect(kt, contains('render_reset_v5'));
  });

  test('CI pose FLAG_SECURE sur TV et téléphone', () {
    for (final String p in <String>[
      '.github/workflows/build-seventv.yml',
      '.github/workflows/build-android.yml',
    ]) {
      expect(File(p).readAsStringSync(), contains('ci/set_secure_flag.py'),
          reason: p);
    }
  });
}
