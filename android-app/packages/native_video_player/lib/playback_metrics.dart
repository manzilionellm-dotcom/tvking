/// Bilan natif fermé et borné. Aucun événement synthétique de l'interface ne
/// doit être envoyé à ce modèle par le contrôleur.
class NativePlaybackMetrics {
  const NativePlaybackMetrics._({
    required this.isSummary,
    required this.sessionId,
    required this.mediaId,
    required this.startedElapsedMs,
    required this.observedElapsedMs,
    required this.firstFrameElapsedMs,
    required this.startupMs,
    required this.elapsedMs,
    required this.droppedFrames,
    required this.droppedSource,
    required this.rebufferCount,
    required this.rebufferMs,
    required this.liveOffsetMs,
    required this.endReason,
  });

  final bool isSummary;
  final int sessionId;
  final int mediaId;
  final int startedElapsedMs;
  final int observedElapsedMs;
  final int? firstFrameElapsedMs;
  final int? startupMs;
  final int elapsedMs;
  final int? droppedFrames;
  final String? droppedSource;
  final int rebufferCount;
  final int rebufferMs;
  final int? liveOffsetMs;
  final String? endReason;

  static const int _max = 9000000000000000;
  static const Set<String> _endReasons = <String>{
    'media_changed',
    'silenced',
    'ended',
    'disposed',
    'disabled',
  };

  /// La validation du transport natif reste dans _onNativeCall. Cette
  /// lecture vérifie aussi les unités, les valeurs et les relations temporelles.
  static NativePlaybackMetrics? readNative(Object? raw) {
    if (raw is! Map<Object?, Object?> ||
        raw['schema'] != 1 ||
        raw['origin'] != 'android_media3') {
      return null;
    }
    final kind = raw['kind'];
    if (kind != 'first_frame' && kind != 'summary') return null;
    int? number(String key, {bool signed = false}) {
      final value = raw[key];
      return value is int && value >= (signed ? -_max : 0) && value <= _max
          ? value
          : null;
    }

    final session = number('sessionId');
    final media = number('mediaId');
    final started = number('startedElapsedMs');
    final observed = number('observedElapsedMs');
    final elapsed = number('elapsedMs');
    final count = number('rebufferCount');
    final rebuffer = number('rebufferMs');
    if (session == null ||
        session == 0 ||
        media == null ||
        media == 0 ||
        started == null ||
        observed == null ||
        elapsed == null ||
        count == null ||
        rebuffer == null ||
        observed < started ||
        elapsed != observed - started ||
        rebuffer > elapsed) {
      return null;
    }
    final first = number('firstFrameElapsedMs');
    final startup = number('startupMs');
    final dropped = number('droppedFrames');
    final live = number('liveOffsetMs', signed: true);
    for (final key in <String>[
      'firstFrameElapsedMs',
      'startupMs',
      'droppedFrames',
      'liveOffsetMs'
    ]) {
      if (raw[key] != null &&
          number(key, signed: key == 'liveOffsetMs') == null) {
        return null;
      }
    }
    if ((first == null) != (startup == null) ||
        (first != null &&
            (first < started ||
                first > observed ||
                startup != first - started)) ||
        (kind == 'first_frame' && first == null)) {
      return null;
    }
    final source = raw['droppedSource'];
    if (dropped == null
        ? source != null
        : source != 'decoder' && source != 'listener') {
      return null;
    }
    final reason = raw['endReason'];
    if (kind == 'summary' ? !_endReasons.contains(reason) : reason != null) {
      return null;
    }
    return NativePlaybackMetrics._(
      isSummary: kind == 'summary',
      sessionId: session,
      mediaId: media,
      startedElapsedMs: started,
      observedElapsedMs: observed,
      firstFrameElapsedMs: first,
      startupMs: startup,
      elapsedMs: elapsed,
      droppedFrames: dropped,
      droppedSource: source as String?,
      rebufferCount: count,
      rebufferMs: rebuffer,
      liveOffsetMs: live,
      endReason: reason as String?,
    );
  }

  /// Les chaînes libres reçues sur le canal n'entrent jamais dans ce texte.
  String toBlackBoxLine() {
    String known(int? value) => value?.toString() ?? 'indisponible';
    return 'Mesures natives Media3 : session=$sessionId média=$mediaId '
        'origine=android_media3 début_ms=$startedElapsedMs '
        'première_image_ms=${known(firstFrameElapsedMs)} '
        'démarrage_ms=${known(startupMs)} durée_ms=$elapsedMs '
        'images_perdues=${known(droppedFrames)} '
        'compteur=${droppedSource ?? 'indisponible'} '
        'rebufferings=$rebufferCount rebuffering_ms=$rebufferMs '
        'retard_direct_ms=${known(liveOffsetMs)} fin=${endReason ?? 'en_cours'}';
  }
}
