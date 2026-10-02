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

  /// Repli « focus audio » : vrai = Media3 gère le focus (baisse à 20 %).
  static const String androidFocusKey = 'zuno.audio.focus.android';

  /// Repli « arrière-plan » : vrai = pause (ancien), faux = arrêt propre.
  static const String bgPauseKey = 'zuno.player.bg_pause_only';

  /// Repli « passage » : vrai = on n'attend pas l'AudioTrack (ancien).
  static const String immediateHandoffKey = 'zuno.audio.handoff.immediate';

  /// Correctif candidat H1 (02/10/2026) : vrai = mode système « appel »
  /// remis à normal avant chaque ouverture. Faux par défaut.
  static const String modeNormalKey = 'zuno.audio.fix.mode_normal';

  /// Essai H2 : type déclaré au système (« film » par défaut, « musique », « parole »).
  static const String contentTypeKey = 'zuno.audio.attr.content';

  static Future<void> load() async {
    var probe = false;
    var ffmpeg = false;
    var platform = false;
    var sessionWide = false;
    var androidFocus = false;
    var bgPause = false;
    var immediate = false;
    var modeNormal = false;
    var content = NativeVideoController.contentFilm;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      probe = prefs.getBool(probeKey) ?? false;
      ffmpeg = prefs.getBool(ffmpegKey) ?? false;
      platform = prefs.getBool(platformKey) ?? false;
      sessionWide = prefs.getBool(sessionWideKey) ?? false;
      androidFocus = prefs.getBool(androidFocusKey) ?? false;
      bgPause = prefs.getBool(bgPauseKey) ?? false;
      immediate = prefs.getBool(immediateHandoffKey) ?? false;
      modeNormal = prefs.getBool(modeNormalKey) ?? false;
      content = _validContent(prefs.getString(contentTypeKey));
    } catch (_) {
      probe = false;
      ffmpeg = false;
      platform = false;
      sessionWide = false;
      androidFocus = false;
      bgPause = false;
      immediate = false;
      modeNormal = false;
      content = NativeVideoController.contentFilm;
    }
    NativeVideoController.forceNormalAudioMode = modeNormal;
    NativeVideoController.audioContentType = content;
    NativeVideoController.audioProbeEnabled = probe;
    NativeVideoController.keepFfmpegAudio = ffmpeg;
    NativeVideoController.preferPlatformAac = platform;
    NativeVideoController.sessionWideFallback = sessionWide;
    NativeVideoController.androidAudioFocus = androidFocus;
    NativeVideoController.backgroundPauseOnly = bgPause;
    NativeVideoController.immediateHandoff = immediate;
    // Une vue déjà ouverte doit recevoir le réglage. Sinon l'écran
    // affiche « Spectre : mesuré » et le lecteur natif reste coupé.
    NativeVideoController.pushAudioDiagFlags();
  }

  /// Un texte inconnu ou illisible vaut « film » : le défaut v106.
  static String _validContent(String? raw) {
    switch (raw) {
      case NativeVideoController.contentMusique:
        return NativeVideoController.contentMusique;
      case NativeVideoController.contentParole:
        return NativeVideoController.contentParole;
      default:
        return NativeVideoController.contentFilm;
    }
  }

  static Future<void> setForceNormalMode(bool value) async {
    NativeVideoController.forceNormalAudioMode = value;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(modeNormalKey, value);
    } catch (_) {}
  }

  static Future<void> setContentType(String value) async {
    final String clean = _validContent(value);
    NativeVideoController.audioContentType = clean;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(contentTypeKey, clean);
    } catch (_) {}
  }

  /// Cycle film → musique → parole → film.
  static String nextContentType(String current) {
    switch (current) {
      case NativeVideoController.contentFilm:
        return NativeVideoController.contentMusique;
      case NativeVideoController.contentMusique:
        return NativeVideoController.contentParole;
      default:
        return NativeVideoController.contentFilm;
    }
  }

  static Future<void> setImmediateHandoff(bool value) async {
    NativeVideoController.immediateHandoff = value;
    NativeVideoController.pushAudioDiagFlags();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(immediateHandoffKey, value);
    } catch (_) {}
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
