// =========================================================
//  banc_essai_test.dart — un banc qui ment est pire qu'aucun banc
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) : « Fais l'excellence, et fais
//  un benchmark. »
//
//  CE QUE CES TESTS PROTÈGENT, DANS L'ORDRE D'IMPORTANCE :
//
//   1. QU'ON REFUSE DE NOTER UNE SESSION TROP COURTE. C'est le test le
//      plus important du fichier. Trois minutes sans crash ne prouvent
//      rien — la panne qu'on cherche met une demi-heure à se montrer.
//      Un « 100/100 » après trois minutes donnerait confiance sans
//      raison, et on republierait par-dessus un défaut réel.
//
//   2. QUE LA NOTE SOIT COMPARABLE D'UN BUILD À L'AUTRE. Les compteurs
//      sont ramenés à l'heure : sans ça, une session de 24 h paraîtrait
//      pire qu'une de 2 h juste parce qu'elle a duré plus longtemps, et
//      le banc récompenserait les tests courts.
//
//   3. QUE CHAQUE CHIFFRE VIENNE D'UN VRAI ÉVÉNEMENT du journal. Le
//      banc NOTE ce que la Boîte noire a vu ; il ne mesure rien de son
//      côté. Un compteur maison aurait fini par contredire le journal.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/observability/banc_essai.dart';

/// Une ligne de journal, comme la Boîte noire la stocke.
Map<String, Object?> ligne(String domaine, String evenement,
        {String lvl = 'warn'}) =>
    <String, Object?>{'lvl': lvl, 'domain': domaine, 'event': evenement};

List<Map<String, Object?>> lignes(String domaine, String evenement, int n,
    {String lvl = 'warn'}) =>
    List<Map<String, Object?>>.generate(
        n, (_) => ligne(domaine, evenement, lvl: lvl));

void main() {
  group('LA RÈGLE QUI REND LE BANC HONNÊTE — trop court = pas de note', () {
    test('3 minutes sans aucune panne ne reçoivent AUCUNE note', () {
      final BancVerdict v = noterBanc(mesurerBanc(
        const <Map<String, Object?>>[],
        duree: const Duration(minutes: 3),
      ));
      expect(v.note, isNull,
          reason: 'un 100/100 après 3 minutes donnerait confiance sans '
              'raison — c\'est pire que pas de banc du tout');
      expect(v.resume, contains('Trop court'));
      expect(v.bon, isFalse, reason: '« pas de note » n\'est pas « bon »');
    });

    test('59 minutes : toujours pas de note', () {
      final BancVerdict v = noterBanc(mesurerBanc(
        const <Map<String, Object?>>[],
        duree: const Duration(minutes: 59),
      ));
      expect(v.note, isNull);
    });

    test('1 heure pile : on note', () {
      final BancVerdict v = noterBanc(mesurerBanc(
        const <Map<String, Object?>>[],
        duree: const Duration(hours: 1),
      ));
      expect(v.note, 100);
    });

    test('« pas de note » n\'est PAS « zéro »', () {
      // La confusion serait grave : zéro veut dire « ce build est
      // mauvais », null veut dire « je ne sais pas encore ».
      final BancVerdict court = noterBanc(mesurerBanc(
        const <Map<String, Object?>>[],
        duree: const Duration(minutes: 5),
      ));
      final BancVerdict mauvais = noterBanc(mesurerBanc(
        lignes('crash', 'boum', 5, lvl: 'fatal'),
        duree: const Duration(hours: 6),
      ));
      expect(court.note, isNull);
      expect(mauvais.note, 0);
      expect(court.note, isNot(mauvais.note));
    });
  });

  group('chaque chiffre vient d\'un VRAI événement du journal', () {
    test('les six familles de pannes sont comptées séparément', () {
      final BancMesure m = mesurerBanc(<Map<String, Object?>>[
        ...lignes('app', 'mort', 1, lvl: 'fatal'),
        ...lignes('crash', 'zone', 2, lvl: 'err'),
        ...lignes('memoire', 'pressure.purge', 3),
        ...lignes('native', 'tv_player.startup_timeout', 4),
        ...lignes('native', 'tv_player.error', 5),
        ...lignes('native', 'tv_player.rebuffer_budget_exceeded', 6),
        ...lignes('ecran', 'verrou.refuse', 7),
        ...lignes('ecran', 'verrou.retabli', 8),
      ], duree: const Duration(hours: 2));

      expect(m.crashs, 1);
      expect(m.erreursNonRattrapees, 2);
      expect(m.purgesMemoire, 3);
      expect(m.demarragesRates, 4);
      expect(m.erreursLecture, 5);
      expect(m.gelsBudgetDepasse, 6);
      expect(m.verrouRefuse, 7);
      expect(m.verrouRetabli, 8);
      expect(m.incidents, 36);
    });

    test('les lignes SAINES ne comptent pas', () {
      // `verrou.pose` est une bonne nouvelle : la compter comme un
      // incident ferait chuter la note d'un build qui va bien.
      final BancMesure m = mesurerBanc(<Map<String, Object?>>[
        ...lignes('ecran', 'verrou.pose', 20, lvl: 'info'),
        ...lignes('sub', 'sync.ok', 50, lvl: 'info'),
        ...lignes('native', 'tv_player.opened', 30, lvl: 'info'),
      ], duree: const Duration(hours: 3));
      expect(m.incidents, 0);
      expect(noterBanc(m).note, 100);
    });

    test('une ligne abîmée ne fait pas tomber le comptage', () {
      // Un journal tronqué par un crash ne doit pas priver le
      // propriétaire de son verdict.
      final BancMesure m = mesurerBanc(<Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'domain': null, 'event': null, 'lvl': null},
        <String, Object?>{'domain': 42, 'event': <int>[1], 'lvl': true},
        ...lignes('memoire', 'pressure.purge', 2),
      ], duree: const Duration(hours: 2));
      expect(m.purgesMemoire, 2);
    });

    test('un journal vide sur une longue session = note parfaite', () {
      final BancVerdict v = noterBanc(mesurerBanc(
        const <Map<String, Object?>>[],
        duree: const Duration(hours: 24),
      ));
      expect(v.note, 100);
      expect(v.reproches, isEmpty);
      expect(v.bon, isTrue);
    });
  });

  group('la note est COMPARABLE d\'un build à l\'autre', () {
    test('même taux horaire, durées différentes → même note', () {
      // LE test qui empêche le banc de récompenser les essais courts.
      // 2 purges en 2 h et 24 purges en 24 h, c'est le même rythme :
      // la note doit être identique.
      final BancVerdict courte = noterBanc(mesurerBanc(
        lignes('memoire', 'pressure.purge', 2),
        duree: const Duration(hours: 2),
      ));
      final BancVerdict longue = noterBanc(mesurerBanc(
        lignes('memoire', 'pressure.purge', 24),
        duree: const Duration(hours: 24),
      ));
      expect(courte.note, longue.note,
          reason: 'sinon un build serait « meilleur » simplement parce '
              'qu\'on l\'a testé moins longtemps');
    });

    test('deux fois plus de pannes au même rythme horaire = même note', () {
      final BancVerdict a = noterBanc(mesurerBanc(
        lignes('native', 'tv_player.error', 3),
        duree: const Duration(hours: 3),
      ));
      final BancVerdict b = noterBanc(mesurerBanc(
        lignes('native', 'tv_player.error', 6),
        duree: const Duration(hours: 6),
      ));
      expect(a.note, b.note);
    });

    test('à durée égale, plus de pannes = note plus basse', () {
      final BancVerdict peu = noterBanc(mesurerBanc(
        lignes('native', 'tv_player.error', 1),
        duree: const Duration(hours: 4),
      ));
      final BancVerdict beaucoup = noterBanc(mesurerBanc(
        lignes('native', 'tv_player.error', 20),
        duree: const Duration(hours: 4),
      ));
      expect(beaucoup.note, lessThan(peu.note!));
    });
  });

  group('les deux pannes ÉLIMINATOIRES', () {
    test('UN SEUL crash plombe la note, même sur 24 h impeccables', () {
      // Un crash vide le salon. Le diluer dans une longue session
      // reviendrait à dire « ce n'est pas grave, c'est rare » — non :
      // le client, lui, s'est pris l'écran noir en pleine figure.
      final BancVerdict v = noterBanc(mesurerBanc(
        lignes('app', 'mort', 1, lvl: 'fatal'),
        duree: const Duration(hours: 24),
      ));
      expect(v.note, 60);
      expect(v.bon, isFalse);
      expect(v.reproches.first, contains('crash'));
    });

    test('UN SEUL refus du verrou d\'écran plombe la note', () {
      // Le verrou refusé GARANTIT un écran noir plus tard. Le ramener
      // à l'heure le rendrait invisible sur une longue session —
      // c'est précisément la panne du 18/09.
      final BancVerdict v = noterBanc(mesurerBanc(
        lignes('ecran', 'verrou.refuse', 1),
        duree: const Duration(hours: 24),
      ));
      expect(v.note, 75);
      expect(v.reproches.first, contains('écran noir'));
    });

    test('la note ne descend jamais sous zéro', () {
      final BancVerdict v = noterBanc(mesurerBanc(
        lignes('app', 'mort', 50, lvl: 'fatal'),
        duree: const Duration(hours: 2),
      ));
      expect(v.note, 0);
    });
  });

  group('le verdict se lit à voix haute', () {
    test('les durées sont dites comme le propriétaire les dit', () {
      final BancVerdict v = noterBanc(mesurerBanc(
        const <Map<String, Object?>>[],
        duree: const Duration(hours: 6, minutes: 40),
      ));
      expect(v.resume, contains('6 h 40'),
          reason: 'jamais « 24000 s » : ce chiffre se lit au téléphone');
    });

    test('une session en heures pleines ne dit pas « 6 h 0 »', () {
      final BancVerdict v = noterBanc(mesurerBanc(
        const <Map<String, Object?>>[],
        duree: const Duration(hours: 6),
      ));
      expect(v.resume, contains('6 h'));
      expect(v.resume, isNot(contains('6 h 0')));
    });

    test('chaque reproche porte son CHIFFRE', () {
      // Un reproche sans chiffre ne se compare pas d'un build à
      // l'autre, et c'est tout l'objet du banc.
      final BancVerdict v = noterBanc(mesurerBanc(<Map<String, Object?>>[
        ...lignes('native', 'tv_player.startup_timeout', 3),
        ...lignes('memoire', 'pressure.purge', 6),
      ], duree: const Duration(hours: 3)));
      expect(v.reproches.length, 2);
      for (final String r in v.reproches) {
        expect(RegExp(r'\d').hasMatch(r), isTrue, reason: r);
      }
    });
  });

  group('CE QUE LE BANC NE PROUVE PAS — dit à chaque fois', () {
    test('même à 100/100, les limites sont écrites', () {
      // Une note sans ses limites ment par omission. C'est le défaut
      // qui revient le plus souvent dans ce dépôt, et il ne doit pas
      // renaître dans l'outil censé le débusquer.
      final BancVerdict v = noterBanc(mesurerBanc(
        const <Map<String, Object?>>[],
        duree: const Duration(hours: 48),
      ));
      expect(v.note, 100);
      expect(v.nonMesure, isNotEmpty);
      final String limites = v.nonMesure.join(' ').toLowerCase();
      expect(limites, contains('fournisseur'),
          reason: 'une panne du fournisseur compte ici comme une erreur '
              'de lecture — il faut le dire avant qu\'on accuse l\'app');
      expect(v.nonMesure.join(' '), contains('box'),
          reason: 'une seule box ne représente pas le parc');
    });

    test('les limites sont là AUSSI quand la session est trop courte', () {
      final BancVerdict v = noterBanc(mesurerBanc(
        const <Map<String, Object?>>[],
        duree: const Duration(minutes: 10),
      ));
      expect(v.nonMesure, isNotEmpty);
    });
  });

  group('le cas réel du 18/09, rejoué', () {
    test('avant : la box redémarrait toutes les 25 minutes', () {
      // Trop court pour être noté — et c'est exactement le constat
      // qu'il fallait : on ne pouvait rien conclure d'une box qui ne
      // tenait pas debout.
      final BancVerdict v = noterBanc(mesurerBanc(<Map<String, Object?>>[
        ...lignes('memoire', 'pressure.purge', 14),
        ...lignes('app', 'mort', 1, lvl: 'fatal'),
      ], duree: const Duration(minutes: 25)));
      expect(v.note, isNull);
      expect(v.resume, contains('Trop court'));
    });

    test('après : 6 h 40 tenues, pression mémoire rare', () {
      final BancVerdict v = noterBanc(mesurerBanc(<Map<String, Object?>>[
        ...lignes('memoire', 'pressure.purge', 2),
        ...lignes('ecran', 'verrou.retabli', 1),
      ], duree: const Duration(hours: 6, minutes: 40)));
      expect(v.note, isNotNull);
      expect(v.note, greaterThanOrEqualTo(80),
          reason: 'c\'est le build que le propriétaire a validé sur une '
              'vraie box — le banc doit être d\'accord avec lui');
      expect(v.bon, isTrue);
    });
  });
}
