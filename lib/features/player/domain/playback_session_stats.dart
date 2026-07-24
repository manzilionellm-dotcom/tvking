// =========================================================
//  playback_session_stats.dart — Agrégats d'UNE session de lecture
// =========================================================
//  USINE v2 / S3 : le lecteur émettait déjà des ÉVÉNEMENTS isolés
//  (première frame, coupures, erreurs, reconnexions watchdog) mais
//  aucun AGRÉGAT par session. Or les métriques reines du streaming
//  sont des ratios de session :
//
//    • TTFF (time-to-first-frame) — le ressenti « ça démarre vite » ;
//    • taux de démarrage réussi   — a-t-on VU une frame, oui ou non ;
//    • ratio de rebuffering        — temps gelé / temps de lecture ;
//    • nombre de stalls            — coupures APRÈS la 1re frame ;
//    • erreurs par famille (cf. playback_error_taxonomy.dart) ;
//    • reconnexions watchdog       — les zombies devenus données.
//
//  Classe PURE : aucun import Flutter/media_kit, l'horloge est
//  INJECTABLE (les tests pilotent le temps, jamais de flakiness).
//  Une session = « ouverture (ou zap) → fermeture (ou zap suivant) »,
//  elle SURVIT aux retries/reconnexions internes : c'est exactement
//  ce que vit l'utilisateur.
// =========================================================

import 'playback_error_taxonomy.dart';

/// Résumé figé d'une session de lecture, produit par
/// [PlaybackSessionStats.summarize].
class PlaybackSessionSummary {
  const PlaybackSessionSummary({
    required this.isLive,
    required this.started,
    required this.ttffMs,
    required this.sessionMs,
    required this.bufferingMs,
    required this.stallCount,
    required this.rebufferRatio,
    required this.errorCounts,
    required this.recoveryCount,
  });

  /// Live (ou catch-up assimilé) vs VOD — les budgets diffèrent.
  final bool isLive;

  /// `true` si au moins UNE frame a été décodée (session « démarrée »).
  /// Le taux de démarrage réussi agrégé = moyenne de ce booléen.
  final bool started;

  /// Ouverture → première frame, en ms. `null` si jamais démarré.
  final int? ttffMs;

  /// Durée totale de la session (ouverture → fermeture), en ms.
  final int sessionMs;

  /// Temps cumulé en buffering APRÈS la première frame, en ms.
  final int bufferingMs;

  /// Nombre de gels (passages en buffering) APRÈS la première frame.
  final int stallCount;

  /// bufferingMs / temps écoulé depuis la première frame. 0 si jamais
  /// démarré (le raté de démarrage est porté par [started], pas ici).
  final double rebufferRatio;

  /// Erreurs FATALES par famille (label stable → occurrences).
  final Map<String, int> errorCounts;

  /// Reconnexions automatiques (watchdog position figée, EOF live…).
  final int recoveryCount;

  /// Session saine = démarrée, sans erreur fatale, ratio de
  /// rebuffering sous 5 % (seuil industrie usuel) et 0 reconnexion.
  bool get healthy =>
      started &&
      errorCounts.isEmpty &&
      recoveryCount == 0 &&
      rebufferRatio < 0.05;

  /// Ligne compacte pour la boîte noire (grep-able, une seule ligne).
  String toLogLine() {
    final StringBuffer b = StringBuffer()
      ..write('session ')
      ..write(isLive ? 'live' : 'vod')
      ..write(started ? ' demarree' : ' JAMAIS DEMARREE')
      ..write(ttffMs == null ? '' : ' ttff=${ttffMs}ms')
      ..write(' duree=${sessionMs}ms')
      ..write(' stalls=$stallCount')
      ..write(' rebuffer=${(rebufferRatio * 100).toStringAsFixed(1)}%')
      ..write(' reconnexions=$recoveryCount');
    if (errorCounts.isNotEmpty) {
      final String errs = errorCounts.entries
          .map((MapEntry<String, int> e) => '${e.key}:${e.value}')
          .join(',');
      b.write(' erreurs=$errs');
    }
    return b.toString();
  }
}

/// Accumulateur d'événements d'une session de lecture.
///
/// Cycle : construire à l'ouverture (ou au zap), nourrir depuis les
/// listeners existants du lecteur, puis [summarize] à la fermeture
/// (ou juste avant le zap suivant). Chaque méthode est idempotente
/// là où l'événement peut se répéter (doubles émissions media_kit).
class PlaybackSessionStats {
  PlaybackSessionStats({required this.isLive, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _openedAt = _clock();
  }

  final bool isLive;
  final DateTime Function() _clock;

  late final DateTime _openedAt;
  DateTime? _firstFrameAt;
  DateTime? _bufferingSince; // non-null = gel en cours (post-1re frame)
  int _bufferingMs = 0;
  int _stallCount = 0;
  int _recoveryCount = 0;
  final Map<String, int> _errorCounts = <String, int>{};

  /// Première frame réellement décodée. Seule la PREMIÈRE compte
  /// (les reprises internes ne remettent pas le chrono à zéro : le
  /// TTFF est le ressenti du démarrage initial).
  void onFirstFrame() {
    _firstFrameAt ??= _clock();
  }

  /// À brancher sur `stream.buffering`. Avant la première frame, le
  /// buffering est le CHARGEMENT normal : il est porté par le TTFF,
  /// pas compté comme stall.
  void onBuffering(bool buffering) {
    if (_firstFrameAt == null) return;
    if (buffering) {
      if (_bufferingSince != null) return; // double émission → ignorée
      _bufferingSince = _clock();
      _stallCount++;
    } else {
      final DateTime? since = _bufferingSince;
      if (since == null) return;
      _bufferingSince = null;
      _bufferingMs += _clock().difference(since).inMilliseconds;
    }
  }

  /// Erreur FATALE (celles que l'UI affiche ou qui déclenchent la
  /// cascade) — les warnings filtrés ne passent pas par ici.
  void onError(PlaybackErrorCategory category) {
    final String key = PlaybackErrorTaxonomy.label(category);
    _errorCounts[key] = (_errorCounts[key] ?? 0) + 1;
  }

  /// Reconnexion automatique (watchdog position figée, EOF live…).
  void onRecovery() {
    _recoveryCount++;
  }

  /// Fige et renvoie le résumé. Un gel encore ouvert est clôturé à
  /// l'instant de l'appel (sinon son temps serait perdu).
  PlaybackSessionSummary summarize() {
    final DateTime now = _clock();
    onBuffering(false); // clôt un éventuel gel en cours
    final int sessionMs = now.difference(_openedAt).inMilliseconds;
    final DateTime? ff = _firstFrameAt;
    final int? ttffMs = ff?.difference(_openedAt).inMilliseconds;
    final int playedMs =
        ff == null ? 0 : now.difference(ff).inMilliseconds;
    final double ratio =
        playedMs <= 0 ? 0 : (_bufferingMs / playedMs).clamp(0, 1).toDouble();
    return PlaybackSessionSummary(
      isLive: isLive,
      started: ff != null,
      ttffMs: ttffMs,
      sessionMs: sessionMs,
      bufferingMs: _bufferingMs,
      stallCount: _stallCount,
      rebufferRatio: ratio,
      errorCounts: Map<String, int>.unmodifiable(_errorCounts),
      recoveryCount: _recoveryCount,
    );
  }
}
