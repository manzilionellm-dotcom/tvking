// =========================================================
//  decoder_fallback.dart — Quand changer de moteur vidéo
// =========================================================
//  Même échelle que le lecteur TV (matériel → logiciel → FFmpeg
//  s'il est vraiment là). On ne change PAS pour un trou de réseau.
//  On change si le décodeur vidéo a échoué, ou si l'image est noire
//  ou figée alors que la lecture est prête.
//
//  On ne revient pas au matériel tout seul : c'est lui qui vient
//  d'échouer. Une nouvelle chaîne repart du choix de la personne.
// =========================================================

import 'image_engine.dart';
import 'playback_error_taxonomy.dart';

enum PictureSignal {
  decode,
  blackOrFrozen,
  network,
  audio,
  other,
}

class DecoderDecision {
  const DecoderDecision({
    required this.engine,
    required this.reopen,
    required this.giveUp,
  });

  final ImageEngine engine;
  final bool reopen;
  final bool giveUp;
}

abstract final class DecoderFallback {
  /// Traduit une erreur libmpv déjà classée. L'audio et le réseau
  /// ne font pas changer de moteur vidéo.
  static PictureSignal fromCategory(PlaybackErrorCategory category) {
    switch (category) {
      case PlaybackErrorCategory.decoder:
        return PictureSignal.decode;
      case PlaybackErrorCategory.network:
        return PictureSignal.network;
      case PlaybackErrorCategory.tokenExpired:
      case PlaybackErrorCategory.source:
      case PlaybackErrorCategory.unknown:
        return PictureSignal.other;
    }
  }

  static DecoderDecision next({
    required ImageEngine current,
    required PictureSignal signal,
    required bool ffmpegVideoReady,
    required Set<ImageEngine> tried,
  }) {
    if (signal != PictureSignal.decode &&
        signal != PictureSignal.blackOrFrozen) {
      return DecoderDecision(engine: current, reopen: false, giveUp: false);
    }
    final List<ImageEngine> ladder = <ImageEngine>[
      ImageEngine.hardware,
      ImageEngine.software,
      if (ffmpegVideoReady) ImageEngine.ffmpeg,
    ];
    final int start = ladder.indexOf(current).clamp(0, ladder.length - 1);
    final Set<ImageEngine> blocked = <ImageEngine>{...tried, current};
    for (int i = start + 1; i < ladder.length; i++) {
      final ImageEngine candidate = ladder[i];
      if (!blocked.contains(candidate)) {
        return DecoderDecision(
          engine: candidate,
          reopen: true,
          giveUp: false,
        );
      }
    }
    return DecoderDecision(engine: current, reopen: false, giveUp: true);
  }
}

/// Image noire ou figée. On ne conclut PAS pendant le chargement.
abstract final class PictureHealth {
  static bool black({
    required bool decoderReady,
    required int framesRendered,
    required bool playbackReady,
    required bool buffering,
    required int elapsedMs,
    int timeoutMs = 8000,
  }) {
    if (!decoderReady || !playbackReady || buffering) return false;
    if (framesRendered > 0) return false;
    return elapsedMs >= timeoutMs;
  }

  static bool frozen({
    required int framesRendered,
    required bool playing,
    required bool buffering,
    required int msSinceLastFrame,
    int timeoutMs = 8000,
  }) {
    if (framesRendered <= 0 || !playing || buffering) return false;
    return msSinceLastFrame >= timeoutMs;
  }
}
