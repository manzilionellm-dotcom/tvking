// Tests des modèles sportifs (purs, sans réseau) : parsing défensif,
// conversion de date (timestamp ISO / date seule / invalide), score.

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

void main() {
  group('SportEvent.startsAt', () {
    test('timestamp ISO UTC → heure locale', () {
      const SportEvent e = SportEvent(
        id: '1',
        timestamp: '2026-08-02T19:00:00+00:00',
      );
      final DateTime? dt = e.startsAt;
      expect(dt, isNotNull);
      expect(dt!.toUtc().hour, 19);
    });

    test('repli date + heure quand pas de timestamp', () {
      const SportEvent e =
          SportEvent(id: '1', date: '2026-08-02', time: '21:00:00');
      final DateTime? dt = e.startsAt;
      expect(dt, isNotNull);
      expect(dt!.toUtc().hour, 21);
    });

    test('date seule → minuit UTC', () {
      const SportEvent e = SportEvent(id: '1', date: '2026-08-02');
      expect(e.startsAt, isNotNull);
    });

    test('rien de connu → null (jamais de date inventée)', () {
      const SportEvent e = SportEvent(id: '1');
      expect(e.startsAt, isNull);
    });

    test('timestamp illisible → repli date, sinon null', () {
      const SportEvent bad =
          SportEvent(id: '1', timestamp: 'pas-une-date');
      expect(bad.startsAt, isNull);
    });
  });

  group('SportEvent.hasScore', () {
    test('les deux scores présents', () {
      const SportEvent e =
          SportEvent(id: '1', homeScore: '2', awayScore: '1');
      expect(e.hasScore, isTrue);
    });

    test('score partiel ou vide → pas de score affiché', () {
      const SportEvent a = SportEvent(id: '1', homeScore: '2');
      const SportEvent b =
          SportEvent(id: '1', homeScore: '', awayScore: '');
      expect(a.hasScore, isFalse);
      expect(b.hasScore, isFalse);
    });
  });

  group('fromJson défensif', () {
    test('champs manquants → valeurs vides, pas de crash', () {
      final SportEvent e = SportEvent.fromJson(const <String, dynamic>{});
      expect(e.id, '');
      expect(e.hasScore, isFalse);
      expect(e.startsAt, isNull);
    });

    test('équipe minimale', () {
      final SportTeam t =
          SportTeam.fromJson(const <String, dynamic>{'id': 5, 'name': 'Arsenal'});
      expect(t.id, '5');
      expect(t.name, 'Arsenal');
      expect(t.badge, '');
    });
  });
}
