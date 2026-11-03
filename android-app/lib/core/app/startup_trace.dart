import 'package:flutter/foundation.dart';

/// Jalons de démarrage : uniquement des noms fixes et des durées, jamais
/// d'identifiant appareil, d'URL, de préférence ou de donnée de playlist.
abstract final class StartupTrace {
  static final Stopwatch _clock = Stopwatch()..start();

  static void mark(String stage) {
    debugPrint('[ZunoStartup] ${_clock.elapsedMilliseconds}ms $stage');
  }

  static Future<T> step<T>(String stage, Future<T> Function() work) async {
    mark('$stage.begin');
    try {
      final T result = await work();
      mark('$stage.end');
      return result;
    } catch (_) {
      mark('$stage.failed');
      rethrow;
    }
  }
}
