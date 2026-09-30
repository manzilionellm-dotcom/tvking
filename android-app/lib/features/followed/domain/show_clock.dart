// =========================================================
//  show_clock.dart — Commence bientôt, en cours, ou fini
// =========================================================
//  Uniquement les heures du guide déjà sur la box. On compare
//  des instants (millisecondes), pas des horloges locales :
//  « dans 5 minutes » reste 5 minutes à Paris comme à Dakar.
//  Le créneau jour/heure, lui, est calculé à part (show_taste).
//
//  Guide vide, titre vide, horaire à l'envers : on rend une
//  liste vide. On ne lance pas d'exception.
// =========================================================

import 'show_title.dart';

/// La rangée montre « bientôt » jusqu'à 90 minutes.
/// Le bandeau, lui, n'attend que le délai choisi (souvent 5).
const int kHomeSoonMs = 90 * 60 * 1000;

/// Avant 3 minutes, c'est encore « en cours » (on n'a presque
/// rien raté). Après, c'est « déjà commencée ».
const int kLateAfterMs = 3 * 60 * 1000;

/// On dit « terminée » pendant 30 minutes, pas toute la soirée.
const int kFinishedWindowMs = 30 * 60 * 1000;

/// Rediffusion cherchée au plus dans les 36 heures.
const int kReplayHorizonMs = 36 * 60 * 60 * 1000;

/// Cartes de la rangée.
const int kShowRowMax = 8;

/// Délais proposés dans les réglages. Autre valeur → 5 minutes.
const List<int> kLeadChoices = <int>[2, 5, 10, 15];
const int kLeadDefault = 5;

int normalizeLead(int? raw) =>
    raw != null && kLeadChoices.contains(raw) ? raw : kLeadDefault;

/// Le délai suivant dans la liste (2 → 5 → 10 → 15 → 2).
int nextLead(int current) {
  final int safe = normalizeLead(current);
  final int i = kLeadChoices.indexOf(safe);
  return kLeadChoices[(i + 1) % kLeadChoices.length];
}

/// Une case du guide, déjà simplifiée pour le calcul.
class GuideSlot {
  const GuideSlot({
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.startMs,
    required this.stopMs,
    required this.catchupDeclared,
  });

  final String channelId;
  final String channelName;
  final String title;
  final int startMs;
  final int stopMs;

  /// La chaîne a DÉCLARÉ un rattrapage. On n'invente pas l'adresse.
  final bool catchupDeclared;
}

/// Où en est l'émission par rapport à maintenant.
enum ShowMoment { onAir, soon, started, finished }

/// Une émission suivie, placée dans le temps.
class ShowCue {
  const ShowCue({
    required this.title,
    required this.titleKey,
    required this.channelId,
    required this.channelName,
    required this.startMs,
    required this.stopMs,
    required this.moment,
    required this.minutes,
    required this.canRewind,
    this.replayChannelId,
    this.replayChannelName,
    this.replayStartMs,
  });

  final String title;
  final String titleKey;
  final String channelId;
  final String channelName;
  final int startMs;
  final int stopMs;
  final ShowMoment moment;

  /// Minutes avant le début, depuis le début, ou depuis la fin.
  final int minutes;

  /// Vrai seulement si la chaîne a déclaré un rattrapage ET que
  /// l'émission a déjà commencé (le début existe encore).
  final bool canRewind;

  final String? replayChannelId;
  final String? replayChannelName;
  final int? replayStartMs;

  bool get hasReplay =>
      replayChannelId != null &&
      replayChannelId!.isNotEmpty &&
      replayStartMs != null;

  /// Groupe de la rangée. Les 3 premières minutes restent
  /// « en cours » même si le bandeau dit déjà « il y a N minutes ».
  /// Le bandeau, lui, ne sonne qu'une fois : sa clé ne change pas
  /// à la 3e minute.
  ShowMoment get rowGroup {
    if (moment == ShowMoment.started && minutes < (kLateAfterMs ~/ 60000)) {
      return ShowMoment.onAir;
    }
    return moment;
  }

  /// Une fois ce rappel montré, on ne le remonte pas.
  /// « Bientôt », « déjà commencée » et « terminée » sont trois
  /// rappels différents. « Déjà commencée » ne se répète pas
  /// quand les minutes augmentent.
  String get alertKey => '$channelId@$startMs@${moment.name}';

  ShowCue withMinutes(int minutes) {
    return ShowCue(
      title: title,
      titleKey: titleKey,
      channelId: channelId,
      channelName: channelName,
      startMs: startMs,
      stopMs: stopMs,
      moment: moment,
      minutes: minutes < 0 ? 0 : minutes,
      canRewind: canRewind,
      replayChannelId: replayChannelId,
      replayChannelName: replayChannelName,
      replayStartMs: replayStartMs,
    );
  }
}

/// Rangée + un seul bandeau (le plus utile, pas déjà montré).
class ShowPlan {
  const ShowPlan({
    this.row = const <ShowCue>[],
    this.banner,
  });

  final List<ShowCue> row;
  final ShowCue? banner;

  static const ShowPlan empty = ShowPlan();
}

/// Construit la rangée et le bandeau.
///
/// [followed] : clés de titres (voir [showKey]).
/// [seen] : rappels déjà montrés ([ShowCue.alertKey]).
/// [leadMinutes] : délai du bandeau « commence dans ».
ShowPlan planShows({
  required int nowMs,
  required int leadMinutes,
  required List<GuideSlot> programs,
  required Set<String> followed,
  required Set<String> seen,
  int homeSoonMs = kHomeSoonMs,
  int finishedWindowMs = kFinishedWindowMs,
  int maxRow = kShowRowMax,
}) {
  if (programs.isEmpty || followed.isEmpty || maxRow <= 0) {
    return ShowPlan.empty;
  }
  final int leadMs = normalizeLead(leadMinutes) * 60000;
  final List<GuideSlot> clean = <GuideSlot>[
    for (final GuideSlot slot in programs)
      if (slot.stopMs > slot.startMs && showKey(slot.title).isNotEmpty) slot,
  ];
  if (clean.isEmpty) return ShowPlan.empty;

  final Map<String, ShowCue> byKey = <String, ShowCue>{};
  for (final GuideSlot slot in clean) {
    final String key = showKey(slot.title);
    if (!followed.contains(key)) continue;
    final ShowCue? cue = _cue(
      slot: slot,
      key: key,
      nowMs: nowMs,
      homeSoonMs: homeSoonMs,
      finishedWindowMs: finishedWindowMs,
      programs: clean,
    );
    if (cue == null) continue;
    byKey.putIfAbsent(cue.alertKey, () => cue);
  }
  if (byKey.isEmpty) return ShowPlan.empty;

  final List<ShowCue> all = byKey.values.toList();
  final List<ShowCue> row = <ShowCue>[
    for (final ShowMoment moment in <ShowMoment>[
      ShowMoment.onAir,
      ShowMoment.soon,
      ShowMoment.started,
    ])
      ...(_sorted(all.where((ShowCue c) => c.rowGroup == moment))),
  ];
  if (row.length > maxRow) {
    row.removeRange(maxRow, row.length);
  }

  ShowCue? banner;
  for (final ShowCue cue in _bannerOrder(all, nowMs, leadMs)) {
    if (seen.contains(cue.alertKey)) continue;
    banner = cue;
    break;
  }
  return ShowPlan(row: row, banner: banner);
}

/// Le bandeau encore affiché est-il toujours dans sa fenêtre ?
bool cueStillCurrent(ShowCue cue, int nowMs) {
  switch (cue.moment) {
    case ShowMoment.soon:
      return nowMs < cue.startMs;
    case ShowMoment.onAir:
    case ShowMoment.started:
      return nowMs < cue.stopMs;
    case ShowMoment.finished:
      return nowMs <= cue.stopMs + kFinishedWindowMs;
  }
}

ShowCue? _cue({
  required GuideSlot slot,
  required String key,
  required int nowMs,
  required int homeSoonMs,
  required int finishedWindowMs,
  required List<GuideSlot> programs,
}) {
  if (nowMs < slot.startMs) {
    final int delta = slot.startMs - nowMs;
    if (delta > homeSoonMs) return null;
    final int minutes = (delta / 60000).ceil().clamp(1, 100000).toInt();
    return _make(slot, key, ShowMoment.soon, minutes, rewind: false);
  }
  if (nowMs < slot.stopMs) {
    final int minutes = (nowMs - slot.startMs) ~/ 60000;
    // Moins d'une minute : « en cours », sans bandeau.
    // À partir d'une minute : « a commencé il y a N minutes »,
    // une seule fois pour cette diffusion. La rangée dit
    // « en cours » pendant les 3 premières minutes
    // (voir [ShowCue.rowGroup]), puis « déjà commencée ».
    if (minutes < 1) {
      return _make(slot, key, ShowMoment.onAir, 0, rewind: false);
    }
    return _make(
      slot,
      key,
      ShowMoment.started,
      minutes,
      rewind: slot.catchupDeclared,
    );
  }
  final int sinceEnd = nowMs - slot.stopMs;
  if (sinceEnd > finishedWindowMs) return null;
  final int minutes = sinceEnd ~/ 60000;
  final GuideSlot? replay = _replay(programs, slot, key, nowMs);
  return ShowCue(
    title: slot.title.trim(),
    titleKey: key,
    channelId: slot.channelId,
    channelName: slot.channelName,
    startMs: slot.startMs,
    stopMs: slot.stopMs,
    moment: ShowMoment.finished,
    minutes: minutes,
    canRewind: slot.catchupDeclared,
    replayChannelId: replay?.channelId,
    replayChannelName: replay?.channelName,
    replayStartMs: replay?.startMs,
  );
}

ShowCue _make(
  GuideSlot slot,
  String key,
  ShowMoment moment,
  int minutes, {
  required bool rewind,
}) {
  return ShowCue(
    title: slot.title.trim(),
    titleKey: key,
    channelId: slot.channelId,
    channelName: slot.channelName,
    startMs: slot.startMs,
    stopMs: slot.stopMs,
    moment: moment,
    minutes: minutes,
    canRewind: rewind,
  );
}

/// Plus tard, même titre. On préfère celle qui passe MAINTENANT,
/// sinon la plus proche dans les 36 heures.
GuideSlot? _replay(
  List<GuideSlot> programs,
  GuideSlot ended,
  String key,
  int nowMs,
) {
  GuideSlot? next;
  for (final GuideSlot slot in programs) {
    if (slot.channelId == ended.channelId && slot.startMs == ended.startMs) {
      continue;
    }
    if (showKey(slot.title) != key) continue;
    if (slot.startMs < ended.stopMs) continue;
    if (slot.startMs > nowMs + kReplayHorizonMs) continue;
    if (slot.startMs <= nowMs && nowMs < slot.stopMs) return slot;
    if (slot.startMs >= nowMs &&
        (next == null || slot.startMs < next.startMs)) {
      next = slot;
    }
  }
  return next;
}

List<ShowCue> _sorted(Iterable<ShowCue> cues) {
  final List<ShowCue> list = cues.toList()
    ..sort((ShowCue a, ShowCue b) => a.startMs.compareTo(b.startMs));
  return list;
}

/// Ordre du bandeau : tu rates le début, puis ça va commencer,
/// puis c'est fini. « En cours » depuis moins de 3 minutes
/// n'ouvre pas de bandeau : la rangée suffit.
List<ShowCue> _bannerOrder(List<ShowCue> all, int nowMs, int leadMs) {
  final List<ShowCue> started = _sorted(
    all.where((ShowCue c) => c.moment == ShowMoment.started),
  );
  final List<ShowCue> soon = _sorted(
    all.where((ShowCue c) {
      if (c.moment != ShowMoment.soon) return false;
      return c.startMs - nowMs <= leadMs;
    }),
  );
  final List<ShowCue> over = _sorted(
    all.where((ShowCue c) => c.moment == ShowMoment.finished),
  );
  return <ShowCue>[...started, ...soon, ...over];
}
