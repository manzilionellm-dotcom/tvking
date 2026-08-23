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
    this.sport = '',
    this.homeBadge = '',
    this.awayBadge = '',
    this.tier = 0,
    this.women = false,
    this.progress = '',
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

  /// Discipline (« Soccer », « Basketball », « Tennis »…) telle que la
  /// renvoie le panel. Sert à ranger les affiches par sport dans le coin
  /// Sport ; vide sur les sources anciennes, jamais bloquant.
  final String sport;

  /// Écussons des deux équipes (URL). La clé payante TheSportsDB les
  /// fournit pour presque toutes les équipes. Vides sur une source
  /// ancienne ou une équipe obscure : l'affichage DOIT rester correct
  /// sans eux, on ne réserve donc jamais la place « en attendant ».
  final String homeBadge;
  final String awayBadge;

  /// Importance de la compétition, décidée par le serveur :
  /// 1 = mondial (C1, Coupe du monde), 2 = grand championnat
  /// (Premier League, NBA, F1), 3 = notable (MLS, WNBA), 0 = inconnu.
  ///
  /// C'est le SERVEUR qui tranche, jamais l'app : la règle vit à un seul
  /// endroit et une correction ne demande aucune republication.
  final int tier;

  /// Compétition féminine. On ne la CACHE pas, on la NOMME — sans quoi
  /// « Italian Serie A Womens Cup » s'afficherait « Serie A » et le
  /// client croirait voir le championnat masculin.
  final bool women;

  /// Minute de jeu pendant un match EN DIRECT (« 21 »). Chaîne et non
  /// entier : TheSportsDB y met aussi « 45+2 ». Vide hors direct.
  final String progress;

  /// Le match est-il en train de se jouer ? `status` vaut alors 1H, 2H,
  /// HT, Q1… — et surtout PAS « FT » (fini), « NS » (pas commencé) ni
  /// vide. Liste blanche impossible (chaque sport a ses codes), donc on
  /// procède par exclusion des états terminaux, qui sont peu nombreux.
  static const Set<String> _notLive = <String>{
    'ft', 'aet', 'pen', 'ns', 'postp', 'canc', 'abd', 'awarded', 'tbd', '',
  };

  bool get isLive => !_notLive.contains(status.trim().toLowerCase());

  /// Ce qu'on affiche à la place du chrono. « 21' » pendant le jeu,
  /// « Mi-temps » à la pause. Vide si on ne sait pas.
  String get liveLabel {
    final String s = status.trim().toLowerCase();
    if (s == 'ht') return 'Mi-temps';
    if (progress.isNotEmpty) return "$progress'";
    return status.trim();
  }

  /// Titre à afficher quand il n'y a pas deux équipes — une course
  /// automobile ou un tournoi de tennis n'a pas de « domicile ».
  /// Sans ça, l'écran affichait « vs » tout seul.
  bool get isDuel => home.isNotEmpty && away.isNotEmpty;

  String get title => isDuel ? '$home vs $away' : (name.isNotEmpty ? name : league);

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
        sport: '${j['sport'] ?? ''}',
        homeBadge: '${j['homeBadge'] ?? ''}',
        awayBadge: '${j['awayBadge'] ?? ''}',
        // `tier` peut arriver en nombre OU en chaîne selon la route.
        // On passe par `toString()` puis `tryParse` : un format inattendu
        // donne 0, jamais une exception qui viderait tout l'écran.
        tier: int.tryParse('${j['tier'] ?? 0}') ?? 0,
        women: j['women'] == true,
        progress: '${j['progress'] ?? ''}',
      );

  /// Sérialisation — nécessaire pour MÉMORISER les matchs que le client
  /// choisit de suivre (FollowedMatchesService). Les clés sont les mêmes
  /// que celles de [fromJson] : ce qu'on écrit se relit tel quel.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'home': home,
        'away': away,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'date': date,
        'time': time,
        'timestamp': timestamp,
        'status': status,
        'league': league,
        'sport': sport,
        'homeBadge': homeBadge,
        'awayBadge': awayBadge,
        'tier': tier,
        'women': women,
        'progress': progress,
      };

  /// Recopie en changeant quelques champs. Sert au rafraîchissement EN
  /// DIRECT : on garde l'affiche telle qu'elle est (heure, écussons) et
  /// on ne remplace QUE le score et la minute. Sans ça, un match suivi
  /// perdrait ses informations à chaque tour de rafraîchissement.
  SportEvent copyWith({
    String? homeScore,
    String? awayScore,
    String? status,
    String? progress,
  }) =>
      SportEvent(
        id: id,
        name: name,
        home: home,
        away: away,
        homeScore: homeScore ?? this.homeScore,
        awayScore: awayScore ?? this.awayScore,
        date: date,
        time: time,
        timestamp: timestamp,
        status: status ?? this.status,
        league: league,
        sport: sport,
        homeBadge: homeBadge,
        awayBadge: awayBadge,
        tier: tier,
        women: women,
        progress: progress ?? this.progress,
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
