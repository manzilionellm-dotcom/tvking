// =========================================================
//  voice_keys.dart — Touches « micro » de la télécommande
// =========================================================
//  Sur une box Android TV, le bouton micro envoie souvent :
//    • KEYCODE_SEARCH       (84)
//    • KEYCODE_ASSIST       (219)
//    • KEYCODE_VOICE_ASSIST (231)
//  Flutter connaît la touche Search. Les deux autres arrivent parfois
//  comme des touches Android non répertoriées : leur identifiant est
//  alors « plan Android » + le code clavier (constante officielle du
//  framework, 0x01100000000).
//
//  On ne consomme JAMAIS ces touches pendant qu'une chaîne ou le direct
//  est à l'écran (voir VoiceHotkey + TvActivity). Ici, on ne fait que
//  reconnaître la touche.
// =========================================================

import 'package:flutter/services.dart';

abstract final class VoiceKeys {
  /// Même valeur que `LogicalKeyboardKey.androidPlane` dans Flutter.
  static const int androidPlane = 0x01100000000;

  static const int planeMask = 0x0FF00000000;

  static const int keySearch = 84;
  static const int keyAssist = 219;
  static const int keyVoiceAssist = 231;

  static bool isMicLogical(LogicalKeyboardKey key) {
    // KEYCODE_SEARCH (84) et KEYCODE_ASSIST (219) sont connus de Flutter.
    // KEYCODE_VOICE_ASSIST (231) ne l'est pas : il arrive dans le « plan
    // Android » (identifiant = plan + code). On accepte les trois.
    if (key == LogicalKeyboardKey.browserSearch) return true;
    if (key == LogicalKeyboardKey.launchAssistant) return true;
    if ((key.keyId & planeMask) != androidPlane) return false;
    final int code = key.keyId & 0xFFFFFFFF;
    return code == keySearch || code == keyAssist || code == keyVoiceAssist;
  }

  /// Vrai seulement sur l'appui (pas la répétition : une télécommande
  /// répète la touche si on la garde, et on ne veut pas ouvrir dix fois
  /// la recherche).
  static bool isMicPress(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    return isMicLogical(event.logicalKey);
  }
}
