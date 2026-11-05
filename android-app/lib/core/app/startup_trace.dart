import 'dart:async';
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';

/// Jalons de démarrage : uniquement des noms fixes et des durées, jamais
/// d'identifiant appareil, d'URL, de préférence ou de donnée de playlist.
abstract final class StartupTrace {
  static final Stopwatch _clock = Stopwatch()..start();

  static void mark(String stage) {
    debugPrint('[ZunoStartup] ${_clock.elapsedMilliseconds}ms $stage');
  }

  /// En debug seulement. On laisse passer la première image (shaders),
  /// puis on note 24 images. p50 / p90 / max, en millisecondes.
  /// Une image au-dessus de 16 ms compte comme lente. Rien n'est envoyé.
  /// Le mode release ne branche pas ce rappel.
  static void watchFrames() {
    if (!kDebugMode) return;
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      final List<int> spans = <int>[];
      debugPrint('[ZunoStartup] frames.watch');
      PlatformDispatcher.instance.onReportTimings = (List<FrameTiming> timings) {
        for (final FrameTiming timing in timings) {
          spans.add(timing.totalSpan.inMilliseconds);
        }
        if (spans.length < 24) return;
        PlatformDispatcher.instance.onReportTimings = null;
        spans.sort();
        final int p50 = spans[spans.length ~/ 2];
        final int p90 =
            spans[(spans.length * 0.9).floor().clamp(0, spans.length - 1)];
        final int slow = spans.where((int ms) => ms > 16).length;
        debugPrint(
          '[ZunoStartup] frames n=${spans.length} p50=${p50}ms '
          'p90=${p90}ms max=${spans.last}ms slow16=$slow',
        );
      };
    });
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
