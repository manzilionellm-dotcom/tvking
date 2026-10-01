// =========================================================
//  audio_diag_prefs.dart — Deux interrupteurs, coupés par défaut
// =========================================================
//  • sonde PCM (mesure seulement, ne filtre pas le son)
//  • réessayer FFmpeg à la prochaine chaîne
//  Une préférence absente ou illisible reste FAUSSE : on ne change
//  pas le chemin audio tout seul.
// =========================================================

import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioDiagPrefs {
  AudioDiagPrefs._();

  static const String probeKey = 'zuno.audio.diag.probe';
  static const String ffmpegKey = 'zuno.audio.fix.ffmpeg';

  static Future<void> load() async {
    var probe = false;
    var ffmpeg = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      probe = prefs.getBool(probeKey) ?? false;
      ffmpeg = prefs.getBool(ffmpegKey) ?? false;
    } catch (_) {
      probe = false;
      ffmpeg = false;
    }
    NativeVideoController.audioProbeEnabled = probe;
    NativeVideoController.keepFfmpegAudio = ffmpeg;
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
}
