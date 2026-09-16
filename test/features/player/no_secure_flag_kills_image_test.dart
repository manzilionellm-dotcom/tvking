// FLAG_SECURE = image noire. Interdit de le REPOSER.
// Rendu = SurfaceView (14/09/2026, l'image marchait).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String _code(File f) => f
      .readAsStringSync()
      .split('\n')
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('MainActivity n\'ACTIVE JAMAIS FLAG_SECURE', () {
    final String code =
        _code(File('android_overlay/google_cast/MainActivity.kt'));
    expect(code.contains('FLAG_SECURE'), isFalse);
    expect(code.contains('setFlags'), isFalse);
  });

  test('défaut rendu = surface (14/09, image visible)', () {
    final String dart = _code(
        File('packages/native_video_player/lib/native_video_player.dart'));
    expect(dart, contains('return surface'));
    final String kt = _code(File(
      'packages/native_video_player/android/src/main/kotlin/'
      'com/manzilionellm/native_video_player/NativeVideoPlayerPlugin.kt',
    ));
    expect(kt, contains('"surface"'));
    expect(kt, contains('render_reset_v6'));
  });

  test('SurfaceView n\'est pas setSecure(true)', () {
    final String code = _code(File(
      'packages/native_video_player/android/src/main/kotlin/'
      'com/manzilionellm/native_video_player/NativeVideoView.kt',
    ));
    expect(code.contains('setSecure(true)'), isFalse);
  });

  test('CI ne pose PAS FLAG_SECURE sur TV ni téléphone', () {
    for (final String p in <String>[
      '.github/workflows/build-seventv.yml',
      '.github/workflows/build-android.yml',
      '.github/workflows/build-prive.yml',
    ]) {
      expect(File(p).readAsStringSync(), isNot(contains('ci/set_secure_flag.py')),
          reason: p);
    }
  });
}
