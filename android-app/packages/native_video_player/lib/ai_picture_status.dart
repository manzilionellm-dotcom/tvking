/// Motif court destiné à l'interface, sans exposer les détails GPU/pilote.
enum NativeAiFallback { fluidity, source, verification, unavailable }

/// État envoyé après le traitement d'une vraie image par le moteur natif.
/// La présence d'un modèle ou d'un score ne suffit jamais à activer l'IA.
/// Les mesures restent des diagnostics, pas une note de qualité d'image.
class NativeAiPictureStatus {
  const NativeAiPictureStatus._({
    required this.active,
    required this.reason,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.outputWidth,
    required this.outputHeight,
    this.sessionId,
    this.p95Ms,
    this.score,
    this.modelSha256,
  });

  final bool active;
  final String? reason;
  final int sourceWidth;
  final int sourceHeight;
  final int outputWidth;
  final int outputHeight;
  final int? sessionId;
  final double? p95Ms;
  final int? score;
  final String? modelSha256;

  NativeAiFallback get fallback => switch (reason) {
        'TOO_SLOW' || 'FRAME_DEADLINE' || 'MARGIN_LOST' || 'CADENCE_CHANGED' =>
          NativeAiFallback.fluidity,
        'HDR_OR_DRM' || 'NATIVE_4K' || 'UPSCALE_NOT_USEFUL' =>
          NativeAiFallback.source,
        'NOT_CONFIGURED' ||
        'SOURCE_UNKNOWN' ||
        'BENCHMARK_MISSING' ||
        'BENCHMARK_OTHER_MODEL' ||
        'BENCHMARK_OTHER_DRIVER' ||
        'BENCHMARK_OTHER_SIZE' ||
        'BENCHMARK_INCOMPLETE' ||
        'MEMORY_UNKNOWN' ||
        'PLAYBACK_STARTED' => NativeAiFallback.verification,
        _ => NativeAiFallback.unavailable,
      };

  /// Les changements de p95/score seuls ne doivent pas reconstruire l'écran
  /// à chaque image. Ils restent consultables dans le dernier diagnostic.
  bool hasSamePresentation(NativeAiPictureStatus? other) =>
      other != null && active == other.active && reason == other.reason;

  static NativeAiPictureStatus? read(Object? raw) {
    if (raw is! Map) return null;
    final Object? active = raw['active'];
    if (active is! bool) return null;
    final Object? rawReason = raw['reason'];
    final String? reason = rawReason is String && rawReason.trim().isNotEmpty
        ? rawReason.trim()
        : null;
    final int sourceWidth = _dimension(raw['sourceWidth']);
    final int sourceHeight = _dimension(raw['sourceHeight']);
    final int outputWidth = _dimension(raw['outputWidth']);
    final int outputHeight = _dimension(raw['outputHeight']);
    if (active) {
      // « ×2 » exige le contrat explicite ET une géométrie cohérente.
      // Un événement incomplet reste inconnu, jamais présumé actif.
      if (rawReason != null || raw['scale'] != 2 || sourceWidth == 0 ||
          sourceHeight == 0 || outputWidth != sourceWidth * 2 ||
          outputHeight != sourceHeight * 2) return null;
    } else if (reason == null) {
      return null;
    }
    final Object? p95 = raw['p95Ms'];
    final Object? score = raw['score'];
    final Object? session = raw['sessionId'];
    final Object? hash = raw['modelSha256'];
    return NativeAiPictureStatus._(
      active: active,
      reason: reason,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
      sessionId: session is int && session >= 0 ? session : null,
      p95Ms: p95 is num && p95.isFinite && p95 > 0 ? p95.toDouble() : null,
      score: score is int && score >= 0 ? score : null,
      modelSha256: hash is String && _sha256.hasMatch(hash) ? hash : null,
    );
  }

  static final RegExp _sha256 = RegExp(r'^[a-fA-F0-9]{64}$');
  static int _dimension(Object? value) =>
      value is int && value > 0 && value <= 32768 ? value : 0;
}
