// =========================================================
//  tonight_plan.dart — « Qu'est-ce qu'il y a ce soir ? »
// =========================================================
//  Réponse 100 % locale. On ne contacte aucun serveur : on prend les
//  programmes déjà dans le guide (EPG) et on garde ceux qui passent
//  pendant la soirée.
//
//  Soirée = 18 h 00 → 01 h 00, heure de la box.
//  Entre minuit et 5 h, on est encore dans la soirée de la veille
//  (un film qui a commencé à 22 h est toujours « ce soir »).
//
//  Pur et synchrone : aucun accès disque, donc aucun risque de figer
//  le lecteur. L'écran interroge la base À CÔTÉ, puis appelle ceci.
// =========================================================

/// Bornes de la soirée, en heure locale.
class EveningWindow {
  const EveningWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// Un programme réduit à ce qu'il faut pour choisir et afficher.
class TonightProgram {
  const TonightProgram({
    required this.channelId,
    required this.title,
    required this.startMs,
    required this.stopMs,
    this.category,
  });

  final String channelId;
  final String title;
  final int startMs;
  final int stopMs;
  final String? category;
}

/// Une ligne montrée à l'écran (« 20:40 · Film · TF1 »).
class TonightSlot {
  const TonightSlot({
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.startMs,
    required this.stopMs,
    this.category,
    required this.canPlay,
  });

  final String channelId;
  final String channelName;
  final String title;
  final int startMs;
  final int stopMs;
  final String? category;

  /// Vrai si la chaîne est dans la playlist : OK peut l'ouvrir.
  /// Sinon la ligne reste lisible, mais on n'invente pas de flux.
  final bool canPlay;
}

class TonightLineup {
  const TonightLineup({
    required this.window,
    required this.slots,
  });

  final EveningWindow window;
  final List<TonightSlot> slots;

  bool get isEmpty => slots.isEmpty;
}

/// Soirée qui contient [now] (heure locale).
EveningWindow eveningWindow(DateTime now) {
  final DateTime local = now.toLocal();
  // Avant 5 h, la soirée a commencé hier à 18 h.
  final DateTime day = local.hour < 5
      ? DateTime(local.year, local.month, local.day)
          .subtract(const Duration(days: 1))
      : DateTime(local.year, local.month, local.day);
  final DateTime start = DateTime(day.year, day.month, day.day, 18);
  // 18 h + 7 h = 01 h le lendemain.
  final DateTime end = start.add(const Duration(hours: 7));
  return EveningWindow(start: start, end: end);
}

/// Choisit au plus [limit] programmes de la soirée.
///
/// [knownChannelIds] : chaînes vraiment dans la playlist. Une ligne
/// dont l'identifiant n'y est pas reste affichée (le guide le dit)
/// mais [TonightSlot.canPlay] est faux : on n'ouvrira pas un flux
/// imaginaire.
///
/// [channelNames] : nom à montrer. S'il manque, on affiche l'identifiant
/// tel quel plutôt que de planter.
TonightLineup planTonight({
  required DateTime now,
  required List<TonightProgram> programs,
  required Map<String, String> channelNames,
  Set<String>? knownChannelIds,
  int limit = 12,
}) {
  final EveningWindow window = eveningWindow(now);
  final int from = window.start.millisecondsSinceEpoch;
  final int to = window.end.millisecondsSinceEpoch;
  final int cap = limit < 1 ? 1 : (limit > 40 ? 40 : limit);

  final List<TonightProgram> overlapping = <TonightProgram>[];
  for (final TonightProgram p in programs) {
    final String title = p.title.trim();
    if (title.isEmpty) continue;
    if (p.stopMs <= p.startMs) continue;
    // Chevauchement : le programme n'est pas fini avant 18 h
    // et n'a pas commencé après 01 h.
    if (p.stopMs <= from || p.startMs >= to) continue;
    overlapping.add(p);
  }
  overlapping.sort((TonightProgram a, TonightProgram b) {
    final int byTime = a.startMs.compareTo(b.startMs);
    if (byTime != 0) return byTime;
    return a.title.compareTo(b.title);
  });

  final Set<String> seenTitles = <String>{};
  final List<TonightSlot> slots = <TonightSlot>[];
  for (final TonightProgram p in overlapping) {
    final String key = p.title.trim().toLowerCase();
    if (!seenTitles.add(key)) continue; // même émission sur 8 chaînes → une ligne
    // On ne joue la chaîne que si elle est vraiment dans la playlist.
    // Sans l'ensemble [knownChannelIds], on se rabat sur la table des noms
    // (même information, fournie par l'écran).
    final bool canPlay = knownChannelIds != null
        ? knownChannelIds.contains(p.channelId)
        : channelNames.containsKey(p.channelId);
    slots.add(TonightSlot(
      channelId: p.channelId,
      channelName: channelNames[p.channelId] ?? p.channelId,
      title: p.title.trim(),
      startMs: p.startMs,
      stopMs: p.stopMs,
      category: p.category,
      canPlay: canPlay,
    ));
    if (slots.length >= cap) break;
  }
  return TonightLineup(window: window, slots: slots);
}
