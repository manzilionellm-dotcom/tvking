// =========================================================
//  ffmpeg_converter.dart — Conversion .ts → .mp4 via FFmpeg
// =========================================================
//  POURQUOI FFmpeg (et pas MediaExtractor/MediaMuxer d'Android) :
//  nos enregistrements sont des flux MPEG-TS live (ou des segments HLS
//  concaténés). Le MediaExtractor natif d'Android n'arrive PAS à les
//  relire (pas de PAT/PMT en tête, discontinuités PCR…) → la conversion
//  native échoue sur TOUTES les chaînes, et l'export vers la galerie
//  sortait un fichier « incompatible » (point d'exclamation).
//
//  FFmpeg, lui, lit ces flux sans problème. On fait une conversion qui NE
//  TOUCHE PAS à la qualité vidéo :
//     -c:v copy   → la piste vidéo est COPIÉE telle quelle (aucune perte,
//                   très rapide même sur un match de 90 min) ;
//     -c:a aac    → seul l'audio est converti en AAC (l'AC-3/E-AC-3 des
//                   bouquets IPTV n'est pas lu par la galerie) ;
//     +faststart  → l'index (moov) est mis en tête → lecture immédiate.
//
//  Ce fichier importe `ffmpeg_kit_flutter_new_min`, qui n'existe PAS dans
//  le build TV (retiré du pubspec, comme media_kit). Il est donc appelé
//  UNIQUEMENT via le hook `tsToMp4Hook` posé par l'entrée mobile
//  (main.dart) → l'entrée TV (main_tv.dart) ne le référence jamais et il
//  n'est pas compilé côté TV.
// =========================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';

abstract final class FfmpegConverter {
  /// Convertit [srcPath] (un `.ts`) en `.mp4` posé À CÔTÉ (même nom, même
  /// dossier). Copie la vidéo, transcode l'audio en AAC. Retourne le chemin
  /// du `.mp4` produit, ou `null` si la conversion échoue (l'appelant garde
  /// alors le `.ts`, toujours lisible dans l'app).
  static Future<String?> tsToMp4(String srcPath) async {
    if (!srcPath.toLowerCase().endsWith('.ts')) return null;
    final File src = File(srcPath);
    if (!await src.exists() || await src.length() == 0) return null;

    final String outPath = '${srcPath.substring(0, srcPath.length - 3)}.mp4';
    // On n'écrase jamais un .mp4 déjà présent (nom horodaté → collision rare).
    final File out = File(outPath);
    try {
      if (await out.exists()) return outPath; // déjà converti
    } catch (_) {}

    // -y            : écrase la sortie temporaire au besoin
    // -fflags +genpts : régénère des timestamps propres (flux live tronqué)
    // -map 0:v:0? / 0:a:0? : 1re piste vidéo + 1re piste audio si présentes
    // -c:v copy     : VIDÉO copiée (aucune perte de qualité)
    // -c:a aac -b:a 160k : audio en AAC (compatible galerie)
    // -movflags +faststart : moov en tête → lecture immédiate
    final String cmd =
        '-y -fflags +genpts -i ${_q(srcPath)} -map 0:v:0? -map 0:a:0? '
        '-c:v copy -c:a aac -b:a 160k -movflags +faststart ${_q(outPath)}';

    try {
      final session = await FFmpegKit.execute(cmd);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) &&
          await out.exists() &&
          await out.length() > 0) {
        return outPath;
      }
      // Échec : on nettoie un éventuel .mp4 partiel.
      if (kDebugMode) {
        final logs = await session.getAllLogsAsString();
        debugPrint('[FFmpeg] conversion échouée : $logs');
      }
      try {
        if (await out.exists()) await out.delete();
      } catch (_) {}
      return null;
    } catch (e) {
      // Best-effort : sur un appareil sans la lib (ou trop ancien), on
      // retombe sur le chemin natif / on garde le .ts.
      if (kDebugMode) debugPrint('[FFmpeg] indisponible : $e');
      return null;
    }
  }

  /// Échappe un chemin pour la ligne de commande FFmpegKit (guillemets).
  static String _q(String p) => '"${p.replaceAll('"', r'\"')}"';
}
