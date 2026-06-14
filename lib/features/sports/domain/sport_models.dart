// =========================================================
//  sport_models.dart — Équipe + Match (TheSportsDB via Worker)
// =========================================================
import 'package:flutter/foundation.dart';

@immutable
class SportTeam {
  const SportTeam({
    required this.id,
    required this.name,
    this.badge = '',
    this.league = '',
    this.sport = '',
  });

  final String id;
  final String name;
  final String badge; // URL du logo
  final String league;
  final String sport;

  factory SportTeam.fromJson(Map<String, dynamic> j) => SportTeam(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        badge: '${j['badge'] ?? ''}',
        league: '${j['league'] ?? ''}',
        sport: '${j['sport'] ?? ''}',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'badge': badge,
        'league': league,
        'sport': sport,
      };
}

@immutable
class SportEvent {
  const SportEvent({
    required this.id,
    this.name = '',
    this.home = '',
    this.away = '',
    this.homeScore,
    this.awayScore,
    this.date = '',
    this.time = '',
    this.timestamp = '',
    this.status = '',
    this.league = '',
  });

  final String id;
  final String name;
  final String home;
  final String away;
  final String? homeScore;
  final String? awayScore;
  final String date; // YYYY-MM-DD
  final String time; // HH:MM:SS
  final String timestamp; // ISO UTC (TheSportsDB strTimestamp)
  final String status;
  final String league;

  bool get hasScore =>
      homeScore != null &&
      homeScore!.isNotEmpty &&
      awayScore != null &&
      awayScore!.isNotEmpty;

  /// Date/heure de début du match (UTC → local), si connue.
  DateTime? get startsAt {
    if (timestamp.isNotEmpty) {
      final DateTime? dt = DateTime.tryParse(timestamp);
      if (dt != null) return dt.toLocal();
    }
    if (date.isNotEmpty) {
      final DateTime? dt = DateTime.tryParse(
          '${date}T${time.isEmpty ? '00:00:00' : time}Z');
      if (dt != null) return dt.toLocal();
    }
    return null;
  }

  factory SportEvent.fromJson(Map<String, dynamic> j) => SportEvent(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        home: '${j['home'] ?? ''}',
        away: '${j['away'] ?? ''}',
        homeScore: j['homeScore'] == null ? null : '${j['homeScore']}',
        awayScore: j['awayScore'] == null ? null : '${j['awayScore']}',
        date: '${j['date'] ?? ''}',
        time: '${j['time'] ?? ''}',
        timestamp: '${j['timestamp'] ?? ''}',
        status: '${j['status'] ?? ''}',
        league: '${j['league'] ?? ''}',
      );

  /// « 14/06 21:00 » (date + heure courtes) si dispo.
  String get whenLabel {
    if (date.isEmpty) return '';
    String dm = date;
    final List<String> p = date.split('-'); // YYYY-MM-DD
    if (p.length == 3) dm = '${p[2]}/${p[1]}';
    final String hm = time.length >= 5 ? time.substring(0, 5) : time;
    return hm.isEmpty ? dm : '$dm · $hm';
  }

  /// Libellé compact pour le bandeau défilant.
  String get ticker => hasScore
      ? '$home $homeScore–$awayScore $away'
      : (whenLabel.isEmpty ? '$home vs $away' : '$home vs $away · $whenLabel');
}
