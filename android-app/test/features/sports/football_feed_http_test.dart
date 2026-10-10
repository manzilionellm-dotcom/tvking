// La preuve traverse une vraie socket HTTP et le décodage en isolate.
// Les données synthétiques reprennent le schéma public, jamais un flux IPTV.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/sports/data/football_feed_repository.dart';
import 'package:tv_king/features/sports/data/sports_repository.dart';
import 'package:tv_king/features/sports/domain/football_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  setUp(() {
    RepairFlags.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(RepairFlags.debugReset);

  test('OpenLigaDB : score final par type, buts et horaire UTC, sans clé', () async {
    final _FeedServer server = await _FeedServer.start(jsonEncode(_league));
    addTearDown(server.close);
    final FootballFeedResult result = await server.repository.load(FootballCompetition.bundesliga);
    expect(result.failure, isNull);
    expect(result.matches, hasLength(1));
    final FootballMatch match = result.matches.single;
    expect(match.homeScore, 3, reason: 'Le tableau finit par la mi-temps 1–0.');
    expect(match.awayScore, 2);
    expect(match.finished, isTrue);
    expect(match.startsAt.isUtc, isTrue);
    expect(match.goals.map((FootballGoal g) => g.minute), <int>[12, 85]);
    expect(match.goals.last.player, 'Joueur test');
    expect(server.paths, <String>['/getmatchdata/bl1']);
    expect(server.authorizations, <String?>[null]);
    expect(result.receivedAt, isNotNull);
  });

  test('OpenFootball : saison courante, score ft, absence de score respectée', () async {
    final _FeedServer server = await _FeedServer.start(jsonEncode(_calendar));
    addTearDown(server.close);
    final FootballFeedResult result = await server.repository.load(
        FootballCompetition.ligue1, now: DateTime(2026, 10, 8));
    expect(result.failure, isNull);
    expect(server.paths, <String>['/datasets/2026-27/fr.1.json']);
    expect(result.matches, hasLength(2));
    expect(result.matches.first.homeScore, 2);
    expect(result.matches.first.awayScore, 1);
    expect(result.matches.first.finished, isTrue);
    expect(result.matches.last.hasScore, isFalse);
    expect(result.matches.last.finished, isFalse);
    expect(result.matches.last.goals, isEmpty);
    await server.repository.load(FootballCompetition.ligue1, now: DateTime(2027, 3, 1));
    expect(server.paths.last, '/datasets/2026-27/fr.1.json');
  });

  test('Un score de mi-temps seul ne devient pas un score final', () {
    final Map<String, Object> halfOnly = Map<String, Object>.from(_league.single);
    halfOnly['matchResults'] = <Map<String, int>>[
      <String, int>{'resultTypeID': 1, 'pointsTeam1': 1, 'pointsTeam2': 0},
    ];
    final FootballMatch match = decodeFootballFeed(
        (FootballSource.openLigaDb, jsonEncode(<Object>[halfOnly]))).single;
    expect(match.hasScore, isFalse);
  });

  test('Le repli retire le service sans aucun appel HTTP', () async {
    final _FeedServer server = await _FeedServer.start(jsonEncode(_league));
    addTearDown(server.close);
    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.sportsCommunityOffKey: true,
    });
    await RepairFlags.load();
    final FootballFeedResult old = await server.repository.load(FootballCompetition.bundesliga);
    expect(old.disabled, isTrue);
    expect(old.matches, isEmpty);
    expect(server.paths, isEmpty, reason: 'Ancien Sport : aucun accès OpenLigaDB.');
    RepairFlags.debugReset();
    expect(RepairFlags.sportsCommunityOff, isFalse);
    final FootballFeedResult current = await server.repository.load(FootballCompetition.bundesliga);
    expect(current.disabled, isFalse);
    expect(current.matches, hasLength(1));
    expect(server.paths, hasLength(1));
  });

  test('HTTP 503 et JSON illisible restent visibles, sans réessai', () async {
    final _FeedServer server = await _FeedServer.start('{}');
    addTearDown(server.close);
    server.status = 503;
    final FootballFeedResult down = await server.repository.load(FootballCompetition.bundesliga);
    expect(down.failure?.kind, SportsFailureKind.http);
    expect(down.failure?.statusCode, 503);
    expect(server.paths, hasLength(1));
    server.status = 200;
    server.body = '<html>panne</html>';
    final FootballFeedResult invalid = await server.repository.load(FootballCompetition.bundesliga);
    expect(invalid.failure?.kind, SportsFailureKind.invalidResponse);
    expect(server.paths, hasLength(2));
  });

  test('Une réponse trop volumineuse est arrêtée avant le décodage', () async {
    final _FeedServer server = await _FeedServer.start(
        List<String>.filled(FootballFeedRepository.maxResponseBytes + 1, ' ').join());
    addTearDown(server.close);
    final FootballFeedResult result = await server.repository.load(FootballCompetition.bundesliga);
    expect(result.failure?.kind, SportsFailureKind.invalidResponse);
    expect(server.paths, hasLength(1));
  });

  test('Une réponse communautaire après 9 s est acceptée en un seul appel', () async {
    final _FeedServer server = await _FeedServer.start(jsonEncode(_league));
    server.delay = const Duration(seconds: 9);
    addTearDown(server.close);
    final FootballFeedResult result = await server.repository.load(FootballCompetition.bundesliga);
    expect(result.matches, hasLength(1));
    expect(result.failure, isNull);
    expect(server.paths, hasLength(1));
  }, timeout: const Timeout(Duration(seconds: 30)));
}

const List<Map<String, Object>> _league = <Map<String, Object>>[
  <String, Object>{
    'team1': <String, String>{'teamName': 'Equipe A'},
    'team2': <String, String>{'teamName': 'Equipe B'},
    'matchDateTimeUTC': '2026-10-08T19:00:00Z',
    'matchIsFinished': true,
    'matchResults': <Map<String, int>>[
      <String, int>{'resultTypeID': 2, 'pointsTeam1': 3, 'pointsTeam2': 2},
      <String, int>{'resultTypeID': 1, 'pointsTeam1': 1, 'pointsTeam2': 0},
    ],
    'goals': <Map<String, Object>>[
      <String, Object>{'scoreTeam1': 3, 'scoreTeam2': 2, 'matchMinute': 85, 'goalGetterName': 'Joueur test'},
      <String, Object>{'scoreTeam1': 1, 'scoreTeam2': 0, 'matchMinute': 12, 'goalGetterName': 'Autre joueur'},
    ],
  },
];
const Map<String, Object> _calendar = <String, Object>{
  'matches': <Map<String, Object>>[
    <String, Object>{'team1': 'Equipe A', 'team2': 'Equipe B', 'date': '2026-10-08',
      'score': <String, List<int>>{'ht': <int>[0, 0], 'ft': <int>[2, 1]}},
    <String, Object>{'team1': 'Equipe C', 'team2': 'Equipe D', 'date': '2026-10-09'},
  ],
};

class _FeedServer {
  _FeedServer(this.server, this.body) : repository = FootballFeedRepository.forTesting(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      Uri.parse('http://127.0.0.1:${server.port}/datasets/'));
  final HttpServer server;
  final FootballFeedRepository repository;
  String body;
  int status = 200;
  Duration delay = Duration.zero;
  final List<String> paths = <String>[];
  final List<String?> authorizations = <String?>[];
  final List<Future<void>> _responses = <Future<void>>[];
  late final StreamSubscription<HttpRequest> _subscription;
  static Future<_FeedServer> start(String body) async {
    final _FeedServer result = _FeedServer(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0), body);
    result._subscription = result.server.listen((HttpRequest r) => result._responses.add(result._respond(r)));
    return result;
  }
  Future<void> _respond(HttpRequest request) async {
    paths.add(request.uri.path);
    authorizations.add(request.headers.value('authorization'));
    await Future<void>.delayed(delay);
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
  }
  Future<void> close() async {
    await Future.wait(_responses);
    await _subscription.cancel();
    await server.close(force: true);
  }
}
