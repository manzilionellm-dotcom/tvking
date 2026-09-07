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
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/epg/domain/epg_program.dart';
import 'package:tv_king/features/sports/data/match_channel_finder.dart';
import 'package:tv_king/features/sports/data/sport_country_prefs.dart';
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

/// Chaîne de test. Le pays n'est PAS un champ : il est déduit du nom et
/// de la catégorie par le classifieur de l'app — on passe donc la
/// catégorie qui le déclenche (« FR », « Sweden »), exactement comme le
/// ferait une vraie playlist M3U.
///
/// L'`id` doit être UNIQUE par chaîne : le pays est mis en cache par id
/// dans Channel, et réutiliser un id rendrait le pays d'une autre.
Channel _chan(String id, String category) => Channel(
      id: id,
      name: id,
      category: category,
      streamUrl: 'http://x/$id',
      isLive: true,
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

  group('Choisir la bonne chaîne', () {
    final List<String> noms = <String>['Barracas Central', 'Argentinos Juniors'];

    ({EpgProgram program, Channel channel}) pair(
      String titre,
      String chId,
      String categorie,
    ) =>
        (
          program: _prog(titre, channelId: chId),
          channel: _chan(chId, categorie),
        );

    test('les DEUX équipes battent une seule, même arrivée en second', () {
      final Channel? best = MatchChannelFinder.pickBest(
        <({EpgProgram program, Channel channel})>[
          pair('Magazine Barracas Central', 'magazine', 'FR'),
          pair('Barracas Central / Argentinos Juniors', 'match', 'FR'),
        ],
        noms,
        '',
      );
      expect(best?.id, 'match');
    });

    test('les DEUX équipes gagnent aussi quand elles arrivent en premier', () {
      final Channel? best = MatchChannelFinder.pickBest(
        <({EpgProgram program, Channel channel})>[
          pair('Barracas Central - Argentinos Juniors', 'match', 'FR'),
          pair('Résumé Argentinos Juniors', 'resume', 'FR'),
        ],
        noms,
        '',
      );
      expect(best?.id, 'match');
    });

    test('la casse ne décide de rien', () {
      final Channel? best = MatchChannelFinder.pickBest(
        <({EpgProgram program, Channel channel})>[
          pair('BARRACAS CENTRAL vs ARGENTINOS JUNIORS', 'c', 'FR'),
        ],
        noms,
        '',
      );
      expect(best, isNotNull);
    });

    test('à défaut, une seule équipe vaut mieux qu\'un écran muet', () {
      final Channel? best = MatchChannelFinder.pickBest(
        <({EpgProgram program, Channel channel})>[
          pair('Foot : Barracas Central', 'partiel', 'FR'),
        ],
        noms,
        '',
      );
      expect(best?.id, 'partiel');
    });

    test('aucun candidat : null, on n\'invente pas de chaîne', () {
      expect(
          MatchChannelFinder.pickBest(
              <({EpgProgram program, Channel channel})>[], noms, ''),
          isNull);
      expect(
          MatchChannelFinder.pickBest(
              <({EpgProgram program, Channel channel})>[
                pair('Journal', 'j', 'FR')
              ],
              <String>[],
              ''),
          isNull);
    });

    // ---------------------------------------------------------
    //  LE PAYS DU CLIENT — « genre les apps haut niveau »
    // ---------------------------------------------------------
    test('à match égal, la chaîne DU PAYS choisi gagne', () {
      final Channel? best = MatchChannelFinder.pickBest(
        <({EpgProgram program, Channel channel})>[
          pair('Barracas Central - Argentinos Juniors', 'arabe', 'Sweden'),
          pair('Barracas Central - Argentinos Juniors', 'francais', 'FR'),
        ],
        noms,
        'FR',
      );
      expect(best?.id, 'francais',
          reason: 'trois chaînes diffusent le même match : on donne la sienne');
    });

    test('le MATCH passe avant le pays', () {
      // Le cas qui compte vraiment. Une émission de son pays qui n'est
      // PAS le match ne doit jamais battre le vrai match diffusé
      // ailleurs : mieux vaut le bon match en suédois qu'un magazine en
      // français pendant que le match se joue.
      final Channel? best = MatchChannelFinder.pickBest(
        <({EpgProgram program, Channel channel})>[
          pair('Magazine Barracas Central', 'magazine-fr', 'FR'),
          pair('Barracas Central - Argentinos Juniors', 'match-se', 'Sweden'),
        ],
        noms,
        'FR',
      );
      expect(best?.id, 'match-se');
    });

    test('sans pays choisi, on ne préfère rien : l\'ordre du guide décide', () {
      final Channel? best = MatchChannelFinder.pickBest(
        <({EpgProgram program, Channel channel})>[
          pair('Barracas Central - Argentinos Juniors', 'premier', 'Sweden'),
          pair('Barracas Central - Argentinos Juniors', 'second', 'FR'),
        ],
        noms,
        '',
      );
      expect(best?.id, 'premier');
    });

    test('pays choisi absent des candidats : on rend quand même le match', () {
      final Channel? best = MatchChannelFinder.pickBest(
        <({EpgProgram program, Channel channel})>[
          pair('Barracas Central - Argentinos Juniors', 'match', 'Sweden'),
        ],
        noms,
        'FR',
      );
      expect(best?.id, 'match',
          reason: 'un réglage de confort ne doit jamais faire disparaître '
              'le match');
    });
  });

  group('Les pays proposés au client', () {
    test('déduits de SA playlist, classés par nombre de chaînes', () {
      final List<Channel> chans = <Channel>[
        _chan('a', 'FR'),
        _chan('b', 'FR'),
        _chan('c', 'FR'),
        _chan('d', 'Sweden'),
        _chan('e', 'Sweden'),
        _chan('f', 'sans-pays-connu'),
      ];
      final List<SportCountryOption> opts =
          SportCountryPrefs.optionsFrom(chans);
      expect(opts.first.info.code, 'FR');
      expect(opts.first.channelCount, 3);
      expect(opts[1].info.code, 'SE');
      expect(opts[1].channelCount, 2);
      // Une chaîne dont on ne reconnaît pas le pays n'invente pas
      // d'entrée « inconnu » dans le menu.
      expect(opts.length, 2);
    });

    test('playlist vide : aucune option, et surtout pas une liste du monde',
        () {
      expect(SportCountryPrefs.optionsFrom(<Channel>[]), isEmpty);
    });
  });
}
