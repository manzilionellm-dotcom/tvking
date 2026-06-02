// =========================================================
//  screen_recorder.dart — Wrapper de l'enregistrement par
//  CAPTURE D'ÉCRAN (MediaProjection, côté natif Kotlin)
// =========================================================
//  Méthode d'enregistrement IMBLOCABLE : on capture ce qui est
//  affiché à l'écran (la vidéo qui joue) au lieu de re-télécharger
//  le flux. Avantages :
//    - Marche quel que soit le serveur (même "1 connexion") car on
//      ne rouvre AUCUNE connexion réseau.
//    - La lecture continue : le client regarde pendant que ça
//      enregistre en arrière-plan.
//    - Jamais "vide" : si ça joue à l'écran, c'est capturé.
//
//  Implémentation native : MainActivity (popup d'autorisation) +
//  ScreenRecordService (MediaRecorder → MP4). Channel :
//  `com.manzilionellm.tvking/screen_recorder`.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenRecorder {
  ScreenRecorder._();
  static final ScreenRecorder instance = ScreenRecorder._();

  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/screen_recorder');

  /// `true` si l'appareil supporte la capture d'écran (Android 5+).
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Démarre la capture vers [filePath] (un .mp4). Affiche la popup
  /// système d'autorisation au 1er lancement. Retourne `true` si la
  /// capture a bien démarré, `false` si l'utilisateur a refusé ou en
  /// cas d'erreur. La lecture N'est PAS interrompue.
  Future<bool> start({
    required String filePath,
    required String title,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('start', <String, dynamic>{
        'file': filePath,
        'title': title,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[ScreenRec] start error: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Arrête la capture et finalise le fichier MP4.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[ScreenRec] stop error: ${e.message}');
    } on MissingPluginException {
      // ignore
    }
  }
}
