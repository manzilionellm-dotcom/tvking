// =========================================================
//  image_prefs.dart — choix d'image mémorisés
// =========================================================
//  Coupés / matériel par défaut : c'est le comportement des
//  versions 102 à 104. Une préférence illisible revient à ça.
//  Le contraste n'est pas mémorisé « allumé » : cette version
//  ne l'applique pas (voir PictureTuneChoice).
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/image_engine.dart';

class ImagePrefs {
  ImagePrefs._();

  static const String engineKey = 'zuno.player.image.engine.v1';
  static const String frameRateKey = 'zuno.player.image.fps.v1';

  static ImageEngine _engine = ImageEngine.hardware;
  static bool _frameRateMatch = false;
  static bool _loaded = false;

  static ImageEngine get engine => _engine;
  static bool get frameRateMatch => _frameRateMatch;

  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _engine = ImageEngine.fromWire(prefs.getString(engineKey));
      _frameRateMatch = prefs.getBool(frameRateKey) ?? false;
    } catch (_) {
      _engine = ImageEngine.hardware;
      _frameRateMatch = false;
    }
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
}
