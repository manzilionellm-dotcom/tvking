// =========================================================
//  line_expiry_test.dart — « on ne coupe pas un client qui a payé »
// =========================================================
//  Ces tests existent à cause d'une photo datée du 12/09/2026 : on était
//  le 12, et l'app annonçait « Your subscription expired on 13/09/2026 ».
//  Une date PAS ENCORE ARRIVÉE. Et ce n'était pas qu'un mot mal choisi :
//  le même verdict arrête définitivement les reconnexions du relais.
//
//  Le test qui existait alors (block_reason_test.dart) ne pouvait pas
//  l'attraper : il ne travaillait qu'avec des écarts d'un jour entier,
//  là où le défaut se jouait sur des heures et sur un jour d'affichage.
//  Un test trop grossier laisse passer exactement le bug qu'il prétend
//  couvrir — on descend donc ici à l'heure et à la seconde.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/line_expiry.dart';

void main() {
  // Une date de référence FIXE : un test qui dépend de l'heure réelle
  // passe le matin et échoue la nuit, puis finit désactivé.
  final DateTime le12aMidi = DateTime(2026, 9, 12, 12, 0);

  group("dernierJourCouvert — le jour qu'on annonce au client", () {
    test('une fin à minuit couvre la VEILLE (le cas de la photo)', () {
      // Le panel pose « 13/09 00:00 » : la ligne est valable jusqu'à la
      // dernière seconde du 12. Annoncer « 13/09 » nommait un jour que le
      // client n'a jamais eu.
      expect(
        formatJour(dernierJourCouvert(DateTime(2026, 9, 13))),
        '12/09/2026',
      );
    });

    test('une fin en pleine journée reste sur SON jour', () {
      // Ici le 13 est bien le dernier jour couvert : reculer d'une seconde
      // ne doit pas voler un jour au client.
      expect(
        formatJour(dernierJourCouvert(DateTime(2026, 9, 13, 14, 30))),
        '13/09/2026',
      );
    });

    test('le format porte les zéros devant (lisible au téléphone)', () {
      // Fin le 6 janvier à MINUIT → dernier jour couvert : le 5.
      // (Ce test a d'abord été écrit avec « 6 janvier à 9 h » en attendant
      //  « 05/01 » : c'était le test qui se trompait, pas le code — une fin
      //  en pleine journée couvre bien SON propre jour. Gardé en mémoire
      //  ici, parce que c'est exactement la confusion qui a produit le bug
      //  d'origine, en sens inverse.)
      expect(
        formatJour(dernierJourCouvert(DateTime(2026, 1, 6))),
        '05/01/2026',
      );
    });
  });

  group('jugerLigne — la ligne est-elle morte ?', () {
    test('LE CAS DE LA PHOTO : fin demain, on ne coupe pas', () {
      expect(
        jugerLigne(
          statut: 'Active',
          finDeLigne: DateTime(2026, 9, 13),
          horlogeAppareil: le12aMidi,
        ),
        VerdictLigne.vivante,
      );
    });

    test('date franchement passée → morte', () {
      expect(
        jugerLigne(
          statut: 'Active',
          finDeLigne: DateTime(2026, 9, 1),
          horlogeAppareil: le12aMidi,
        ),
        VerdictLigne.morte,
      );
    });

    test('pas de date et pas de statut de fin → vivante (on ne devine pas)',
        () {
      expect(
        jugerLigne(
          statut: null,
          finDeLigne: null,
          horlogeAppareil: le12aMidi,
        ),
        VerdictLigne.vivante,
      );
    });

    test('statut « Expired » sans date → morte (rien ne le contredit)', () {
      expect(
        jugerLigne(
          statut: 'Expired',
          finDeLigne: null,
          horlogeAppareil: le12aMidi,
        ),
        VerdictLigne.morte,
      );
    });

    test('statut « Expired » mais date encore devant → CONTRADICTOIRE', () {
      // Le panel se contredit lui-même. On ne coupe pas la télé d'un client
      // sur la foi d'une information que le panel dément dans la ligne
      // d'à côté.
      expect(
        jugerLigne(
          statut: 'Expired',
          finDeLigne: DateTime(2026, 10, 1),
          horlogeAppareil: le12aMidi,
        ),
        VerdictLigne.contradictoire,
      );
    });

    test("« Not Expired » ne se lit pas à l'envers", () {
      // Le piège du `contains` : un panel exotique répond « Not Expired »,
      // et l'ancien code y lisait « expired ».
      expect(
        jugerLigne(
          statut: 'Not Expired',
          finDeLigne: null,
          horlogeAppareil: le12aMidi,
        ),
        VerdictLigne.vivante,
      );
    });

    group('la marge protège des horloges fausses', () {
      test('deux heures après la fin : encore vivante', () {
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 12, 10, 0),
            horlogeAppareil: le12aMidi,
          ),
          VerdictLigne.vivante,
        );
      });

      test('au-delà de la marge : morte', () {
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 11, 12, 0),
            horlogeAppareil: le12aMidi,
          ),
          VerdictLigne.morte,
        );
      });

      test('juste AVANT la limite exacte de la marge : vivante', () {
        // Fin + 12 h = 13/09 00:00. À 23:59 le 12, on est encore dedans.
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 12, 12, 0),
            horlogeAppareil: DateTime(2026, 9, 12, 23, 59),
            marge: const Duration(hours: 12),
          ),
          VerdictLigne.vivante,
        );
      });
    });

    group("l'horloge du panel fait autorité", () {
      test(
          'une box qui AVANCE de trois jours ne tue plus une ligne valide',
          () {
        // Le scénario le plus coûteux : boîtier bon marché sans NTP, réglé
        // à la main. L'appareil croit être le 15, le panel sait qu'on est
        // le 12, et la ligne court jusqu'au 13.
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 13),
            horlogeAppareil: DateTime(2026, 9, 15, 12, 0),
            horlogePanel: le12aMidi,
          ),
          VerdictLigne.vivante,
        );
      });

      test("sans horloge du panel, on retombe sur celle de l'appareil", () {
        // Même scénario, panel muet : le comportement d'avant. On ne fait
        // pas semblant de savoir.
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 13),
            horlogeAppareil: DateTime(2026, 9, 15, 12, 0),
          ),
          VerdictLigne.morte,
        );
      });

      test('une box en RETARD ne prolonge pas une ligne vraiment finie', () {
        // La symétrie compte : l'horloge du panel doit aussi pouvoir
        // accuser, pas seulement disculper.
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 1),
            horlogeAppareil: DateTime(2026, 8, 25),
            horlogePanel: le12aMidi,
          ),
          VerdictLigne.morte,
        );
      });
    });
  });

  group('statutSanctionne — banni / suspendu', () {
    test('reconnaît les formulations courantes', () {
      for (final String s in <String>[
        'Banned', 'disabled', 'user suspended', 'SUSPEND',
      ]) {
        expect(statutSanctionne(s), isTrue, reason: s);
      }
    });

    test('ne sanctionne ni « Active », ni vide, ni null', () {
      expect(statutSanctionne('Active'), isFalse);
      expect(statutSanctionne(''), isFalse);
      expect(statutSanctionne(null), isFalse);
    });

    test('la liste reste VOLONTAIREMENT courte', () {
      // « blocked » et « inactive » étaient dans la liste de la calibration
      // de source, pas dans celle du lecteur. En unifiant, on a gardé la
      // plus prudente : « banni » arrête les reconnexions du relais, donc
      // chaque mot ajouté ici est une nouvelle façon de couper un client.
      // Si quelqu'un les rajoute un jour, que ce soit un choix assumé —
      // et que ce test le lui rappelle.
      expect(statutSanctionne('blocked'), isFalse);
      expect(statutSanctionne('inactive'), isFalse);
    });
  });

  group("horlogePanelDepuisServerInfo — on ne croit pas n'importe quoi", () {
    test('lit timestamp_now en secondes, entier comme chaîne', () {
      final int s = DateTime(2026, 9, 12, 12).millisecondsSinceEpoch ~/ 1000;
      expect(horlogePanelDepuisServerInfo(<String, dynamic>{
        'timestamp_now': s,
      }), DateTime(2026, 9, 12, 12));
      expect(horlogePanelDepuisServerInfo(<String, dynamic>{
        'timestamp_now': '$s',
      }), DateTime(2026, 9, 12, 12));
    });

    test('bloc absent, champ absent, zéro, texte → null', () {
      expect(horlogePanelDepuisServerInfo(null), isNull);
      expect(horlogePanelDepuisServerInfo(<String, dynamic>{}), isNull);
      expect(
        horlogePanelDepuisServerInfo(<String, dynamic>{'timestamp_now': 0}),
        isNull,
      );
      expect(
        horlogePanelDepuisServerInfo(
          <String, dynamic>{'timestamp_now': 'bientôt'},
        ),
        isNull,
      );
    });

    test('une heure de panel ABSURDE est rejetée, pas subie', () {
      // Un panel bloqué en 1970 rendrait toutes les lignes éternelles ;
      // un panel réglé en 2099 les tuerait toutes d'un coup. Dans les deux
      // cas on préfère l'horloge de l'appareil.
      expect(
        horlogePanelDepuisServerInfo(
          <String, dynamic>{'timestamp_now': 1000000},
        ),
        isNull,
      );
      expect(
        horlogePanelDepuisServerInfo(
          <String, dynamic>{'timestamp_now': 4102444800},
        ),
        isNull,
      );
    });
  });
}
