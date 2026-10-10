// Un vrai échange HTTP reproduit une réponse qui arrive après les huit
// secondes accordées par l'app. Aucun client HTTP ni horloge n'est simulé.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/sports/data/sports_repository.dart';
import 'package:tv_king/features/sports/domain/sport_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Le binding protège normalement les tests widgets du réseau. Ici, la
  // preuve exige le vrai client et une vraie socket vers 127.0.0.1.
  HttpOverrides.global = null;
  setUp(() {
    RepairFlags.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(RepairFlags.debugReset);

  test('Sport accepte une équipe reçue après 9 secondes, en un seul appel',
      () async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final List<Future<void>> responses = <Future<void>>[];
    int calls = 0;
    Future<void> respond(HttpRequest request) async {
      calls++;
      expect(request.uri.path, '/api/sports/search');
      expect(request.uri.queryParameters['q'], 'Equipe test');
      expect(request.headers.value('accept'), 'application/json');
      await Future<void>.delayed(const Duration(seconds: 9));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, Object>{
        'teams': <Map<String, String>>[
          <String, String>{
            'id': '42',
            'name': 'Equipe test',
            'badge': 'https://badge.invalid/equipe.png',
            'league': 'Ligue test',
            'sport': 'Soccer',
          },
        ],
      }));
      await request.response.close();
    }

    final StreamSubscription<HttpRequest> subscription = server.listen(
      (HttpRequest request) => responses.add(respond(request)),
    );
    addTearDown(() async {
      await Future.wait(responses);
      await subscription.cancel();
      await server.close(force: true);
    });
    final SportsRepository repository = SportsRepository.forTesting(
        Uri.parse('http://127.0.0.1:${server.port}'));
    final teams = await repository.search('Equipe test');
    expect(teams, hasLength(1),
        reason: 'La réponse valide après 9 s ne doit pas devenir introuvable.');
    expect(teams.single.id, '42');
    expect(calls, 1, reason: 'Aucun réessai automatique ne masque le délai.');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Repli Sport : une réponse après 9 s redevient vide à 8 s', () async {
    RepairFlags.sportsNetworkLegacy = true;
    final _SportsServer server = await _SportsServer.start(
      body: jsonEncode(_teams), delay: const Duration(seconds: 9));
    addTearDown(server.close);
    final SportsSearchResult result = await server.repository.searchResult('Equipe test');
    expect(result.teams, isEmpty);
    expect(result.failure, isNull, reason: 'Ancien comportement : échec silencieux.');
    expect(server.calls, 1);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('HTTP 503 devient une raison distincte ; le repli restitue le vide', () async {
    final _SportsServer server = await _SportsServer.start(body: '{}', status: 503);
    addTearDown(server.close);
    final SportsSearchResult result = await server.repository.searchResult('Equipe test');
    expect(result.teams, isEmpty);
    expect(result.failure?.kind, SportsFailureKind.http);
    expect(result.failure?.statusCode, 503);
    expect(server.calls, 1);

    RepairFlags.sportsNetworkLegacy = true;
    final SportsSearchResult old = await server.repository.searchResult('Equipe test');
    expect(old.teams, isEmpty);
    expect(old.failure, isNull);
    expect(server.calls, 2, reason: 'Un appel pour chaque demande explicite.');
  });

  test('Réponse illisible et vraie recherche sans résultat restent distinctes', () async {
    final _SportsServer server = await _SportsServer.start(body: '<html>panne</html>');
    addTearDown(server.close);
    final SportsSearchResult invalid = await server.repository.searchResult('Equipe test');
    expect(invalid.failure?.kind, SportsFailureKind.invalidResponse);
    server.body = jsonEncode(<String, Object>{'teams': <Object>[]});
    final SportsSearchResult empty = await server.repository.searchResult('Equipe test');
    expect(empty.teams, isEmpty);
    expect(empty.failure, isNull);
    expect(server.calls, 2);
  });

  test('Une connexion refusée est visible, sans réessai automatique', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final Uri uri = Uri.parse('http://127.0.0.1:${server.port}');
    await server.close(force: true);
    final SportsSearchResult result = await SportsRepository.forTesting(uri)
        .searchResult('Equipe test');
    expect(result.failure?.kind, SportsFailureKind.network);
    expect(result.teams, isEmpty);
  });

  for (final bool legacy in <bool>[false, true]) {
    test('Matchs après 9 s : repli=$legacy', () async {
      RepairFlags.sportsNetworkLegacy = legacy;
      final _SportsServer server = await _SportsServer.start(
          body: jsonEncode(_events), delay: const Duration(seconds: 9));
      addTearDown(() async {
        await server.repository.removeFavorite('42');
        await server.close();
      });
      await server.repository.addFavorite(const SportTeam(id: '42', name: 'Equipe test'));
      final SportsEvents events = server.repository.eventsFor('42');
      expect(events.last, hasLength(legacy ? 0 : 1));
      expect(events.loading, isFalse);
      expect(events.failure, isNull);
      expect(server.calls, 1);
      expect(server.paths, <String>['/api/sports/team/42']);
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  test('Une panne des matchs garde le dernier score ; Réessayer relit le serveur', () async {
    final _SportsServer server = await _SportsServer.start(body: jsonEncode(_events));
    addTearDown(() async {
      await server.repository.removeFavorite('42');
      await server.close();
    });
    await server.repository.addFavorite(const SportTeam(id: '42', name: 'Equipe test'));
    final SportsEvents first = server.repository.eventsFor('42');
    expect(first.last, hasLength(1));
    server.status = 503;
    await server.repository.refreshTeam('42');
    final SportsEvents failed = server.repository.eventsFor('42');
    expect(failed.failure?.statusCode, 503);
    expect(failed.last, first.last);
    expect(failed.loading, isFalse);
    expect(server.calls, 2, reason: 'La panne ne déclenche pas de réessai.');
    server.status = 200;
    await server.repository.refreshTeam('42');
    expect(server.repository.eventsFor('42').failure, isNull);
    expect(server.calls, 3);
  });

  test('Le repli réseau Sport est éteint par défaut et chargé par sa clé', () async {
    await RepairFlags.load();
    expect(RepairFlags.sportsNetworkLegacy, isFalse);
    expect(RepairFlags.sportsNetworkLegacyKey, 'zuno.sports.network_legacy');
    SharedPreferences.setMockInitialValues(<String, Object>{
      RepairFlags.sportsNetworkLegacyKey: true,
    });
    await RepairFlags.load();
    expect(RepairFlags.sportsNetworkLegacy, isTrue);
    RepairFlags.debugReset();
    expect(RepairFlags.sportsNetworkLegacy, isFalse);
  });
}

const Map<String, Object> _teams = <String, Object>{
  'teams': <Map<String, String>>[<String, String>{'id': '42', 'name': 'Equipe test'}],
};
const Map<String, Object> _events = <String, Object>{
  'last': <Map<String, String>>[<String, String>{
    'id': '7', 'home': 'Equipe test', 'away': 'Equipe visiteuse',
    'homeScore': '2', 'awayScore': '1', 'date': '2026-01-01',
  }],
  'next': <Object>[],
};

class _SportsServer {
  _SportsServer(this.server, this.body, this.status, this.delay)
      : repository = SportsRepository.forTesting(Uri.parse('http://127.0.0.1:${server.port}'));
  final HttpServer server;
  final SportsRepository repository;
  String body;
  int status;
  final Duration delay;
  int calls = 0;
  final List<String> paths = <String>[];
  final List<Future<void>> _responses = <Future<void>>[];
  late final StreamSubscription<HttpRequest> _subscription;

  static Future<_SportsServer> start({required String body, int status = 200,
      Duration delay = Duration.zero}) async {
    final _SportsServer result = _SportsServer(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0), body, status, delay);
    result._subscription = result.server.listen(
        (HttpRequest request) => result._responses.add(result._respond(request)));
    return result;
  }

  Future<void> _respond(HttpRequest request) async {
    calls++;
    paths.add(request.uri.path);
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
