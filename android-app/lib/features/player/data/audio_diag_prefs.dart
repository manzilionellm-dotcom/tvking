// =========================================================
//  audio_diag_prefs.dart — Interrupteurs coupés par défaut
// =========================================================
//  • sonde PCM (mesure seulement, ne filtre pas le son)
//  • réessayer FFmpeg à la prochaine chaîne
//  • essayer le décodeur AAC de la box à la prochaine chaîne
//  Une préférence absente ou illisible reste FAUSSE : on ne change
//  pas le chemin audio tout seul.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// Repli « focus audio » : vrai = Media3 gère le focus (baisse à 20 %).
  static const String androidFocusKey = 'zuno.audio.focus.android';

  /// Repli « arrière-plan » : vrai = pause (ancien), faux = arrêt propre.
  static const String bgPauseKey = 'zuno.player.bg_pause_only';

  /// Repli « passage » : vrai = on n'attend pas l'AudioTrack (ancien).
  static const String immediateHandoffKey = 'zuno.audio.handoff.immediate';

  /// Garde « mode appel ». Vrai = demander le retour à normal si Android
  /// est en chemin d'appel. Faux par défaut : setMode n'est pas appelé.
  static const String restoreNormalKey = 'zuno.audio.mode.normal';

  static Future<void> load() async {
    var probe = false;
    var ffmpeg = false;
    var platform = false;
    var sessionWide = false;
    var androidFocus = false;
    var bgPause = false;
    var immediate = false;
    var restoreNormal = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      probe = prefs.getBool(probeKey) ?? false;
      ffmpeg = prefs.getBool(ffmpegKey) ?? false;
      platform = prefs.getBool(platformKey) ?? false;
      sessionWide = prefs.getBool(sessionWideKey) ?? false;
      androidFocus = prefs.getBool(androidFocusKey) ?? false;
      bgPause = prefs.getBool(bgPauseKey) ?? false;
      immediate = prefs.getBool(immediateHandoffKey) ?? false;
      restoreNormal = prefs.getBool(restoreNormalKey) ?? false;
    } catch (_) {
      probe = false;
      ffmpeg = false;
      platform = false;
      sessionWide = false;
      androidFocus = false;
      bgPause = false;
      immediate = false;
      restoreNormal = false;
    }
    NativeVideoController.audioProbeEnabled = probe;
    NativeVideoController.keepFfmpegAudio = ffmpeg;
    NativeVideoController.preferPlatformAac = platform;
    NativeVideoController.sessionWideFallback = sessionWide;
    NativeVideoController.androidAudioFocus = androidFocus;
    NativeVideoController.backgroundPauseOnly = bgPause;
    NativeVideoController.immediateHandoff = immediate;
    NativeVideoController.restoreNormalMode = restoreNormal;
    // Une vue déjà ouverte doit recevoir le réglage. Sinon l'écran
    // affiche « Spectre : mesuré » et le lecteur natif reste coupé.
    NativeVideoController.pushAudioDiagFlags();
  }

  static Future<void> setImmediateHandoff(bool value) async {
    NativeVideoController.immediateHandoff = value;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(immediateHandoffKey, value);
    } catch (_) {}
  }

  /// Allume ou coupe la garde. Coupé : on prévient le natif pour qu'il
  /// n'appelle pas setMode, et on ne lit pas le mode. Allumé : la vue
  /// ExoPlayer déjà ouverte le fait tout de suite ; le téléphone
  /// (lecteur mpv) le fait à l'ouverture suivante, ou via
  /// [AudioModeGuardClient.ask] si l'écran veut la phrase tout de suite.
  static Future<void> setRestoreNormalMode(bool value) async {
    NativeVideoController.restoreNormalMode = value;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(restoreNormalKey, value);
    } catch (_) {}
    if (!value) {
      // Prévenir le téléphone : le canal ne doit plus appeler setMode.
      // L'argument faux ne lit pas le mode et ne le change pas.
      await AudioModeGuardClient.notifyOff();
    }
  }

  static Future<void> setAndroidFocus(bool value) async {
    NativeVideoController.androidAudioFocus = value;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(androidFocusKey, value);
    } catch (_) {}
  }

  static Future<void> setBackgroundPauseOnly(bool value) async {
    NativeVideoController.backgroundPauseOnly = value;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(bgPauseKey, value);
    } catch (_) {}
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

/// Demande Android « reviens à normal » seulement si l'interrupteur
/// est allumé. La phrase renvoyée ne contient aucune adresse de flux.
/// Coupé : [ask] ne parle pas au natif. [notifyOff] envoie faux, et le
/// natif ne lit pas le mode.
abstract final class AudioModeGuardClient {
  static const MethodChannel _channel =
      MethodChannel('native_video_player/mode_guard');

  static Future<String?> ask() async {
    if (!NativeVideoController.restoreNormalMode) return null;
    try {
      return await _channel.invokeMethod<String>('restoreIfStuck', true);
    } catch (e) {
      debugPrint('[Mode audio] demande non faite : $e');
      return null;
    }
  }

  static Future<void> notifyOff() async {
    try {
      await _channel.invokeMethod<void>('restoreIfStuck', false);
    } catch (e) {
      debugPrint('[Mode audio] coupure non transmise : $e');
    }
  }
}
