// =========================================================
//  Rendu vidéo par TEXTURE — l'image doit sortir
// =========================================================
//  CE FICHIER A CHANGÉ DE CAMP LE 17/09/2026, ET IL FAUT LE DIRE.
//
//  Il verrouillait l'inverse : « MainActivity BLOQUE les captures
//  (setFlags FLAG_SECURE) » et « CI pose FLAG_SECURE sur TV et
//  téléphone ». Le pari de l'époque était qu'un rendu par texture
//  laissait passer l'image malgré le drapeau.
//
//  Le terrain a tranché. Le propriétaire, sur une box en clientèle :
//  « même l'application TV ne fonctionne pas, il sort seulement le
//  son ». Sur une box HDMI, une fenêtre marquée « secure » n'est pas
//  composée vers la sortie : la bande-son continue, l'écran reste
//  noir, et le client ne peut rien y faire.
//
//  Les assertions FLAG_SECURE ont donc été RETIRÉES d'ici, pas
//  seulement inversées : elles vivent maintenant dans
//  test/core/flag_secure_off_test.dart, seules et au même endroit
//  que le garde-fou des workflows. Deux fichiers qui jugent le même
//  drapeau finissent par se contredire — c'est exactement ce qui a
//  permis huit allers-retours en deux jours.
//
//  CE QUI RESTE ICI est le vrai sujet du fichier et n'a jamais été
//  en cause : le chemin de rendu par défaut doit être la TEXTURE.
//  C'est lui qui fait sortir l'image sur les box capricieuses, et
//  il a sa propre histoire (render_reset_v5).
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String code(File f) => f
      .readAsStringSync()
      .split('\n')
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('défaut rendu = texture', () {
    final String dart = code(
        File('packages/native_video_player/lib/native_video_player.dart'));
    expect(dart, contains('return texture'));
    final String kt = code(File(
      'packages/native_video_player/android/src/main/kotlin/'
      'com/manzilionellm/native_video_player/NativeVideoPlayerPlugin.kt',
    ));
    expect(kt, contains('"texture"'));
    expect(kt, contains('render_reset_v5'));
  });
}
