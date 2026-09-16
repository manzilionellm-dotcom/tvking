// =========================================================
//  no_secure_flag_kills_image_test.dart
// =========================================================
// FLAG_SECURE = image noire. Interdit de le REPOSER.
// =========================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity n\'ACTIVE JAMAIS FLAG_SECURE', () {
    final File f =
        File('android_overlay/google_cast/MainActivity.kt');
    expect(f.existsSync(), isTrue);
    final String code = f
        .readAsStringSync()
        .split('\n')
        .where((String l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('FLAG_SECURE'), isFalse);
    expect(code.contains('setFlags'), isFalse);
  });

  test('SurfaceView n\'est pas setSecure(true)', () {
    final File f = File(
      'packages/native_video_player/android/src/main/kotlin/'
      'com/manzilionellm/native_video_player/NativeVideoView.kt',
    );
    expect(f.existsSync(), isTrue);
    final String code = f
        .readAsStringSync()
        .split('\n')
        .where((String l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('setSecure(true)'), isFalse);
  });
}
