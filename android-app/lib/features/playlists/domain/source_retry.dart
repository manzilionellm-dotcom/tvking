// =========================================================
//  source_retry.dart — Une liste qui échoue ne bloque pas les autres
// =========================================================
//  Mesuré le 05/10/2026 sur la box de test : trois listes servies, dont
//  deux avec un mot de passe faux. À chaque tour (toutes les 25 s tant
//  que la box n'a pas de chaîne), la box réessayait les listes dans
//  l'ordre du serveur : la mauvaise d'abord (jusqu'à 2 min de silence),
//  puis la bonne, puis encore la mauvaise. Résultat : les listes
//  envoyées à 19 h s'installaient à 23 h.
//
//  Règle : une liste refusée est mise de côté un moment (5 min, puis
//  15, 45 min, 2 h, 6 h au plus), et passe APRÈS les listes jamais
//  refusées. Un ordre explicite du panel (« source ») remet tout le
//  monde en course une fois. Pur, testé.
// =========================================================

/// Dernier échec connu d'une liste (par empreinte).
class SourceFailure {
  const SourceFailure({required this.at, required this.count});

  /// Millisecondes epoch du dernier refus.
  final int at;

  /// Refus d'affilée.
  final int count;

  Map<String, Object?> toJson() => <String, Object?>{'at': at, 'n': count};

  static SourceFailure? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final int at = (raw['at'] as num?)?.toInt() ?? 0;
    final int n = (raw['n'] as num?)?.toInt() ?? 0;
    if (at <= 0 || n <= 0) return null;
    return SourceFailure(at: at, count: n);
  }
}

/// Délais de mise de côté, par nombre de refus d'affilée.
const List<Duration> kSourceRetryBackoff = <Duration>[
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(minutes: 45),
  Duration(hours: 2),
  Duration(hours: 6),
];

Duration sourceRetryDelay(int failures) {
  if (failures <= 0) return Duration.zero;
  final int i = failures - 1;
  return kSourceRetryBackoff[i >= kSourceRetryBackoff.length
      ? kSourceRetryBackoff.length - 1
      : i];
}

/// Ce que le tour doit faire : [tryNow] dans l'ordre (jamais refusées
/// d'abord, puis les refusées dont le délai est passé), [skipped] mises
/// de côté. Les empreintes inconnues (`null`) sont toujours tentées.
class SourceRetryPlan {
  const SourceRetryPlan({required this.tryNow, required this.skipped});

  final List<int> tryNow;
  final List<int> skipped;
}

/// [fingerprints] : empreinte de chaque liste servie (index = position
/// serveur), `null` si elle n'en a pas. [force] : ordre explicite du
/// panel ou passe manuelle → tout est tenté, les refusées en dernier.
/// [retryAlways] : repli (ancien comportement, ordre du serveur).
SourceRetryPlan planSourceRetry({
  required List<String?> fingerprints,
  required Map<String, SourceFailure> failures,
  required int nowMs,
  bool force = false,
  bool retryAlways = false,
}) {
  if (retryAlways) {
    return SourceRetryPlan(
      tryNow: List<int>.generate(fingerprints.length, (int i) => i),
      skipped: const <int>[],
    );
  }
  final List<int> fresh = <int>[];
  final List<int> due = <int>[];
  final List<int> skipped = <int>[];
  for (int i = 0; i < fingerprints.length; i++) {
    final String? fp = fingerprints[i];
    final SourceFailure? f = fp == null ? null : failures[fp];
    if (f == null) {
      fresh.add(i);
      continue;
    }
    final int readyAt = f.at + sourceRetryDelay(f.count).inMilliseconds;
    if (force || nowMs >= readyAt) {
      due.add(i);
    } else {
      skipped.add(i);
    }
  }
  return SourceRetryPlan(tryNow: <int>[...fresh, ...due], skipped: skipped);
}

/// Mémoire après un tour : un succès efface l'échec, un refus l'augmente.
Map<String, SourceFailure> noteSourceOutcome(
  Map<String, SourceFailure> failures, {
  required String fingerprint,
  required bool succeeded,
  required int nowMs,
}) {
  final Map<String, SourceFailure> next = Map<String, SourceFailure>.of(failures);
  if (succeeded) {
    next.remove(fingerprint);
    return next;
  }
  final int count = (next[fingerprint]?.count ?? 0) + 1;
  next[fingerprint] = SourceFailure(at: nowMs, count: count);
  return next;
}
