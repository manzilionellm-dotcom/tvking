// =========================================================
//  no_secure_flag_kills_image_test.dart
// =========================================================
//  16/09/2026 : FLAG_SECURE sur la fenêtre = image noire sur les box
//  Amlogic (surface « secure » que le décodeur n'affiche pas).
//  Ce test LIT le source : si quelqu'un re-pose setFlags(FLAG_SECURE),
//  CI rouge, APK non livré.
// =========================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity n\'ACTIVE JAMAIS FLAG_SECURE (ça tue l\'image)', () {
    final File f =
        File('android_overlay/google_cast/MainActivity.kt');
    expect(f.existsSync(), isTrue);
    final String code = f.readAsStringSync();
    expect(
      code.contains('window.setFlags') && code.contains('FLAG_SECURE'),
      isFalse,
      reason: 'setFlags(FLAG_SECURE) = écran noir sur box. Interdit.',
    );
    expect(
      code,
      contains('window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)'),
      reason: 'on FORCE le drapeau à OFF, même si un plugin le pose',
    );
  });

  test('SurfaceView.setSecure(false) — pas true', () {
    final File f = File(
      'packages/native_video_player/android/src/main/kotlin/'
      'com/manzilionellm/native_video_player/NativeVideoView.kt',
    );
    expect(f.existsSync(), isTrue);
    final String code = f.readAsStringSync();
    expect(code, contains('surfaceView.setSecure(false)'));
    expect(code.contains('setSecure(true)'), isFalse);
  });

  test('le CI TV/phone pose clearFlags, pas setFlags SECURE', () {
    for (final String p in <String>[
      '.github/workflows/build-seventv.yml',
      '.github/workflows/build-android.yml',
    ]) {
      final String y = File(p).readAsStringSync();
      expect(y, contains('ci/clear_secure_flag.py'), reason: p);
      expect(y.contains('flag_secure_activity.py'), isFalse, reason: p);
    }
    final String py = File('ci/clear_secure_flag.py').readAsStringSync();
    expect(py, contains('clearFlags'));
    expect(py, contains('window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)'));
    // Le script PEUT citer setFlags : c'est le motif qu'il REMPLACE.
  });
}
