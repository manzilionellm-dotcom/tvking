// Un vrai échange HTTP reproduit une réponse qui arrive après les huit
// secondes accordées par l'app. Aucun client HTTP ni horloge n'est simulé.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/sports/data/sports_repository.dart';

void main() {
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
}
