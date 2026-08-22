// =========================================================
//  match_alerts_test.dart — Alertes des grands matchs
// =========================================================
//  Demande client (22/08) : « les notifications des grands matchs
//  automatiquement — si le Real joue Chelsea — et les résultats
//  instantanés. »
//
//  CE QU'ON VERROUILLE ICI : les pièces PURES du service, celles dont
//  une erreur ne plante RIEN mais rend l'app silencieuse — le pire des
//  bugs, parce qu'il ne se voit pas.
//
//   1. L'HEURE du coup d'envoi : le panel donne l'heure en UTC, le client
//      vit dans son fuseau. Une conversion ratée programme l'alarme dans
//      le passé → aucune notification, aucune erreur, aucun indice.
//   2. L'EMPLACEMENT de notification : deux passes sur le MÊME match
//      doivent viser le même identifiant (remplacement), sinon le client
//      reçoit la même alerte en double à chaque rafraîchissement.
//   3. Le LIBELLÉ : « Real Madrid – Chelsea », avec repli sur le nom brut
//      quand le panel ne sépare pas les deux camps.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/sports/data/match_alerts_service.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

void main() {
  final MatchAlertsService svc = MatchAlertsService.instance;

  group('heure du coup d\'envoi (UTC → locale)', () {
    test('timestamp ISO UTC → même INSTANT, exprimé en heure locale', () {
      const SportEvent ev = SportEvent(
        id: '1',
        home: 'Real Madrid',
        away: 'Chelsea',
        timestamp: '2026-09-15T19:00:00+00:00',
      );
      final DateTime? k = ev.startsAt;
      expect(k, isNotNull);
      // On compare en UTC : le test doit passer quel que soit le fuseau de
      // la machine qui l'exécute (CI en UTC, poste de dev en Europe/Paris).
      expect(k!.toUtc(), DateTime.utc(2026, 9, 15, 19));
      expect(k.isUtc, isFalse, reason: 'l\'alarme se programme en local');
    });

    test('repli date + heure quand le panel ne donne pas de timestamp', () {
      const SportEvent ev = SportEvent(
        id: '2',
        home: 'Real Madrid',
        away: 'Chelsea',
        date: '2026-09-15',
        time: '19:00:00',
      );
      expect(ev.startsAt!.toUtc(), DateTime.utc(2026, 9, 15, 19));
    });

    test('sans date exploitable → null (le match est simplement ignoré)', () {
      const SportEvent ev = SportEvent(id: '3', home: 'A', away: 'B');
      expect(ev.startsAt, isNull);
    });
  });

  group('emplacement de notification', () {
    test('STABLE : le même match vise toujours le même emplacement', () {
      expect(svc.slot('2052478'), svc.slot('2052478'));
    });

    test('BORNÉ à 1000 : jamais de collision avec une autre famille', () {
      for (final String id in <String>[
        '1',
        '2052478',
        'abcdef',
        '999999999999999999',
        '',
      ]) {
        expect(svc.slot(id), inInclusiveRange(0, 999));
      }
    });

    test('DISCRIMINANT : deux matchs voisins ne se recouvrent pas', () {
      expect(svc.slot('2052478'), isNot(svc.slot('2052479')));
    });
  });

  group('libellé de l\'affiche', () {
    test('deux camps connus → « Real Madrid – Chelsea »', () {
      const SportEvent ev =
          SportEvent(id: '1', home: 'Real Madrid', away: 'Chelsea');
      expect(svc.label(ev), 'Real Madrid – Chelsea');
    });

    test('camps manquants → repli sur le nom brut du match', () {
      const SportEvent ev =
          SportEvent(id: '1', name: 'Real Madrid vs Chelsea');
      expect(svc.label(ev), 'Real Madrid vs Chelsea');
    });
  });

  group('score : on n\'annonce que ce qui est vraiment connu', () {
    test('score complet → annonçable', () {
      const SportEvent ev = SportEvent(
          id: '1', home: 'A', away: 'B', homeScore: '2', awayScore: '1');
      expect(ev.hasScore, isTrue);
    });

    test('score vide ou absent → on se tait (0–0 ≠ pas encore joué)', () {
      const SportEvent pending = SportEvent(id: '1', home: 'A', away: 'B');
      expect(pending.hasScore, isFalse);
      const SportEvent halfKnown = SportEvent(
          id: '2', home: 'A', away: 'B', homeScore: '2', awayScore: '');
      expect(halfKnown.hasScore, isFalse);
    });
  });
}
