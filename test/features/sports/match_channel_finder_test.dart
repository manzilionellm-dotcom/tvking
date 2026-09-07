// =========================================================
//  match_channel_finder_test.dart — « Sur quelle chaîne ? »
// =========================================================
//  Ce qui est verrouillé ici, et POURQUOI chaque cas existe :
//
//    1. L'INSTANT INTERROGÉ. C'est le défaut qui a motivé tout ce
//       travail : on cherchait « ce qui passe MAINTENANT » pour un match
//       qui commence dans trente minutes, et la réponse était forcément
//       « aucune chaîne ». Si quelqu'un remet `now` à la place du coup
//       d'envoi, ces tests tombent.
//
//    2. LES DEUX ÉQUIPES D'ABORD. « Barracas Central / Argentinos
//       Juniors » est le match ; « Magazine Barracas » ne l'est pas. Une
//       correspondance complète doit toujours battre une partielle,
//       QUEL QUE SOIT l'ordre dans lequel le guide les rend.
//
//    3. LES NOMS TROP COURTS SONT ÉCARTÉS. Chercher « FC » dans les
//       titres du guide ramènerait la moitié du sport mondial.
//
//  Ces trois décisions sont PURES (aucune base, aucun réseau) : elles
//  sont exposées pour être testées telles quelles.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/sports/data/match_channel_finder.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

SportEvent _ev({
  String home = 'Barracas Central',
  String away = 'Argentinos Juniors',
  String name = '',
  String status = 'NS',
  String timestamp = '',
}) =>
    SportEvent(
      id: 'e1',
      name: name,
      home: home,
      away: away,
      date: '',
      time: '',
      timestamp: timestamp,
      status: status,
      league: 'Argentinian Primera',
      sport: 'Soccer',
    );

EpgProgram _prog(String title, {String channelId = 'c1'}) => EpgProgram(
      channelId: channelId,
      startTime: 0,
      stopTime: 1,
      title: title,
    );

void main() {
  group('À quel instant interroger le guide', () {
    final DateTime maintenant = DateTime(2026, 9, 7, 21, 30);

    test('match à venir : on vise le COUP D\'ENVOI, pas maintenant', () {
      // Le cas exact du propriétaire : il est 21 h 30, le match est à 22 h.
      // On ne compare JAMAIS à une heure locale écrite en dur : le CI
      // tourne en UTC, la box du client non. Tout se mesure par rapport
      // à `startsAt`, donc le test dit la même chose sous tout fuseau.
      final SportEvent e = _ev(timestamp: '2026-09-07T20:00:00Z');
      final int at = MatchChannelFinder.lookupInstant(e, maintenant);
      expect(at, isNot(maintenant.millisecondsSinceEpoch),
          reason: 'chercher « maintenant » ne trouve jamais un match à venir');
      final DateTime vise = DateTime.fromMillisecondsSinceEpoch(at);
      expect(vise.isAfter(e.startsAt!), isTrue,
          reason: 'on vise APRÈS le coup d\'envoi, pas l\'avant-match');
      expect(vise.difference(e.startsAt!).inMinutes, 10);
    });

    test('match EN COURS : on vise maintenant', () {
      final SportEvent e = _ev(status: '2H', timestamp: '2026-09-07T18:00:00Z');
      expect(MatchChannelFinder.lookupInstant(e, maintenant),
          maintenant.millisecondsSinceEpoch);
    });

    test('heure inconnue : on retombe sur maintenant, sans planter', () {
      final SportEvent e = _ev(timestamp: '');
      expect(MatchChannelFinder.lookupInstant(e, maintenant),
          maintenant.millisecondsSinceEpoch);
    });
  });

  group('Ce qu\'on cherche dans le guide', () {
    test('les deux équipes', () {
      expect(MatchChannelFinder.searchTerms(_ev()),
          <String>['Barracas Central', 'Argentinos Juniors']);
    });

    test('un nom trop court est écarté (un LIKE « FC » ramène tout)', () {
      final List<String> t =
          MatchChannelFinder.searchTerms(_ev(home: 'FC', away: 'Lens'));
      expect(t, <String>['Lens']);
    });

    test('épreuve sans duel : on cherche le nom de l\'épreuve', () {
      final List<String> t = MatchChannelFinder.searchTerms(
          _ev(home: '', away: '', name: 'Grand Prix de Monza'));
      expect(t, <String>['Grand Prix de Monza']);
    });

    test('rien d\'exploitable : liste vide, aucune requête ne partira', () {
      expect(MatchChannelFinder.searchTerms(_ev(home: '', away: '', name: '')),
          isEmpty);
    });
  });

  group('Choisir le bon programme', () {
    final List<String> noms = <String>['Barracas Central', 'Argentinos Juniors'];

    test('les DEUX équipes battent une seule, même arrivée en second', () {
      final EpgProgram? best = MatchChannelFinder.bestMatch(
        <EpgProgram>[
          _prog('Magazine Barracas Central', channelId: 'magazine'),
          _prog('Barracas Central / Argentinos Juniors', channelId: 'match'),
        ],
        noms,
      );
      expect(best?.channelId, 'match');
    });

    test('les DEUX équipes gagnent aussi quand elles arrivent en premier', () {
      final EpgProgram? best = MatchChannelFinder.bestMatch(
        <EpgProgram>[
          _prog('Barracas Central - Argentinos Juniors', channelId: 'match'),
          _prog('Résumé Argentinos Juniors', channelId: 'resume'),
        ],
        noms,
      );
      expect(best?.channelId, 'match');
    });

    test('la casse ne décide de rien', () {
      final EpgProgram? best = MatchChannelFinder.bestMatch(
        <EpgProgram>[_prog('BARRACAS CENTRAL vs ARGENTINOS JUNIORS')],
        noms,
      );
      expect(best, isNotNull);
    });

    test('à défaut, une seule équipe vaut mieux qu\'un écran muet', () {
      final EpgProgram? best = MatchChannelFinder.bestMatch(
        <EpgProgram>[_prog('Foot : Barracas Central', channelId: 'partiel')],
        noms,
      );
      expect(best?.channelId, 'partiel');
    });

    test('aucun candidat : null, on n\'invente pas de chaîne', () {
      expect(MatchChannelFinder.bestMatch(<EpgProgram>[], noms), isNull);
      expect(
          MatchChannelFinder.bestMatch(
              <EpgProgram>[_prog('Journal')], <String>[]),
          isNull);
    });
  });
}
