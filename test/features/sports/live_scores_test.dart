// =========================================================
//  live_scores_test.dart — Les scores en direct
// =========================================================
//  Ce fichier verrouille des pièges CONSTATÉS sur les vraies données de
//  TheSportsDB le 23/08/2026, le jour où la clé payante est arrivée.
//
//  Le plus coûteux : avant, « en direct » était DEVINÉ à l'horloge — un
//  match dont l'heure de coup d'envoi était passée de moins de 2 h était
//  déclaré en cours. Un report, une prolongation ou un fuseau mal lu, et
//  le badge mentait au client. La source dit maintenant l'état réel, et
//  ces tests s'assurent qu'on le lit correctement.
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/sports/data/live_scores_service.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

SportEvent ev({
  String id = '1',
  String status = '',
  String progress = '',
  String home = 'Manchester City',
  String away = 'Bournemouth',
  String? homeScore,
  String? awayScore,
}) =>
    SportEvent(
      id: id,
      home: home,
      away: away,
      homeScore: homeScore,
      awayScore: awayScore,
      status: status,
      progress: progress,
      league: 'English Premier League',
      sport: 'Soccer',
      homeBadge: 'https://exemple/h.png',
      awayBadge: 'https://exemple/a.png',
      tier: 2,
    );

void main() {
  group('État EN DIRECT', () {
    test('un match terminé ou pas commencé n\'est PAS en direct', () {
      // Ce sont les états qu'on voit le plus souvent : sans eux, TOUTE la
      // liste des affiches à venir se serait affichée « en direct ».
      for (final String s in <String>['FT', 'ft', 'NS', 'AET', 'PEN',
        'Postp', 'Canc', '']) {
        expect(ev(status: s).isLive, isFalse, reason: 'statut « $s »');
      }
    });

    test('un match en cours EST en direct, quel que soit le sport', () {
      // 1H/2H au football, Q1..Q4 au basket, P1 au hockey : impossible de
      // faire une liste blanche. On procède par exclusion, et ce test
      // vérifie qu'un code inconnu est bien traité comme « ça joue ».
      for (final String s in <String>['1H', '2H', 'HT', 'Q3', 'P2', 'In Play']) {
        expect(ev(status: s).isLive, isTrue, reason: 'statut « $s »');
      }
    });

    test('la minute de jeu est affichée, la mi-temps est nommée', () {
      expect(ev(status: '1H', progress: '21').liveLabel, "21'");
      // TheSportsDB envoie aussi « 45+2 » : c'est une CHAÎNE, pas un
      // entier. Convertir en int aurait planté ou perdu l'information.
      expect(ev(status: '1H', progress: '45+2').liveLabel, "45+2'");
      expect(ev(status: 'HT', progress: '').liveLabel, 'Mi-temps');
      // Sans minute connue, on retombe sur le statut brut plutôt que sur
      // une case vide.
      expect(ev(status: 'Q3', progress: '').liveLabel, 'Q3');
    });
  });

  group('Rencontres sans deux camps', () {
    test('une course garde son nom au lieu d\'afficher « vs »', () {
      // Constaté le 23/08 : les épreuves de sport auto arrivent sans
      // domicile ni extérieur. L'écran affichait « null vs null ».
      const SportEvent course = SportEvent(
        id: '9',
        name: 'Daytona 500',
        league: 'NASCAR Cup Series',
        sport: 'Motorsport',
      );
      expect(course.isDuel, isFalse);
      expect(course.title, 'Daytona 500');
      expect(course.title.contains('vs'), isFalse);
    });

    test('un duel garde bien ses deux équipes', () {
      expect(ev().isDuel, isTrue);
      expect(ev().title, 'Manchester City vs Bournemouth');
    });
  });

  group('Lecture du JSON', () {
    test('les nouveaux champs sont lus', () {
      final SportEvent e = SportEvent.fromJson(<String, dynamic>{
        'id': '2494006',
        'home': 'Manchester City',
        'away': 'Bournemouth',
        'homeScore': 0,
        'awayScore': 0,
        'homeBadge': 'https://exemple/h.png',
        'status': '1H',
        'progress': 21,
        'tier': 2,
        'women': true,
      });
      expect(e.homeBadge, 'https://exemple/h.png');
      expect(e.status, '1H');
      expect(e.progress, '21'); // arrivé en NOMBRE, lu en chaîne
      expect(e.tier, 2);
      expect(e.women, isTrue);
    });

    test('un champ absent ou malformé ne fait JAMAIS planter', () {
      // Une exception ici viderait TOUT l'écran Sport à cause d'un seul
      // match mal formé. Le pire des comportements possibles.
      final SportEvent e = SportEvent.fromJson(<String, dynamic>{
        'id': '1',
        'tier': 'pas un nombre',
      });
      expect(e.tier, 0);
      expect(e.women, isFalse);
      expect(e.homeBadge, isEmpty);
      expect(e.progress, isEmpty);
    });

    test('ce qui est écrit se relit à l\'identique', () {
      // FollowedMatchesService mémorise les matchs suivis en JSON : si
      // l'aller-retour perdait les écussons, un match suivi les perdrait
      // au premier redémarrage.
      final SportEvent a = ev(status: '2H', progress: '67', homeScore: '2',
          awayScore: '1');
      final SportEvent b = SportEvent.fromJson(a.toJson());
      expect(b.homeBadge, a.homeBadge);
      expect(b.awayBadge, a.awayBadge);
      expect(b.tier, a.tier);
      expect(b.progress, a.progress);
      expect(b.status, a.status);
    });
  });

  group('Injection du score en direct', () {
    test('seul ce qui bouge est remplacé', () {
      // L'affiche garde son heure, ses écussons et son niveau : sinon un
      // match suivi perdrait ses informations à chaque rafraîchissement.
      final SportEvent affiche = ev(id: '42', status: 'NS');
      LiveScoresService.instance.debugSeed(<SportEvent>[
        ev(id: '42', status: '2H', progress: '67',
            homeScore: '2', awayScore: '1'),
      ]);
      final SportEvent vif = LiveScoresService.instance.enrich(affiche);
      expect(vif.homeScore, '2');
      expect(vif.awayScore, '1');
      expect(vif.progress, '67');
      expect(vif.isLive, isTrue);
      // INCHANGÉS
      expect(vif.homeBadge, affiche.homeBadge);
      expect(vif.tier, affiche.tier);
      expect(vif.league, affiche.league);
    });

    test('un match absent du direct revient INTACT', () {
      LiveScoresService.instance.debugSeed(<SportEvent>[ev(id: '42')]);
      final SportEvent autre = ev(id: '99', status: 'NS');
      expect(identical(LiveScoresService.instance.enrich(autre), autre), isTrue);
      expect(LiveScoresService.instance.forId('99'), isNull);
    });

    test('un identifiant vide ne rapproche rien', () {
      // (voir groupe suivant pour la détection de but)
      // Sans ce garde-fou, tous les matchs sans identifiant se
      // seraient reconnus entre eux.
      LiveScoresService.instance.debugSeed(<SportEvent>[ev(id: '')]);
      expect(LiveScoresService.instance.forId(''), isNull);
    });
  });

  group('Détection du but (le « wouaaah »)', () {
    final LiveScoresService s = LiveScoresService.instance;

    setUp(s.debugResetGoals);

    test('LE PIÈGE : le premier tour n\'annonce RIEN', () {
      // Sans état antérieur, TOUS les matchs en cours semblent venir de
      // marquer. On ouvrirait l'app et on recevrait vingt cris d'un
      // coup. Le premier passage doit seulement APPRENDRE.
      final List<String> r = s.debugGoals(<SportEvent>[
        ev(id: 'a', homeScore: '2', awayScore: '1'),
        ev(id: 'b', homeScore: '0', awayScore: '3'),
      ]);
      expect(r, isEmpty);
      expect(s.debugBaselineDone, isTrue);
    });

    test('un score qui MONTE est un but', () {
      s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '0', awayScore: '0')]);
      final List<String> r = s.debugGoals(
          <SportEvent>[ev(id: 'a', homeScore: '1', awayScore: '0')]);
      expect(r, <String>['a']);
    });

    test('un score INCHANGÉ ne déclenche rien', () {
      s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '1', awayScore: '0')]);
      expect(
        s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '1', awayScore: '0')]),
        isEmpty,
      );
    });

    test('un score qui BAISSE ne déclenche rien, et est mémorisé', () {
      // But refusé après vidéo, correction d'arbitrage, ou simplement
      // une donnée amont qui hoquette. On se tait — puis on repart de
      // la NOUVELLE valeur, sinon le prochain retour à 1-0 serait
      // annoncé comme un but qui n'a jamais eu lieu.
      s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '1', awayScore: '0')]);
      expect(
        s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '0', awayScore: '0')]),
        isEmpty,
      );
      expect(
        s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '1', awayScore: '0')]),
        <String>['a'],
        reason: 'le retour à 1-0 est un vrai but par rapport à 0-0',
      );
    });

    test('un match VU POUR LA PREMIÈRE FOIS en cours de route est muet', () {
      // Un match qui commence pendant qu'on regarde ailleurs arrive
      // déjà à 1-0. Ce n'est pas un but qu'on vient de voir : c'est un
      // match qu'on découvre.
      s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '0', awayScore: '0')]);
      final List<String> r = s.debugGoals(<SportEvent>[
        ev(id: 'a', homeScore: '0', awayScore: '0'),
        ev(id: 'nouveau', homeScore: '1', awayScore: '0'),
      ]);
      expect(r, isEmpty);
    });

    test('un score ILLISIBLE ne déclenche rien et n\'efface pas la mémoire',
        () {
      s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '1', awayScore: '0')]);
      // Score absent : l'amont hoquette. On ne devine pas, on ne crie
      // pas — et surtout on ne prend pas ce trou pour un 0-0.
      expect(s.debugGoals(<SportEvent>[ev(id: 'a')]), isEmpty);
      expect(
        s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '1', awayScore: '0')]),
        isEmpty,
        reason: 'le match réapparaît au score connu : ce n\'est pas un but',
      );
    });

    test('deux buts simultanés sont TOUS DEUX détectés', () {
      // La détection les voit tous les deux ; c'est l'appelant qui ne
      // joue qu'un seul son, pour que deux « wouaaah » ne se
      // chevauchent pas. La distinction compte : on ne PERD pas
      // l'information, on choisit seulement de ne pas la crier deux
      // fois.
      s.debugGoals(<SportEvent>[
        ev(id: 'a', homeScore: '0', awayScore: '0'),
        ev(id: 'b', homeScore: '0', awayScore: '0'),
      ]);
      final List<String> r = s.debugGoals(<SportEvent>[
        ev(id: 'a', homeScore: '1', awayScore: '0'),
        ev(id: 'b', homeScore: '0', awayScore: '1'),
      ]);
      expect(r, <String>['a', 'b']);
    });

    test('le but de l\'ÉQUIPE EXTÉRIEURE compte aussi', () {
      // On compare le TOTAL des deux scores : un but est un but, peu
      // importe qui l'a marqué.
      s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '1', awayScore: '0')]);
      expect(
        s.debugGoals(<SportEvent>[ev(id: 'a', homeScore: '1', awayScore: '1')]),
        <String>['a'],
      );
    });
  });
}
