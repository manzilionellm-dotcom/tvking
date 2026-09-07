// =========================================================
//  match_detail.dart — La FICHE d'un match (modèles purs, zéro Flutter)
// =========================================================
//  Ce que le Worker renvoie sur /api/sports/event/:id (voir
//  cloudflare/sports_event.js) : l'événement, les statistiques, la
//  chronologie (buts, cartons, VAR, remplacements) et les compositions.
//
//  Tout est TOLÉRANT : un champ absent vaut vide ou null, jamais une
//  exception — une fiche qui plante à cause d'un champ manquant chez un
//  seul match est le pire des comportements possibles.
// =========================================================
import 'package:flutter/foundation.dart';

String _s(Object? v) => v == null ? '' : '$v';
int? _n(Object? v) => v == null ? null : int.tryParse('$v');

/// Une ligne de statistique : « Corner Kicks · 5 · 3 ».
@immutable
class MatchStat {
  const MatchStat({required this.name, this.home, this.away});
  final String name;
  final int? home;
  final int? away;

  factory MatchStat.fromJson(Map<String, dynamic> j) => MatchStat(
        name: _s(j['name']),
        home: _n(j['home']),
        away: _n(j['away']),
      );

  /// Part du domicile, entre 0 et 1, pour dessiner la barre. 0,5 quand
  /// rien n'est connu (barre neutre, pas de division par zéro).
  double get homeShare {
    final int h = home ?? 0;
    final int a = away ?? 0;
    if (h + a <= 0) return 0.5;
    return h / (h + a);
  }
}

/// Un événement de la chronologie : but, carton, VAR, remplacement…
@immutable
class MatchIncident {
  const MatchIncident({
    this.minute,
    this.type = '',
    this.detail = '',
    this.player = '',
    this.assist = '',
    this.team = '',
    this.home = false,
    this.comment = '',
  });

  final int? minute;

  /// `Goal` | `Card` | `Var` | `subst` … tel que la source le nomme.
  final String type;

  /// `Normal Goal` | `Penalty` | `Yellow Card` | `Red Card` | …
  final String detail;
  final String player;
  final String assist;
  final String team;
  final bool home;
  final String comment;

  bool get isGoal => type.toLowerCase() == 'goal';
  bool get isCard => type.toLowerCase() == 'card';
  bool get isRedCard => isCard && detail.toLowerCase().contains('red');
  bool get isYellowCard => isCard && detail.toLowerCase().contains('yellow');

  factory MatchIncident.fromJson(Map<String, dynamic> j) => MatchIncident(
        minute: _n(j['minute']),
        type: _s(j['type']),
        detail: _s(j['detail']),
        player: _s(j['player']),
        assist: _s(j['assist']),
        team: _s(j['team']),
        home: j['home'] == true,
        comment: _s(j['comment']),
      );
}

@immutable
class MatchPlayer {
  const MatchPlayer({
    required this.name,
    this.position = '',
    this.number,
    this.substitute = false,
    this.home = false,
    this.thumb = '',
  });
  final String name;
  final String position;
  final int? number;
  final bool substitute;
  final bool home;
  final String thumb;

  factory MatchPlayer.fromJson(Map<String, dynamic> j) => MatchPlayer(
        name: _s(j['name']),
        position: _s(j['position']),
        number: _n(j['number']),
        substitute: j['substitute'] == true,
        home: j['home'] == true,
        thumb: _s(j['thumb']),
      );
}

@immutable
class MatchDetail {
  const MatchDetail({
    required this.id,
    this.home = '',
    this.away = '',
    this.homeScore,
    this.awayScore,
    this.status = '',
    this.progress = '',
    this.league = '',
    this.venue = '',
    this.summary = '',
    this.thumb = '',
    this.homeFormation = '',
    this.awayFormation = '',
    this.stats = const <MatchStat>[],
    this.timeline = const <MatchIncident>[],
    this.homeLineup = const <MatchPlayer>[],
    this.awayLineup = const <MatchPlayer>[],
    this.statsAvailable = false,
    this.timelineAvailable = false,
    this.lineupAvailable = false,
  });

  final String id;
  final String home;
  final String away;
  final String? homeScore;
  final String? awayScore;
  final String status;
  final String progress;
  final String league;
  final String venue;

  /// Résumé rédigé par la source (anglais), vide si elle n'en a pas.
  final String summary;
  final String thumb;
  final String homeFormation;
  final String awayFormation;
  final List<MatchStat> stats;
  final List<MatchIncident> timeline;
  final List<MatchPlayer> homeLineup;
  final List<MatchPlayer> awayLineup;

  /// Le bloc a-t-il été JOINT côté serveur ? Sert à distinguer « pas
  /// encore de stats » (match pas commencé) de « source muette ».
  final bool statsAvailable;
  final bool timelineAvailable;
  final bool lineupAvailable;

  List<MatchIncident> get goals =>
      timeline.where((MatchIncident i) => i.isGoal).toList(growable: false);
  List<MatchIncident> get cards =>
      timeline.where((MatchIncident i) => i.isCard).toList(growable: false);

  /// La statistique dont le nom contient [needle] (sans la casse).
  MatchStat? stat(String needle) {
    final String k = needle.toLowerCase();
    for (final MatchStat s in stats) {
      if (s.name.toLowerCase().contains(k)) return s;
    }
    return null;
  }

  factory MatchDetail.fromJson(Map<String, dynamic> j) {
    final Object? ev = j['event'];
    final Map<String, dynamic> e =
        ev is Map<String, dynamic> ? ev : const <String, dynamic>{};
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) f) {
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(f)
          .toList(growable: false);
    }

    final Object? lu = j['lineup'];
    final Map<String, dynamic> lineup =
        lu is Map<String, dynamic> ? lu : const <String, dynamic>{};
    final Object? av = j['available'];
    final Map<String, dynamic> available =
        av is Map<String, dynamic> ? av : const <String, dynamic>{};
    return MatchDetail(
      id: _s(j['id']),
      home: _s(e['home']),
      away: _s(e['away']),
      homeScore: e['homeScore'] == null ? null : _s(e['homeScore']),
      awayScore: e['awayScore'] == null ? null : _s(e['awayScore']),
      status: _s(e['status']),
      progress: _s(e['progress']),
      league: _s(e['league']),
      venue: _s(e['venue']),
      summary: _s(e['summary']),
      thumb: _s(e['thumb']),
      homeFormation: _s(e['homeFormation']),
      awayFormation: _s(e['awayFormation']),
      stats: list(j['stats'], MatchStat.fromJson),
      timeline: list(j['timeline'], MatchIncident.fromJson),
      homeLineup: list(lineup['home'], MatchPlayer.fromJson),
      awayLineup: list(lineup['away'], MatchPlayer.fromJson),
      statsAvailable: available['stats'] == true,
      timelineAvailable: available['timeline'] == true,
      lineupAvailable: available['lineup'] == true,
    );
  }
}
