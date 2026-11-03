// =========================================================
//  image_prefs.dart — choix d'image mémorisés
// =========================================================
//  Matériel et cadence inchangés. Le contraste vidéo Android est
//  actif par défaut ; une désactivation explicite reste mémorisée.
//  La capacité et le repli HDR sont décidés par le vrai lecteur natif.
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

  static ImageEngine _engine = ImageEngine.hardware;
  static bool _frameRateMatch = false;
  static bool _lightContrast = true;
  static bool _loaded = false;

  static ImageEngine get engine => _engine;
  static bool get frameRateMatch => _frameRateMatch;
  static bool get lightContrast => _lightContrast;

  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _engine = ImageEngine.fromWire(prefs.getString(engineKey));
      _frameRateMatch = prefs.getBool(frameRateKey) ?? false;
      _lightContrast = prefs.getBool(contrastKey) ?? true;
    } catch (_) {
      _engine = ImageEngine.hardware;
      _frameRateMatch = false;
      _lightContrast = true;
    }
    NativeVideoController.defaultLightContrast = _lightContrast;
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

  @visibleForTesting
  static void resetForTesting() {
    _engine = ImageEngine.hardware;
    _frameRateMatch = false;
    _lightContrast = true;
    _loaded = false;
    NativeVideoController.defaultLightContrast = true;
  }
}
