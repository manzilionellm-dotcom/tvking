// =========================================================
//  audio_diag_prefs.dart — Interrupteurs coupés par défaut
// =========================================================
//  • sonde PCM (mesure seulement, ne filtre pas le son)
//  • réessayer FFmpeg à la prochaine chaîne
//  • essayer le décodeur AAC de la box à la prochaine chaîne
//  Une préférence absente ou illisible reste FAUSSE : on ne change
//  pas le chemin audio tout seul.
// =========================================================

import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioDiagPrefs {
  AudioDiagPrefs._();

  static const String probeKey = 'zuno.audio.diag.probe';
  static const String ffmpegKey = 'zuno.audio.fix.ffmpeg';
  static const String platformKey = 'zuno.audio.fix.platform';

  /// Repli du correctif « repli AAC par chaîne » : vrai = ancien
  /// comportement (une panne FFmpeg → la box pour toutes les chaînes).
  static const String sessionWideKey = 'zuno.audio.fix.session_fallback';

  static Future<void> load() async {
    var probe = false;
    var ffmpeg = false;
    var platform = false;
    var sessionWide = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      probe = prefs.getBool(probeKey) ?? false;
      ffmpeg = prefs.getBool(ffmpegKey) ?? false;
      platform = prefs.getBool(platformKey) ?? false;
      sessionWide = prefs.getBool(sessionWideKey) ?? false;
    } catch (_) {
      probe = false;
      ffmpeg = false;
      platform = false;
      sessionWide = false;
    }
    NativeVideoController.audioProbeEnabled = probe;
    NativeVideoController.keepFfmpegAudio = ffmpeg;
    NativeVideoController.preferPlatformAac = platform;
    NativeVideoController.sessionWideFallback = sessionWide;
  }

  static Future<void> setSessionWideFallback(bool value) async {
    NativeVideoController.sessionWideFallback = value;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(sessionWideKey, value);
    } catch (_) {}
  }

  static Future<void> setProbe(bool value) async {
    NativeVideoController.audioProbeEnabled = value;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(probeKey, value);
    } catch (_) {}
  }

  static Future<void> setKeepFfmpeg(bool value) async {
    NativeVideoController.keepFfmpegAudio = value;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ffmpegKey, value);
    } catch (_) {}
  }

  static Future<void> setPreferPlatform(bool value) async {
    NativeVideoController.preferPlatformAac = value;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(platformKey, value);
    } catch (_) {}
  }
}
