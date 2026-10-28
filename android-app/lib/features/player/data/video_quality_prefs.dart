import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Choix de la piste source, sans filtre artificiel ni modification du décodeur.
enum VideoQuality {
  auto('auto'),
  maximum('maximum');

  const VideoQuality(this.wire);
  final String wire;

  static VideoQuality fromWire(String? value) =>
      value == maximum.wire ? maximum : auto;
}

/// Préférence indépendante du moteur : changer la qualité ne doit pas relancer
/// le décodeur matériel après un repli réussi vers le décodeur logiciel.
class VideoQualityPrefs {
  VideoQualityPrefs._();

  static const String key = 'zuno.player.video.quality.v1';
  static final ValueNotifier<VideoQuality> changes =
      ValueNotifier<VideoQuality>(VideoQuality.auto);
  static Future<void>? _loading;
  static Future<void> _saving = Future<void>.value();

  static VideoQuality get value => changes.value;

  static Future<void> load() => _loading ??= _read();

  static Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      changes.value = VideoQuality.fromWire(prefs.getString(key));
    } catch (_) {
      changes.value = VideoQuality.auto;
    }
  }

  static Future<void> set(VideoQuality quality) async {
    await load();
    changes.value = quality;
    // Des appuis rapides conservent leur ordre aussi sur le stockage Android.
    _saving = _saving.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, quality.wire);
      } catch (_) {
        // Le réglage reste utilisable pour cette session même si l'écriture échoue.
      }
    });
    await _saving;
  }

  @visibleForTesting
  static void resetForTesting() {
    _loading = null;
    _saving = Future<void>.value();
    changes.value = VideoQuality.auto;
  }
}
