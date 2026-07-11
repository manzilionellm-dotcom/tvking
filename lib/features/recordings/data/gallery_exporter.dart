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
//  Cette classe copie l'enregistrement vers `Movies/` via MediaStore —
//  accessible à toutes les apps (Galerie, YouTube, WhatsApp upload, etc.)
//  et survit à la désinstallation.
//
//  Stratégie : côté natif (GalleryExporter.kt), on REMUXE le MPEG-TS
//  dans un VRAI conteneur MP4 (MediaExtractor + MediaMuxer, copie des
//  pistes sans ré-encodage) → fichier accepté par la galerie de la
//  plupart des téléphones. Repli sur copie brute si un codec n'est pas
//  muxable. Pas de ffmpeg embarqué, pas de perte de qualité.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GalleryExporter {
  GalleryExporter._();

  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/gallery');

  /// Résultat de l'export. Contient un flag de succès et, en cas
  /// d'échec, le code + message d'erreur côté natif pour qu'on puisse
  /// l'afficher dans le snackbar (au lieu d'un "indisponible" vague).
  static Future<GalleryExportResult> exportVideo({
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
      return GalleryExportResult(success: result ?? false);
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[Gallery] export ${e.code}: ${e.message}');
      }
      return GalleryExportResult(
        success: false,
        errorCode: e.code,
        errorMessage: e.message,
      );
    } on MissingPluginException {
      // Channel pas câblé (ex. iOS, ou build sans overlay)
      if (kDebugMode) debugPrint('[Gallery] channel manquant');
      return const GalleryExportResult(
        success: false,
        errorCode: 'NO_CHANNEL',
        errorMessage: 'Bridge natif manquant',
      );
    }
  }

  /// Convertit un enregistrement .ts en VRAI MP4 posé à côté de la
  /// source (même dossier, même nom, extension .mp4) : remux sans perte
  /// si les codecs sont compatibles, transcodage H.264+AAC sinon.
  /// Retourne le chemin du MP4 produit, ou `null` si la conversion est
  /// impossible (bridge natif absent, codec indécodable…). La source
  /// n'est jamais supprimée ici — c'est l'appelant qui décide.
  static Future<String?> convertToMp4(String srcPath) async {
    try {
      return await _channel.invokeMethod<String>(
        'convertToMp4',
        <String, dynamic>{'srcPath': srcPath},
      );
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[Gallery] convert ${e.code}: ${e.message}');
      }
      return null;
    } on MissingPluginException {
      // Channel pas câblé (ex. iOS, TV sans overlay) → on garde le .ts.
      return null;
    }
  }
}

class GalleryExportResult {
  const GalleryExportResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
  });

  final bool success;
  final String? errorCode;
  final String? errorMessage;

  /// Texte court pour le snackbar quand on échoue.
  String get userFacingError {
    if (success) return '';
    final String code = errorCode ?? 'UNKNOWN';
    final String msg = errorMessage ?? '';
    return msg.isEmpty ? code : '$code · $msg';
  }
}
