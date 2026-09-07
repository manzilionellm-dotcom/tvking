// =========================================================
//  sport_ordering_test.dart — Les règles d'ordre du coin Sport
// =========================================================
//  Demande du propriétaire (07/09/2026) : filtres « Football, Basket,
//  Tennis, Baseball », football par défaut, jamais en dernier ; matchs
//  en direct d'abord, puis à venir triés par heure.
//
//  Chaque test reprend une phrase de la demande. Si une règle change un
//  jour, c'est ici qu'on le verra, pas sur le téléphone d'un client.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/sports/domain/match_detail.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';
import 'package:tv_king/features/sports/domain/sport_ordering.dart';

SportEvent _m(String id,
        {DateTime? kickoff, String status = '', String? hs, String? as}) =>
    SportEvent(
      id: id,
      home: 'A',
      away: 'B',
      status: status,
      homeScore: hs,
      awayScore: as,
      timestamp: kickoff == null ? '' : kickoff.toUtc().toIso8601String(),
    );

void main() {
  final DateTime now = DateTime.utc(2026, 9, 7, 18);

  group('ordre des filtres', () {
    test('Football, Basket, Tennis, Baseball d\'abord, dans cet ordre', () {
      final List<String> r = orderSports(<String>[
        'Tennis', 'Ice Hockey', 'Baseball', 'Soccer', 'Rugby', 'Basketball',
      ]);
      expect(r.sublist(0, 4), <String>['Soccer', 'Basketball', 'Tennis', 'Baseball']);
      expect(r.sublist(4), <String>['Ice Hockey', 'Rugby'],
          reason: 'le reste suit, alphabétique');
    });

    test('le football n\'est JAMAIS en dernier', () {
      final List<String> r = orderSports(<String>['Rugby', 'Soccer']);
      expect(r.first, 'Soccer');
      expect(r.last, isNot('Soccer'));
    });

    test('une discipline épinglée absente n\'est pas inventée', () {
      expect(orderSports(<String>['Rugby', 'Tennis']), <String>['Tennis', 'Rugby']);
    });

    test('la casse de la source ne casse pas l\'épinglage', () {
      expect(orderSports(<String>['soccer', 'BASKETBALL']),
          <String>['soccer', 'BASKETBALL']);
    });

    test('football sélectionné par défaut ; sinon la première ; sinon rien',
        () {
      expect(defaultSport(<String>['Basketball', 'Soccer']), 'Soccer');
      expect(defaultSport(<String>['Tennis', 'Rugby']), 'Tennis');
      expect(defaultSport(<String>[]), isNull);
    });
  });

  group('ordre des matchs', () {
    final Set<String> liveIds = <String>{'live1', 'live2'};
    bool isLive(SportEvent e) => liveIds.contains(e.id);

    test('EN DIRECT en tête, dans l\'ordre de la source, puis à venir par heure',
        () {
      final List<SportEvent> r = orderMatches(<SportEvent>[
        _m('soir', kickoff: now.add(const Duration(hours: 3))),
        _m('live2', status: '2H'),
        _m('bientot', kickoff: now.add(const Duration(minutes: 30))),
        _m('live1', status: '1H'),
        _m('demain', kickoff: now.add(const Duration(days: 1))),
      ], isLive: isLive, now: now);
      expect(r.map((SportEvent e) => e.id).toList(),
          <String>['live2', 'live1', 'bientot', 'soir', 'demain']);
    });

    test('un résultat d\'hier ne cache pas le match de ce soir', () {
      final List<SportEvent> r = orderMatches(<SportEvent>[
        _m('hier', kickoff: now.subtract(const Duration(days: 1)), hs: '2', as: '1'),
        _m('ce_soir', kickoff: now.add(const Duration(hours: 2))),
      ], isLive: isLive, now: now);
      expect(r.map((SportEvent e) => e.id).toList(), <String>['ce_soir', 'hier']);
    });

    test('sans horaire connu → en dernier, jamais jeté', () {
      final List<SportEvent> r = orderMatches(<SportEvent>[
        _m('inconnu'),
        _m('ce_soir', kickoff: now.add(const Duration(hours: 2))),
      ], isLive: isLive, now: now);
      expect(r.map((SportEvent e) => e.id).toList(), <String>['ce_soir', 'inconnu']);
    });
  });

  group('fiche d\'un match : lecture du JSON', () {
    test('stats, chronologie et compositions sont lues', () {
      final MatchDetail d = MatchDetail.fromJson(<String, dynamic>{
        'id': '2494022',
        'event': <String, dynamic>{
          'home': 'Arsenal', 'away': 'Chelsea', 'homeScore': '2', 'awayScore': '1',
          'status': 'FT', 'league': 'English Premier League', 'summary': 'Arsenal…',
        },
        'stats': <Object>[
          <String, dynamic>{'name': 'Corner Kicks', 'home': 5, 'away': 3},
        ],
        'timeline': <Object>[
          <String, dynamic>{'minute': 25, 'type': 'Goal', 'detail': 'Normal Goal', 'player': 'Havertz', 'home': true},
          <String, dynamic>{'minute': 14, 'type': 'Card', 'detail': 'Yellow Card', 'player': 'Pedro', 'home': false},
        ],
        'lineup': <String, dynamic>{
          'home': <Object>[<String, dynamic>{'name': 'Raya', 'position': 'Goalkeeper', 'number': 1, 'home': true}],
          'away': <Object>[],
        },
        'available': <String, dynamic>{'stats': true, 'timeline': true, 'lineup': true},
      });
      expect(d.home, 'Arsenal');
      expect(d.stat('corner')!.home, 5);
      expect(d.stat('corner')!.homeShare, closeTo(0.625, 0.001));
      expect(d.goals.single.player, 'Havertz');
      expect(d.cards.single.isYellowCard, isTrue);
      expect(d.homeLineup.single.number, 1);
      expect(d.statsAvailable, isTrue);
    });

    test('un JSON vide ou malformé donne une fiche vide, jamais une exception',
        () {
      final MatchDetail d = MatchDetail.fromJson(<String, dynamic>{
        'id': '1', 'event': 'pas un objet', 'stats': 42, 'lineup': null,
      });
      expect(d.home, isEmpty);
      expect(d.stats, isEmpty);
      expect(d.homeLineup, isEmpty);
      expect(d.statsAvailable, isFalse);
      expect(const MatchStat(name: 'x').homeShare, 0.5,
          reason: 'sans chiffres : barre neutre, pas de division par zéro');
    });
  });
}
