// HTTP simulé seulement : le stockage local et les identifiants sont réels.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/support/data/support_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:CC:11:22:33:44',
    }),
  );
  test(
    'identité privée stable : le secret est dans l’en-tête, jamais dans l’URL',
    () async {
      final List<http.Request> seen = <http.Request>[];
      final http.Client client = MockClient((http.Request r) async {
        seen.add(r);
        return http.Response(
          '{"items":[],"unread":2,"owner_read_seq":0,"more":false}',
          200,
        );
      });
      final SupportRepository a = SupportRepository(client: client);
      expect(await a.unread(), 2);
      await Future.wait(<Future<SupportPage>>[
        a.messages(),
        a.messages(before: 9),
      ]);
      await SupportRepository(client: client).unread();
      final String token =
          seen.first.headers['X-Support-Token'] ??
          seen.first.headers['x-support-token']!;
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      final String id = (await Sha256().hash(utf8.encode(token))).bytes
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      for (final http.Request r in seen) {
        expect(r.url.path, '/api/support/$id');
        expect(r.url.toString(), isNot(contains(token)));
        expect(r.url.toString(), isNot(contains('MK:')));
        expect(r.headers.values, contains(token));
      }
      expect(seen[2].url.queryParameters['before'], '9');
    },
  );
  test('un envoi incertain conserve son identifiant pour la reprise', () async {
    final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
    final SupportRepository repo = SupportRepository(
      client: MockClient((http.Request r) async {
        bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
        if (bodies.length == 1) throw http.ClientException('hors ligne');
        return http.Response('{}', 201);
      }),
    );
    final String id = SupportRepository.newMessageId();
    await expectLater(repo.send(' Bonjour ', id), throwsStateError);
    await repo.send(' Bonjour ', id);
    expect(bodies[0], bodies[1]);
    expect(bodies[1]['body'], 'Bonjour');
    expect(bodies[1]['client_id'], id);
  });
  test(
    'les erreurs serveur ne divulguent pas leur contenu au client',
    () async {
      final SupportRepository repo = SupportRepository(
        client: MockClient((_) async => http.Response('secret interne', 500)),
      );
      await expectLater(
        repo.unread(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.toString(),
            'message',
            isNot(contains('secret interne')),
          ),
        ),
      );
    },
  );
}
