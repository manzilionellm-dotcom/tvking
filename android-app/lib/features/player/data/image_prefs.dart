// =========================================================
//  image_prefs.dart — choix d'image mémorisés
// =========================================================
//  Matériel et cadence inchangés. Le contraste vidéo Android est
//  COUPÉ par défaut : l'image sort telle que le décodeur la livre
//  (aucune passe OpenGL). Un choix explicite (allumé ou coupé) reste
//  mémorisé. La capacité et le repli HDR sont décidés par le vrai
//  lecteur natif.
//
//  « Compatibilité HDR » (coupé par défaut) : retire Dolby Vision et
//  HDR10+ du flux avant le décodeur, le film passe en HDR10 simple.
//  À allumer sur une box où un film 4K donne un écran noir ou d'une
//  seule couleur avec le son. Les clés Amazon connues pour ce défaut
//  sont corrigées sans ce réglage (voir logic/HybridHdr.kt).
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/image_engine.dart';

class ImagePrefs {
  ImagePrefs._();

  static const String engineKey = 'zuno.player.image.engine.v1';
  static const String frameRateKey = 'zuno.player.image.fps.v1';
  static const String contrastKey = 'zuno.player.image.contrast.v1';
  static const String hdrCompatKey = 'zuno.player.image.hdr_compat.v1';

  static ImageEngine _engine = ImageEngine.hardware;
  static bool _frameRateMatch = false;
  static bool _lightContrast = false;
  static bool _hdrCompat = false;
  static bool _loaded = false;

  static ImageEngine get engine => _engine;
  static bool get frameRateMatch => _frameRateMatch;
  static bool get lightContrast => _lightContrast;
  static bool get hdrCompat => _hdrCompat;

  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _engine = ImageEngine.fromWire(prefs.getString(engineKey));
      _frameRateMatch = prefs.getBool(frameRateKey) ?? false;
      _lightContrast = prefs.getBool(contrastKey) ?? false;
      _hdrCompat = prefs.getBool(hdrCompatKey) ?? false;
    } catch (_) {
      _engine = ImageEngine.hardware;
      _frameRateMatch = false;
      _lightContrast = false;
      _hdrCompat = false;
    }
    NativeVideoController.defaultLightContrast = _lightContrast;
    // Statique : le lecteur l'envoie à chaque vue avant son adresse.
    NativeVideoController.hdrCompat = _hdrCompat;
    NativeVideoController.pushAudioDiagFlags();
    _loaded = true;
    changes.value++;
  }

  static Future<void> setEngine(ImageEngine value) async {
    _engine = value;
    _loaded = true;
    changes.value++;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(engineKey, value.wire);
    } catch (_) {
      // La valeur reste en mémoire pour la lecture en cours.
    }
  }

  static Future<void> setFrameRateMatch(bool value) async {
    _frameRateMatch = value;
    _loaded = true;
    changes.value++;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(frameRateKey, value);
    } catch (_) {
      // La valeur reste en mémoire pour la lecture en cours.
    }
  }

  static Future<void> setLightContrast(bool value) async {
    _lightContrast = value;
    _loaded = true;
    NativeVideoController.defaultLightContrast = value;
    changes.value++;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(contrastKey, value);
    } catch (_) {
      // Le choix reste appliqué à la lecture courante, même sans stockage.
    }
  }

  /// Pris en compte au prochain film ou à la prochaine chaîne : le
  /// décodeur en cours garde le flux qu'il a commencé à lire.
  static Future<void> setHdrCompat(bool value) async {
    _hdrCompat = value;
    _loaded = true;
    NativeVideoController.hdrCompat = value;
    NativeVideoController.pushAudioDiagFlags();
    changes.value++;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(hdrCompatKey, value);
    } catch (_) {
      // Le choix reste appliqué jusqu'à la fermeture de l'app.
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _engine = ImageEngine.hardware;
    _frameRateMatch = false;
    _lightContrast = false;
    _hdrCompat = false;
    _loaded = false;
    NativeVideoController.defaultLightContrast = false;
    NativeVideoController.hdrCompat = false;
  }
}
