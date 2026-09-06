// =========================================================
//  predictions_test.dart — Les pronostics des fans, côté app
// =========================================================
//  Ce qu'on verrouille :
//   1. QUAND on peut voter : un duel, avec un coup d'envoi connu et à
//      venir, ni en direct ni terminé. Une borne fausse et l'écran
//      proposerait de pronostiquer un match déjà joué.
//   2. MON VOTE SE VOIT TOUT DE SUITE, réseau ou pas, et SURVIT au
//      redémarrage (préférences).
//   3. LES POURCENTAGES SONT CEUX DU SERVEUR, lus avec tolérance : un
//      champ absent ne fait jamais planter la ligne du match.
//   4. Le serveur qui connaît un vote posé depuis un AUTRE appareil du
//      client (sa box) l'emporte sur la mémoire locale vide.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/sports/data/predictions_service.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

SportEvent _duel(
  String id, {
  DateTime? kickoff,
  String status = '',
  String? homeScore,
  String? awayScore,
  String home = 'Real Madrid',
  String away = 'Chelsea',
}) =>
    SportEvent(
      id: id,
      home: home,
      away: away,
      status: status,
      homeScore: homeScore,
      awayScore: awayScore,
      timestamp: kickoff == null ? '' : kickoff.toUtc().toIso8601String(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final DateTime now = DateTime.utc(2026, 9, 6, 20);

  group('quand peut-on voter (fonction pure)', () {
    test('duel à venir → oui', () {
      expect(
        PredictionsService.isOpen(
            _duel('1', kickoff: now.add(const Duration(hours: 2))), now),
        isTrue,
      );
    });

    test('coup d\'envoi passé → non', () {
      expect(
        PredictionsService.isOpen(
            _duel('1', kickoff: now.subtract(const Duration(minutes: 1))), now),
        isFalse,
      );
    });

    test('déjà en direct ou avec un score → non, même si l\'horaire dit le futur',
        () {
      final DateTime later = now.add(const Duration(hours: 1));
      expect(
        PredictionsService.isOpen(_duel('1', kickoff: later, status: '1H'), now),
        isFalse,
      );
      expect(
        PredictionsService.isOpen(
            _duel('1', kickoff: later, homeScore: '1', awayScore: '0'), now),
        isFalse,
      );
    });

    test('sans horaire, ou sans deux camps (course) → non', () {
      expect(PredictionsService.isOpen(_duel('1'), now), isFalse);
      expect(
        PredictionsService.isOpen(
            _duel('1',
                kickoff: now.add(const Duration(hours: 1)), home: '', away: ''),
            now),
        isFalse,
      );
    });
  });

  group('lecture du JSON serveur', () {
    test('champs présents → comptes et mon vote', () {
      final PredictionTally t = PredictionTally.fromJson(<String, dynamic>{
        'total': 3,
        'percent': <String, dynamic>{'home': 67, 'draw': 33, 'away': 0},
        'mine': 'draw',
      });
      expect(t.total, 3);
      expect(t.pct(Pick.home), 67);
      expect(t.pct(Pick.draw), 33);
      expect(t.mine, Pick.draw);
    });

    test('champs absents ou malformés → zéros, jamais d\'exception', () {
      final PredictionTally t = PredictionTally.fromJson(<String, dynamic>{
        'percent': 'pas un objet',
        'mine': 'n\'importe quoi',
      });
      expect(t.total, 0);
      expect(t.pct(Pick.away), 0);
      expect(t.mine, isNull);
    });
  });

  group('le service', () {
    final PredictionsService svc = PredictionsService.instance;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await svc.debugReset();
      svc.debugFetch = null;
      svc.debugSend = null;
    });

    test('mon vote se voit TOUT DE SUITE, même si le serveur ne répond pas',
        () async {
      svc.debugSend = (String id, Pick p, DateTime? k) async => null;
      final SportEvent m = _duel('7', kickoff: now.add(const Duration(hours: 1)));
      final bool ok = await svc.vote(m, Pick.home);
      expect(ok, isFalse, reason: 'le serveur n\'a pas confirmé');
      expect(svc.myPick('7'), Pick.home,
          reason: 'mais le choix est là, localement');
    });

    test('le vote SURVIT au redémarrage', () async {
      svc.debugSend = (String id, Pick p, DateTime? k) async => null;
      await svc.vote(_duel('8', kickoff: now.add(const Duration(hours: 1))),
          Pick.away);
      // Redémarrage simulé : mémoire vidée, préférences conservées.
      await svc.debugResetMemoryOnly();
      await svc.ensureLoaded();
      expect(svc.myPick('8'), Pick.away);
    });

    test('le serveur confirme → les pourcentages sont les siens', () async {
      DateTime? sentKickoff;
      svc.debugSend = (String id, Pick p, DateTime? k) async {
        sentKickoff = k;
        return <String, dynamic>{
          'total': 10,
          'percent': <String, dynamic>{'home': 60, 'draw': 30, 'away': 10},
          'mine': p.name,
        };
      };
      final DateTime kick = now.add(const Duration(hours: 1));
      expect(await svc.vote(_duel('9', kickoff: kick), Pick.draw), isTrue);
      final PredictionTally? t = svc.tallyFor('9');
      expect(t, isNotNull);
      expect(t!.total, 10);
      expect(t.pct(Pick.home), 60);
      expect(t.mine, Pick.draw);
      expect(sentKickoff, isNotNull,
          reason: 'le coup d\'envoi est envoyé : le serveur ferme dessus');
    });

    test('un vote posé sur la BOX du client apparaît sur son téléphone',
        () async {
      // La mémoire locale est vide ; le serveur, lui, connaît la MAC.
      svc.debugFetch = (String id) async => <String, dynamic>{
            'total': 1,
            'percent': <String, dynamic>{'home': 100, 'draw': 0, 'away': 0},
            'mine': 'home',
          };
      await svc.load('10');
      expect(svc.myPick('10'), Pick.home);
      expect(svc.tallyFor('10')!.mine, Pick.home);
    });

    test('serveur muet → on garde ce qu\'on avait, rien ne casse', () async {
      svc.debugFetch = (String id) async => throw Exception('réseau');
      await svc.load('11');
      expect(svc.tallyFor('11'), isNull);
    });
  });
}
