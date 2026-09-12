// =========================================================
//  sport_search_test.dart — « montre-moi le match de Chelsea »
// =========================================================
//  Ces tests existent à cause d'une phrase du propriétaire (12/09/2026) :
//
//    « je voulais regarder le match de Chelsea, j'ai écrit Chelsea, ça
//      devait vraiment me montrer les chaînes en direct qui passent le
//      match — mais ça ne marche plus. »
//
//  Ce qu'on verrouille ici, c'est l'ORDRE. Trouver les matchs ne sert à
//  rien si le match qui joue MAINTENANT arrive en quatrième position :
//  sur une télévision, ce qui n'est pas dans le premier écran n'existe
//  pas. L'appel réseau, lui, n'a rien à prouver — c'est le classement qui
//  porte la promesse faite au client, et il est pur, donc testé ici sans
//  base, sans réseau, sans horloge réelle.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/sports/data/sport_search.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

/// Un match fabriqué pour le test. `status` décide du direct : « 1H »
/// (première mi-temps) joue, « NS » (not started) non, « FT » est fini.
SportEvent _ev(
  String id, {
  String home = 'Chelsea',
  String away = 'Arsenal',
  DateTime? debut,
  String status = 'NS',
}) =>
    SportEvent(
      id: id,
      home: home,
      away: away,
      status: status,
      timestamp: debut == null ? '' : debut.toUtc().toIso8601String(),
    );

({SportEvent event, String teamName}) _r(SportEvent e,
        [String equipe = 'Chelsea']) =>
    (event: e, teamName: equipe);

void main() {
  // Heure FIXE : un test qui dépend de l'heure réelle passe le matin et
  // échoue la nuit, puis finit désactivé.
  final DateTime maintenant = DateTime(2026, 9, 12, 18, 0);

  group('classer — ce qui joue MAINTENANT passe devant', () {
    test('un match en direct bat un match plus proche dans le temps', () {
      // Le piège : le match à 18 h 30 est plus « proche » de maintenant
      // que celui commencé à 17 h. Mais c'est celui qui JOUE que le
      // client veut voir — c'est sa demande littérale.
      final SportEvent enCours = _ev('live',
          debut: DateTime(2026, 9, 12, 17, 0), status: '2H');
      final SportEvent bientot =
          _ev('soon', debut: DateTime(2026, 9, 12, 18, 30));
      final List<({SportEvent event, String teamName})> out =
          SportSearch.classer(
        <({SportEvent event, String teamName})>[_r(bientot), _r(enCours)],
        maintenant,
      );
      expect(out.map((({SportEvent event, String teamName}) e) => e.event.id),
          <String>['live', 'soon']);
    });

    test('à égalité de direct, le plus proche de maintenant gagne', () {
      final SportEvent ceSoir =
          _ev('cesoir', debut: DateTime(2026, 9, 12, 21, 0));
      final SportEvent dansSixJours =
          _ev('loin', debut: DateTime(2026, 9, 18, 21, 0));
      final List<({SportEvent event, String teamName})> out =
          SportSearch.classer(
        <({SportEvent event, String teamName})>[_r(dansSixJours), _r(ceSoir)],
        maintenant,
      );
      expect(out.first.event.id, 'cesoir');
    });

    test('un match récent reste visible, mais derrière celui à venir', () {
      // Deux heures après le coup d'envoi : le client peut encore vouloir
      // le retrouver (rediffusion, fin de match), mais le match de ce soir
      // compte davantage.
      final SportEvent recent =
          _ev('recent', debut: DateTime(2026, 9, 12, 16, 0), status: 'FT');
      final SportEvent ceSoir =
          _ev('cesoir', debut: DateTime(2026, 9, 12, 19, 0));
      final List<({SportEvent event, String teamName})> out =
          SportSearch.classer(
        <({SportEvent event, String teamName})>[_r(recent), _r(ceSoir)],
        maintenant,
      );
      expect(out.map((({SportEvent event, String teamName}) e) => e.event.id),
          <String>['cesoir', 'recent']);
    });
  });

  group('classer — la fenêtre de temps', () {
    test('un match d\'il y a une semaine est écarté', () {
      final SportEvent vieux =
          _ev('vieux', debut: DateTime(2026, 9, 5, 21, 0), status: 'FT');
      expect(
        SportSearch.classer(
            <({SportEvent event, String teamName})>[_r(vieux)], maintenant),
        isEmpty,
      );
    });

    test('un match dans un mois est écarté', () {
      final SportEvent lointain =
          _ev('lointain', debut: DateTime(2026, 10, 12, 21, 0));
      expect(
        SportSearch.classer(
            <({SportEvent event, String teamName})>[_r(lointain)], maintenant),
        isEmpty,
      );
    });

    test('un match SANS heure connue est écarté… sauf s\'il joue', () {
      // Sans date on ne peut rien affirmer — sauf si la source, elle,
      // déclare que ça joue. Elle en sait alors plus que notre fenêtre.
      final SportEvent sansHeure = _ev('flou');
      final SportEvent sansHeureMaisEnDirect = _ev('flouLive', status: '1H');
      final List<({SportEvent event, String teamName})> out =
          SportSearch.classer(
        <({SportEvent event, String teamName})>[
          _r(sansHeure),
          _r(sansHeureMaisEnDirect),
        ],
        maintenant,
      );
      expect(out.map((({SportEvent event, String teamName}) e) => e.event.id),
          <String>['flouLive']);
    });

    test('le bord de la fenêtre ne coupe pas un match de ce soir', () {
      // Trois heures en arrière : un match commencé à 15 h 30 est encore
      // dedans à 18 h, celui de 14 h non.
      final SportEvent dedans =
          _ev('dedans', debut: DateTime(2026, 9, 12, 15, 30), status: 'FT');
      final SportEvent dehors =
          _ev('dehors', debut: DateTime(2026, 9, 12, 14, 0), status: 'FT');
      final List<({SportEvent event, String teamName})> out =
          SportSearch.classer(
        <({SportEvent event, String teamName})>[_r(dedans), _r(dehors)],
        maintenant,
      );
      expect(out.map((({SportEvent event, String teamName}) e) => e.event.id),
          <String>['dedans']);
    });
  });

  group('classer — un match ne s\'affiche qu\'UNE fois', () {
    test('les deux équipes ramènent le même match : une seule affiche', () {
      // « CHE » peut sortir Chelsea ET l'adversaire. Les deux calendriers
      // contiennent la MÊME rencontre. Sans dédoublonnage, le client voit
      // deux affiches identiques côte à côte et croit à deux matchs.
      final SportEvent m = _ev('42', debut: DateTime(2026, 9, 12, 21, 0));
      final List<({SportEvent event, String teamName})> out =
          SportSearch.classer(
        <({SportEvent event, String teamName})>[
          _r(m, 'Chelsea'),
          _r(m, 'Arsenal'),
        ],
        maintenant,
      );
      expect(out.length, 1);
      // Le PREMIER arrivé gagne : c'est l'équipe la mieux classée par la
      // recherche, donc la plus proche de ce que le client a tapé.
      expect(out.first.teamName, 'Chelsea');
    });

    test('un match sans identifiant est ignoré (rien à dédoublonner)', () {
      final SportEvent anonyme =
          _ev('', debut: DateTime(2026, 9, 12, 21, 0));
      expect(
        SportSearch.classer(
            <({SportEvent event, String teamName})>[_r(anonyme)], maintenant),
        isEmpty,
      );
    });
  });

  group('classer — bornes', () {
    test('la liste est plafonnée', () {
      final List<({SportEvent event, String teamName})> beaucoup =
          <({SportEvent event, String teamName})>[
        for (int i = 0; i < 40; i++)
          _r(_ev('m$i',
              debut: DateTime(2026, 9, 12, 19, 0).add(Duration(minutes: i)))),
      ];
      expect(SportSearch.classer(beaucoup, maintenant).length,
          SportSearch.kMaxMatchs);
      expect(SportSearch.classer(beaucoup, maintenant, maxMatchs: 3).length, 3);
    });

    test('aucune entrée → liste vide, pas d\'exception', () {
      expect(
        SportSearch.classer(
            const <({SportEvent event, String teamName})>[], maintenant),
        isEmpty,
      );
    });
  });

  group('rechercher — le garde-fou des requêtes trop courtes', () {
    test('moins de trois lettres ne déclenche AUCUN réseau', () async {
      // Sur un clavier de télévision, chaque lettre relance la recherche.
      // « C » ramènerait le monde entier, pour rien. Ce test passe sans
      // réseau : s'il en partait un, il échouerait ou traînerait.
      for (final String q in <String>['', ' ', 'C', 'CH', '  CH  ']) {
        expect(await SportSearch.rechercher(q), isEmpty, reason: 'q="$q"');
      }
    });
  });
}
