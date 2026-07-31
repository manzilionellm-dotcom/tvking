// Tests des heures murales locales (wall_clock.dart) — le cœur du
// correctif « le nudge de 20 h sonnait à 20 h UTC ». Fonctions pures :
// aucune init de plugin ni de base de fuseaux nécessaire.
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/notifications/wall_clock.dart';

void main() {
  group('nextLocalOccurrence', () {
    test('avant 20 h → ce soir 20 h pile', () {
      final DateTime now = DateTime(2026, 7, 30, 14, 35, 12);
      final DateTime at = nextLocalOccurrence(now, 20);
      expect(at, DateTime(2026, 7, 30, 20));
    });

    test('après 20 h → demain 20 h', () {
      final DateTime now = DateTime(2026, 7, 30, 21, 5);
      final DateTime at = nextLocalOccurrence(now, 20);
      expect(at, DateTime(2026, 7, 31, 20));
    });

    test('20 h 00 pile (pas strictement futur) → demain', () {
      final DateTime now = DateTime(2026, 7, 30, 20);
      expect(nextLocalOccurrence(now, 20), DateTime(2026, 7, 31, 20));
    });

    test('fin de mois : le constructeur normalise le jour', () {
      final DateTime now = DateTime(2026, 7, 31, 22);
      expect(nextLocalOccurrence(now, 20), DateTime(2026, 8, 1, 20));
    });

    test('fin d\'année', () {
      final DateTime now = DateTime(2026, 12, 31, 23, 30);
      expect(nextLocalOccurrence(now, 20), DateTime(2027, 1, 1, 20));
    });
  });

  group('localDayAt', () {
    test('J+2 à 19 h, heure murale exacte', () {
      final DateTime now = DateTime(2026, 7, 30, 9, 12);
      expect(localDayAt(now, 2, 19), DateTime(2026, 8, 1, 19));
    });

    test('J+0 = aujourd\'hui à l\'heure demandée', () {
      final DateTime now = DateTime(2026, 7, 30, 9, 12);
      expect(localDayAt(now, 0, 19), DateTime(2026, 7, 30, 19));
    });

    test('J+30 traverse le mois sans dérive d\'heure', () {
      final DateTime now = DateTime(2026, 7, 30, 23, 59);
      expect(localDayAt(now, 30, 19), DateTime(2026, 8, 29, 19));
    });
  });
}
