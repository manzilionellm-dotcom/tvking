// =========================================================
//  gallery_exporter.dart — Export d'enregistrements vers Galerie
// =========================================================
//  Wrapper Dart au-dessus du MethodChannel
//  `com.manzilionellm.tvking/gallery` (impl Kotlin dans
//  android_overlay/google_cast/GalleryExporter.kt).
//
//  Le `RecordingRepository` actuel sauvegarde les .ts dans
//  `/storage/emulated/0/Android/data/<package>/files/Recordings`
//  (storage privé app), qui :
//    - Est INVISIBLE dans la Galerie photo du téléphone
//    - Est PERDU à la désinstallation de l'app
//
//  Cette classe copie le .ts (en le re-baptisant .mp4) vers
//  `Movies/7MOTION/` via MediaStore — accessible à toutes les apps
//  (Galerie, YouTube, WhatsApp upload, etc.) et survit à la
//  désinstallation.
//
//  Stratégie : on RENOMME en .mp4 sans transcoder. La plupart des
//  players acceptent un MPEG-TS dans un container .mp4 — mismatch
//  MIME bénin, évite d'embarquer ffmpeg (50 MB de plus dans l'APK).
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GalleryExporter {
  GalleryExporter._();

  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/gallery');

  /// Copie [srcPath] (un fichier .ts existant) vers la galerie photo
  /// du téléphone sous `Movies/7MOTION/[displayName]`. Le nom DOIT
  /// contenir l'extension (`.mp4` recommandé). Best effort — retourne
  /// `false` sans throw si l'opération échoue, pour ne jamais bloquer
  /// la fin d'un enregistrement.
  static Future<bool> exportVideo({
    required String srcPath,
    required String displayName,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'exportVideo',
        <String, dynamic>{
          'srcPath': srcPath,
          'displayName': displayName,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[Gallery] export PlatformException: ${e.message}');
      }
      return false;
    } on MissingPluginException {
      // Channel pas câblé (ex. iOS, ou build sans overlay)
      if (kDebugMode) debugPrint('[Gallery] channel manquant');
      return false;
    }
  }
}
