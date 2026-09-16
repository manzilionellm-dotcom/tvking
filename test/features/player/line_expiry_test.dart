// =========================================================
//  line_expiry_test.dart — « on ne coupe pas un client qui a payé »
// =========================================================
//  12/09/2026 : l'app annonçait « expired on 13/09 » le 12.
//  16/09/2026 : elle disait « terminé » alors qu'il restait UN JOUR.
//  Le jour calendaire de exp_date est INCLUS. On ne coupe qu'après
//  le lendemain 00:00 + marge.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/line_expiry.dart';

void main() {
  final DateTime le12aMidi = DateTime(2026, 9, 12, 12, 0);
  final DateTime le13aMidi = DateTime(2026, 9, 13, 12, 0);

  group("dernierJourCouvert — le jour qu'on annonce au client", () {
    test('une fin à minuit COUVRE CE jour (le 13 est payé)', () {
      expect(
        formatJour(dernierJourCouvert(DateTime(2026, 9, 13))),
        '13/09/2026',
      );
    });

    test('une fin en pleine journée reste sur SON jour', () {
      expect(
        formatJour(dernierJourCouvert(DateTime(2026, 9, 13, 14, 30))),
        '13/09/2026',
      );
    });

    test('le format porte les zéros devant', () {
      expect(
        formatJour(dernierJourCouvert(DateTime(2026, 1, 6))),
        '06/01/2026',
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

    test('CAS 16/09 : le DERNIER jour, on ne coupe pas', () {
      // exp_date = 13/09 00:00 → le 13 est encore payé, même à 18 h.
      expect(
        jugerLigne(
          statut: 'Active',
          finDeLigne: DateTime(2026, 9, 13),
          horlogeAppareil: DateTime(2026, 9, 13, 18, 0),
        ),
        VerdictLigne.vivante,
      );
    });

    test('le lendemain matin (marge 12 h) : encore vivante', () {
      // Mort à partir du 14/09 12:00. À 14/09 11:59 → vivante.
      expect(
        jugerLigne(
          statut: 'Active',
          finDeLigne: DateTime(2026, 9, 13),
          horlogeAppareil: DateTime(2026, 9, 14, 11, 59),
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
      expect(
        jugerLigne(
          statut: 'Expired',
          finDeLigne: DateTime(2026, 10, 1),
          horlogeAppareil: le12aMidi,
        ),
        VerdictLigne.contradictoire,
      );
    });

    test('statut Expired LE DERNIER jour → contradictoire, pas morte', () {
      expect(
        jugerLigne(
          statut: 'Expired',
          finDeLigne: DateTime(2026, 9, 13),
          horlogeAppareil: le13aMidi,
        ),
        VerdictLigne.contradictoire,
      );
    });

    test("« Not Expired » ne se lit pas à l'envers", () {
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
      test('deux heures après minuit du lendemain : encore vivante', () {
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 12, 10, 0),
            horlogeAppareil: le12aMidi,
          ),
          VerdictLigne.vivante,
        );
      });

      test('au-delà de la marge après le lendemain : morte', () {
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 10, 12, 0),
            horlogeAppareil: le12aMidi,
          ),
          VerdictLigne.morte,
        );
      });

      test('juste AVANT la limite exacte de la marge : vivante', () {
        // Dernier jour 12/09 → mort après 13/09 00:00 + 12 h = 13/09 12:00.
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 12, 12, 0),
            horlogeAppareil: DateTime(2026, 9, 13, 11, 59),
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
        expect(
          jugerLigne(
            statut: 'Active',
            finDeLigne: DateTime(2026, 9, 13),
            horlogeAppareil: DateTime(2026, 9, 16, 12, 0),
          ),
          VerdictLigne.morte,
        );
      });

      test('une box en RETARD ne prolonge pas une ligne vraiment finie', () {
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
