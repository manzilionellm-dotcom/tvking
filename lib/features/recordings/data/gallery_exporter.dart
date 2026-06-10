// =========================================================
//  gallery_exporter.dart — Export d'enregistrements vers Galerie
// =========================================================
//  Wrapper Dart au-dessus du MethodChannel
//  `com.manzilionellm.tvking/gallery` (impl Kotlin dans
//  android_overlay/google_cast/GalleryExporter.kt).
//
//  Le `RecordingRepository` sauvegarde des .ts (MPEG-TS) dans le storage
//  privé de l'app. Ce .ts n'est PAS lisible par la galerie native du
//  téléphone (image cassée, lecture seulement via VLC).
//
//  STRATÉGIE (2026) — sortie LISIBLE PARTOUT :
//    1. On REMUXE d'abord le .ts en VRAI .mp4 avec ffmpeg (`-c copy` :
//       copie des pistes, AUCUN ré-encodage vidéo, AUCUNE perte). ffmpeg
//       avale les .ts « live » cabossés que le remux natif (MediaExtractor)
//       refusait. Si l'audio n'est pas muxable en MP4 (MP2/AC3 sur certains
//       appareils), on ré-encode UNIQUEMENT l'audio en AAC.
//    2. On passe ce .mp4 propre au natif (GalleryExporter.kt) qui l'insère
//       dans MediaStore (Movies/) → visible et lisible dans la Galerie.
//    Si ffmpeg échoue/indispo, on retombe sur le chemin natif d'origine.
//
//  Ne touche NI au moteur d'enregistrement NI à la lecture vidéo.
// =========================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class GalleryExporter {
  GalleryExporter._();

  static const MethodChannel _channel =
      MethodChannel('com.manzilionellm.tvking/gallery');

  /// Exporte un enregistrement vers la Galerie. Pré-remux ffmpeg pour
  /// garantir un MP4 lisible partout, puis insertion MediaStore (natif).
  static Future<GalleryExportResult> exportVideo({
    required String srcPath,
    required String displayName,
  }) async {
    String pathToExport = srcPath;
    String? tempMp4;

    // 1) Pré-remux ffmpeg .ts → .mp4 propre (best-effort).
    try {
      final String? remuxed = await _ffmpegRemux(srcPath);
      if (remuxed != null) {
        pathToExport = remuxed;
        tempMp4 = remuxed;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Gallery] ffmpeg remux indispo: $e');
    }

    // 2) Insertion dans la galerie via le natif (avec le .mp4 si dispo).
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'exportVideo',
        <String, dynamic>{
          'srcPath': pathToExport,
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
      if (kDebugMode) debugPrint('[Gallery] channel manquant');
      return const GalleryExportResult(
        success: false,
        errorCode: 'NO_CHANNEL',
        errorMessage: 'Bridge natif manquant',
      );
    } finally {
      // Nettoyage du .mp4 temporaire (le natif l'a déjà copié en galerie).
      if (tempMp4 != null) {
        try {
          final File f = File(tempMp4);
          if (await f.exists()) await f.delete();
        } catch (_) {/* best-effort */}
      }
    }
  }

  /// Remuxe `srcPath` (.ts) en VRAI .mp4 via ffmpeg. Renvoie le chemin du
  /// .mp4, ou `null` si échec (l'appelant retombe sur le remux natif).
  /// La vidéo n'est JAMAIS ré-encodée (copie de piste = sans perte).
  static Future<String?> _ffmpegRemux(String srcPath) async {
    final String lower = srcPath.toLowerCase();
    // Déjà un conteneur lisible → on laisse le natif faire.
    if (!lower.endsWith('.ts')) return null;

    final String out = '$srcPath.export.mp4';
    try {
      final File o = File(out);
      if (await o.exists()) await o.delete();
    } catch (_) {}

    // Tentative 1 — LOSSLESS : copie vidéo + audio (quasi instantané).
    if (await _runFfmpeg(
      "-y -hide_banner -loglevel error -i '$srcPath' "
      "-map 0:v:0 -map 0:a:0? -dn -sn -c copy -movflags +faststart '$out'",
      out,
    )) {
      return out;
    }

    // Tentative 2 — audio exotique (MP2/AC3) non muxable : on ré-encode
    // SEULEMENT l'audio en AAC, la vidéo reste copiée (sans perte).
    if (await _runFfmpeg(
      "-y -hide_banner -loglevel error -i '$srcPath' "
      "-map 0:v:0 -map 0:a:0? -dn -sn -c:v copy -c:a aac -b:a 192k "
      "-movflags +faststart '$out'",
      out,
    )) {
      return out;
    }

    return null;
  }

  /// Exécute une commande ffmpeg ; true si succès ET fichier de sortie
  /// non vide. Nettoie le fichier partiel en cas d'échec.
  static Future<bool> _runFfmpeg(String command, String out) async {
    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        final File f = File(out);
        if (await f.exists() && await f.length() > 0) return true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Gallery] ffmpeg exec: $e');
    }
    try {
      final File f = File(out);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    return false;
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
