// Données publiques : aucune chaîne TV, vidéo ou adresse de flux.
// OpenLigaDB fournit des scores communautaires. OpenFootball fournit des
// calendriers et des résultats différés, jamais une promesse de direct.
import 'dart:convert';

enum FootballSource { openLigaDb, openFootball }

enum FootballCompetition {
  bundesliga('Bundesliga', FootballSource.openLigaDb, 'bl1'),
  bundesliga2('2. Bundesliga', FootballSource.openLigaDb, 'bl2'),
  ligue1('Ligue 1', FootballSource.openFootball, 'fr.1'),
  premierLeague('Premier League', FootballSource.openFootball, 'en.1'),
  laLiga('La Liga', FootballSource.openFootball, 'es.1'),
  serieA('Serie A', FootballSource.openFootball, 'it.1');

  const FootballCompetition(this.label, this.source, this.code);
  final String label;
  final FootballSource source;
  final String code;
}

class FootballGoal {
  const FootballGoal({required this.home, required this.away, this.minute, this.player = ''});
  final int home;
  final int away;
  final int? minute;
  final String player;
}

class FootballMatch {
  const FootballMatch({required this.home, required this.away,
    required this.startsAt, this.homeScore, this.awayScore,
    this.finished = false, this.goals = const <FootballGoal>[]});
  final String home;
  final String away;
  final DateTime startsAt;
  final int? homeScore;
  final int? awayScore;
  final bool finished;
  final List<FootballGoal> goals;
  bool get hasScore => homeScore != null && awayScore != null;
}

/// Décodage pur, exécuté hors du fil UI. L'ordre des résultats OpenLigaDB
/// n'est pas une garantie : le type 2 désigne le score du match, le type 1
/// la mi-temps (documentation officielle OpenLigaDB).
List<FootballMatch> decodeFootballFeed((FootballSource, String) payload) {
  final dynamic body = jsonDecode(payload.$2);
  final List<dynamic> rows;
  if (payload.$1 == FootballSource.openLigaDb) {
    if (body is! List<dynamic>) throw const FormatException('Matchs attendus');
    rows = body;
  } else {
    if (body is! Map<String, dynamic> || body['matches'] is! List<dynamic>) {
      throw const FormatException('Calendrier attendu');
    }
    rows = body['matches'] as List<dynamic>;
  }
  final List<FootballMatch> result = <FootballMatch>[];
  for (final dynamic row in rows) {
    if (row is! Map<String, dynamic>) throw const FormatException('Match illisible');
    result.add(payload.$1 == FootballSource.openLigaDb
        ? _openLigaMatch(row) : _openFootballMatch(row));
  }
  result.sort((FootballMatch a, FootballMatch b) => a.startsAt.compareTo(b.startsAt));
  return result;
}

FootballMatch _openLigaMatch(Map<String, dynamic> row) {
  final Map<String, dynamic> first = row['team1'] as Map<String, dynamic>;
  final Map<String, dynamic> second = row['team2'] as Map<String, dynamic>;
  final List<dynamic> scores = row['matchResults'] as List<dynamic>;
  Map<String, dynamic>? score;
  for (final dynamic candidate in scores) {
    if (candidate is Map<String, dynamic> && candidate['resultTypeID'] == 2) {
      score = candidate;
    }
  }
  final List<FootballGoal> goals = <FootballGoal>[];
  for (final dynamic goal in row['goals'] as List<dynamic>? ?? <dynamic>[]) {
    if (goal is! Map<String, dynamic>) throw const FormatException('But illisible');
    goals.add(FootballGoal(home: goal['scoreTeam1'] as int,
      away: goal['scoreTeam2'] as int, minute: goal['matchMinute'] as int?,
      player: goal['goalGetterName'] as String? ?? ''));
  }
  goals.sort((FootballGoal a, FootballGoal b) => (a.minute ?? 0).compareTo(b.minute ?? 0));
  return FootballMatch(home: first['teamName'] as String,
    away: second['teamName'] as String,
    // Seul le champ UTC est utilisé ; l'heure allemande n'est pas locale
    // pour tous les clients de Zuno.
    startsAt: DateTime.parse(row['matchDateTimeUTC'] as String),
    homeScore: score?['pointsTeam1'] as int?, awayScore: score?['pointsTeam2'] as int?,
    finished: row['matchIsFinished'] == true, goals: goals);
}

FootballMatch _openFootballMatch(Map<String, dynamic> row) {
  final dynamic score = row['score'];
  final dynamic fullTime = score is Map<String, dynamic> ? score['ft'] : null;
  final bool validScore = fullTime is List<dynamic> && fullTime.length == 2
      && fullTime[0] is int && fullTime[1] is int;
  return FootballMatch(home: row['team1'] as String, away: row['team2'] as String,
    // La source ne donne pas de fuseau : montrer le jour, pas convertir
    // arbitrairement son heure en heure du téléviseur.
    startsAt: DateTime.parse(row['date'] as String),
    homeScore: validScore ? fullTime[0] as int : null,
    awayScore: validScore ? fullTime[1] as int : null, finished: validScore);
}
