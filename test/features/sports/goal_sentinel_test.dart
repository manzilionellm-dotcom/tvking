// =========================================================
//  goal_sentinel_test.dart — « Prévenu en direct » même hors de l'écran Sport
// =========================================================
//  Demande du propriétaire (06/09/2026) : « configure les alertes buts
//  pour que je sois prévenu en direct ».
//
//  Ce que ces tests VERROUILLENT, et pourquoi chacun compte :
//
//   1. La FENÊTRE d'un match : on n'interroge le réseau qu'entre 5 min
//      avant et 3 h après le coup d'envoi. Une borne fausse d'un signe
//      et la sentinelle tournerait toute la nuit — ou raterait le match.
//   2. Ce qui MÉRITE une alerte : match suivi, match d'une équipe
//      favorite (par identifiant ou par nom), et rien d'autre. Un match
//      « quelconque » qui sonnerait, c'est une désinstallation.
//   3. La sentinelle ELLE-MÊME, à l'horloge simulée : sans match qui
//      compte, ZÉRO requête en une heure ; avec un match suivi en cours,
//      une requête tout de suite puis une toutes les 45 s ; quand le
//      match sort de sa fenêtre, les requêtes s'arrêtent d'elles-mêmes.
//   4. Le corps de l'alerte : le score ET la minute quand on l'a.
// =========================================================
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/sports/data/followed_matches_service.dart';
import 'package:tv_king/features/sports/data/live_scores_service.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

SportEvent _match(
  String id, {
  DateTime? kickoff,
  String home = 'Real Madrid',
  String away = 'Chelsea',
  String status = '',
  String progress = '',
  String? homeScore,
  String? awayScore,
}) =>
    SportEvent(
      id: id,
      home: home,
      away: away,
      status: status,
      progress: progress,
      homeScore: homeScore,
      awayScore: awayScore,
      timestamp: kickoff == null ? '' : kickoff.toUtc().toIso8601String(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime now = DateTime.utc(2026, 9, 6, 20, 0);

  group('fenêtre du match (fonction pure)', () {
    test('5 min avant → dedans ; 6 min avant → dehors', () {
      expect(
        LiveScoresService.inAlertWindow(
            _match('1', kickoff: now.add(const Duration(minutes: 5))), now),
        isTrue,
      );
      expect(
        LiveScoresService.inAlertWindow(
            _match('1', kickoff: now.add(const Duration(minutes: 6))), now),
        isFalse,
      );
    });

    test('pendant le match → dedans ; 3 h après → borne incluse ; au-delà → dehors',
        () {
      expect(
        LiveScoresService.inAlertWindow(
            _match('1', kickoff: now.subtract(const Duration(minutes: 70))),
            now),
        isTrue,
      );
      expect(
        LiveScoresService.inAlertWindow(
            _match('1', kickoff: now.subtract(const Duration(hours: 3))), now),
        isTrue,
      );
      expect(
        LiveScoresService.inAlertWindow(
            _match('1',
                kickoff: now.subtract(const Duration(hours: 3, minutes: 1))),
            now),
        isFalse,
      );
    });

    test('sans horaire connu → dehors (on ne réveille pas le réseau à l\'aveugle)',
        () {
      expect(LiveScoresService.inAlertWindow(_match('1'), now), isFalse);
    });
  });

  group('ce qui mérite une alerte (fonction pure)', () {
    final SportEvent m = _match('42', home: 'Real Madrid', away: 'Chelsea');

    test('match suivi un par un → oui', () {
      expect(
        LiveScoresService.alertWorthy(m,
            followedIds: <String>{'42'},
            favoriteEventIds: <String>{},
            favoriteNames: <String>{}),
        isTrue,
      );
    });

    test('match connu d\'une équipe favorite (par identifiant) → oui', () {
      expect(
        LiveScoresService.alertWorthy(m,
            followedIds: <String>{},
            favoriteEventIds: <String>{'42'},
            favoriteNames: <String>{}),
        isTrue,
      );
    });

    test('équipe favorite reconnue par son NOM, sans la casse, à domicile ou dehors',
        () {
      expect(
        LiveScoresService.alertWorthy(m,
            followedIds: <String>{},
            favoriteEventIds: <String>{},
            favoriteNames: <String>{'chelsea'}),
        isTrue,
        reason: 'équipe extérieure',
      );
      expect(
        LiveScoresService.alertWorthy(m,
            followedIds: <String>{},
            favoriteEventIds: <String>{},
            favoriteNames: <String>{'real madrid'}),
        isTrue,
        reason: 'équipe à domicile',
      );
    });

    test('match quelconque → NON (le garde-fou n° 1)', () {
      expect(
        LiveScoresService.alertWorthy(m,
            followedIds: <String>{'1', '2'},
            favoriteEventIds: <String>{'3'},
            favoriteNames: <String>{'arsenal', 'psg'}),
        isFalse,
      );
    });

    test('identifiant vide → jamais (sinon tous les sans-id se reconnaîtraient)',
        () {
      expect(
        LiveScoresService.alertWorthy(_match('', home: 'PSG', away: 'Lyon'),
            followedIds: <String>{''},
            favoriteEventIds: <String>{''},
            favoriteNames: <String>{'psg'}),
        isFalse,
      );
    });
  });

  group('corps de l\'alerte', () {
    test('score + minute quand la source la donne', () {
      expect(
        LiveScoresService.goalBody(_match('1',
            status: '2H', progress: '67', homeScore: '2', awayScore: '1')),
        "Real Madrid 2–1 Chelsea · 67'",
      );
    });

    test('score seul quand la minute manque', () {
      expect(
        LiveScoresService.goalBody(
            _match('1', homeScore: '1', awayScore: '0')),
        'Real Madrid 1–0 Chelsea',
      );
    });
  });

  group('la sentinelle, à l\'horloge simulée', () {
    final LiveScoresService s = LiveScoresService.instance;
    final FollowedMatchesService followed = FollowedMatchesService.instance;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await followed.clear();
      s.stopSentinel();
      s.debugSeed(const <SportEvent>[]);
    });

    tearDown(() {
      s.stopSentinel();
      s.debugRefreshOverride = null;
      s.debugClock = null;
    });

    /// fake_async avance les MINUTEURS, pas `DateTime.now()` : on donne
    /// donc au service une horloge qui suit l'horloge simulée. Les coups
    /// d'envoi sont datés par rapport à `start`, l'heure réelle du test,
    /// pour que le ménage de FollowedMatchesService (2 jours) ne les
    /// jette pas.
    DateTime Function() clockFor(FakeAsync async, DateTime start) {
      final DateTime Function() c = async.getClock(start).now;
      s.debugClock = c;
      return c;
    }

    test('sans match qui compte : ZÉRO requête en une heure', () {
      fakeAsync((FakeAsync async) {
        clockFor(async, DateTime.now());
        int hits = 0;
        s.debugRefreshOverride = () async => hits++;
        s.startSentinel();
        async.elapse(const Duration(hours: 1));
        expect(hits, 0);
        expect(s.sentinelOn, isTrue);
      });
    });

    test('un match suivi EN COURS : une requête tout de suite, puis toutes les 45 s',
        () {
      fakeAsync((FakeAsync async) {
        final DateTime start = DateTime.now();
        clockFor(async, start);
        int hits = 0;
        s.debugRefreshOverride = () async => hits++;
        // Coup d'envoi il y a 20 minutes : le match se joue.
        followed.toggle(
            _match('7', kickoff: start.subtract(const Duration(minutes: 20))));
        async.flushMicrotasks();
        s.startSentinel();
        async.flushMicrotasks();
        expect(hits, 1, reason: 'première requête immédiate');
        async.elapse(const Duration(seconds: 45));
        expect(hits, 2);
        async.elapse(const Duration(minutes: 3));
        expect(hits, 6, reason: '45 s × 4 tics de plus');
      });
    });

    test('suivre un match pendant la veille RÉARME sans attendre le tic de 5 min',
        () {
      fakeAsync((FakeAsync async) {
        final DateTime start = DateTime.now();
        clockFor(async, start);
        int hits = 0;
        s.debugRefreshOverride = () async => hits++;
        s.startSentinel();
        async.elapse(const Duration(minutes: 1));
        expect(hits, 0);
        followed.toggle(
            _match('8', kickoff: start.add(const Duration(minutes: 3))));
        async.flushMicrotasks();
        expect(hits, 1, reason: 'la fenêtre s\'ouvre → requête immédiate');
      });
    });

    test('quand le match sort de sa fenêtre, les requêtes S\'ARRÊTENT', () {
      fakeAsync((FakeAsync async) {
        final DateTime start = DateTime.now();
        clockFor(async, start);
        int hits = 0;
        s.debugRefreshOverride = () async => hits++;
        // Coup d'envoi il y a 2 h 58 : la fenêtre de 3 h se ferme dans 2 min.
        followed.toggle(_match('9',
            kickoff: start.subtract(const Duration(hours: 2, minutes: 58))));
        async.flushMicrotasks();
        s.startSentinel();
        async.flushMicrotasks();
        expect(hits, 1);
        async.elapse(const Duration(minutes: 3));
        final int atClose = hits;
        expect(atClose, greaterThanOrEqualTo(2));
        // Une heure de plus : plus aucune requête.
        async.elapse(const Duration(hours: 1));
        expect(hits, atClose, reason: 'fenêtre fermée = réseau au repos');
      });
    });

    test('stopSentinel coupe tout, startSentinel est idempotent', () {
      fakeAsync((FakeAsync async) {
        final DateTime start = DateTime.now();
        clockFor(async, start);
        int hits = 0;
        s.debugRefreshOverride = () async => hits++;
        followed.toggle(
            _match('10', kickoff: start.subtract(const Duration(minutes: 5))));
        async.flushMicrotasks();
        s.startSentinel();
        s.startSentinel(); // deuxième appel : pas de second minuteur
        async.flushMicrotasks();
        expect(hits, 1);
        async.elapse(const Duration(seconds: 45));
        expect(hits, 2, reason: 'un seul minuteur, pas deux');
        s.stopSentinel();
        async.elapse(const Duration(minutes: 10));
        expect(hits, 2);
        expect(s.sentinelOn, isFalse);
      });
    });
  });
}
