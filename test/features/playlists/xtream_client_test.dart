// =========================================================
//  xtream_client_test.dart — Tolérance aux panels Xtream réels
// =========================================================
//  Le protocole Xtream n'est pas normalisé : chaque panel répond un peu
//  différemment. Ces tests couvrent les variantes qui faisaient refuser
//  des comptes VALIDES (« marche sur IBO mais pas chez nous ») :
//    - auth: true (booléen) / auth absent / auth: "1"
//    - lien complet get.php collé dans le champ serveur
//    - identifiants avec caractères spéciaux dans les URLs de flux
// =========================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

/// Client HTTP simulé : répond au player_api selon l'action demandée.
MockClient _mockServer({
  required Map<String, dynamic> userInfo,
  List<Uri>? seenUris,
}) {
  return MockClient((http.Request req) async {
    seenUris?.add(req.url);
    final String action = req.url.queryParameters['action'] ?? '';
    Object body;
    switch (action) {
      case 'get_live_categories':
        body = <Object>[
          <String, Object>{'category_id': '7', 'category_name': 'Sport'},
        ];
      case 'get_live_streams':
        body = <Object>[
          <String, Object>{
            'stream_id': 42,
            'name': 'Chaîne Test',
            'category_id': '7',
          },
        ];
      default:
        body = <String, Object?>{'user_info': userInfo};
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}

void main() {
  group('verifyCredentials — variantes auth des panels réels', () {
    test('accepte auth: true (booléen — forks XUI.one)', () async {
      final XtreamClient c = XtreamClient(
        serverUrl: 'http://s.com:8080',
        username: 'u',
        password: 'p',
        httpClient: _mockServer(
            userInfo: <String, Object>{'auth': true, 'status': 'Active'}),
      );
      await expectLater(c.verifyCredentials(), completes);
    });

    test('accepte auth absent mais user_info valide', () async {
      final XtreamClient c = XtreamClient(
        serverUrl: 'http://s.com:8080',
        username: 'u',
        password: 'p',
        httpClient: _mockServer(
            userInfo: <String, Object>{'status': 'Active', 'exp_date': '0'}),
      );
      await expectLater(c.verifyCredentials(), completes);
    });

    test('accepte un statut inconnu non bloquant (Enabled, Trial…)', () async {
      final XtreamClient c = XtreamClient(
        serverUrl: 'http://s.com:8080',
        username: 'u',
        password: 'p',
        httpClient: _mockServer(
            userInfo: <String, Object>{'auth': 1, 'status': 'Enabled'}),
      );
      await expectLater(c.verifyCredentials(), completes);
    });

    test('refuse auth: 0 / false (refus explicite)', () async {
      for (final Object auth in <Object>[0, '0', false, 'false']) {
        final XtreamClient c = XtreamClient(
          serverUrl: 'http://s.com:8080',
          username: 'u',
          password: 'p',
          httpClient: _mockServer(userInfo: <String, Object>{'auth': auth}),
        );
        await expectLater(
            c.verifyCredentials(), throwsA(isA<XtreamException>()));
      }
    });

    test('refuse un statut clairement bloquant (Banned, Expired…)', () async {
      for (final String st in <String>['Banned', 'Expired', 'Disabled']) {
        final XtreamClient c = XtreamClient(
          serverUrl: 'http://s.com:8080',
          username: 'u',
          password: 'p',
          httpClient: _mockServer(
              userInfo: <String, Object>{'auth': 1, 'status': st}),
        );
        await expectLater(
            c.verifyCredentials(), throwsA(isA<XtreamException>()));
      }
    });
  });

  group('serveur collé en lien complet', () {
    test('les appels API visent player_api.php, pas get.php', () async {
      final List<Uri> seen = <Uri>[];
      final XtreamClient c = XtreamClient(
        // Lien complet collé dans le champ serveur ALORS QUE user/pass
        // sont aussi remplis — le cas qui cassait _buildUri.
        serverUrl:
            'http://s.com:8080/get.php?username=x&password=y&type=m3u_plus',
        username: 'u',
        password: 'p',
        httpClient: _mockServer(
          userInfo: <String, Object>{'auth': 1, 'status': 'Active'},
          seenUris: seen,
        ),
      );
      await c.verifyCredentials();
      expect(seen, isNotEmpty);
      expect(seen.first.path, '/player_api.php');
      expect(seen.first.queryParameters['username'], 'u');
      expect(seen.first.queryParameters['password'], 'p');
      // Le get.php collé ne doit laisser AUCUNE trace dans l'URL d'appel.
      expect(seen.first.toString(), isNot(contains('get.php')));
      expect(seen.first.queryParameters['type'], isNull);
    });
  });

  group('identifiants à caractères spéciaux', () {
    test('les URLs de flux live sont %-encodées', () async {
      final XtreamClient c = XtreamClient(
        serverUrl: 'http://s.com:8080',
        username: 'user @1',
        password: 'p&ss/w#',
        httpClient: _mockServer(
            userInfo: <String, Object>{'auth': 1, 'status': 'Active'}),
      );
      final List<Channel> channels =
          await c.fetchLiveChannels(playlistId: 1);
      expect(channels, hasLength(1));
      expect(channels.first.streamUrl,
          'http://s.com:8080/user%20%401/p%26ss%2Fw%23/42.ts');
    });
  });

  group('allowed_output_formats (serveurs HLS-only → écran noir en .ts)', () {
    test('serveur sans « ts » → URLs live en /live/…/id.m3u8', () async {
      final XtreamClient c = XtreamClient(
        serverUrl: 'http://s.com:8080',
        username: 'u',
        password: 'p',
        httpClient: _mockServer(userInfo: <String, Object>{
          'auth': 1,
          'status': 'Active',
          'allowed_output_formats': <String>['m3u8'],
        }),
      );
      await c.verifyCredentials();
      final List<Channel> channels =
          await c.fetchLiveChannels(playlistId: 1);
      expect(channels.first.streamUrl,
          'http://s.com:8080/live/u/p/42.m3u8');
    });

    test('serveur autorisant ts → on garde le .ts (comportement actuel)',
        () async {
      final XtreamClient c = XtreamClient(
        serverUrl: 'http://s.com:8080',
        username: 'u',
        password: 'p',
        httpClient: _mockServer(userInfo: <String, Object>{
          'auth': 1,
          'status': 'Active',
          'allowed_output_formats': <String>['m3u8', 'ts', 'rtmp'],
        }),
      );
      await c.verifyCredentials();
      final List<Channel> channels =
          await c.fetchLiveChannels(playlistId: 1);
      expect(channels.first.streamUrl, 'http://s.com:8080/u/p/42.ts');
    });
  });
}
