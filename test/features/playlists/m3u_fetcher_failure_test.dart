// =========================================================
//  m3u_fetcher_failure_test.dart — Messages d'échec du fetcher
// =========================================================
//  Terrain 2026-07-08 (captures client, 19:40) :
//    1. get.php en HTTP 503 sur les 9 signatures → message générique
//       correct, mais l'utilisateur reste bloqué (le repli Xtream est
//       testé côté repository/UI : addM3uPlaylistSmart) ;
//    2. « Failed host lookup » sur un domaine qui RÉSOUT parfaitement
//       depuis l'extérieur → le message générique « vérifie l'URL »
//       envoyait sur une fausse piste : c'est le DNS du réseau qui
//       bloque (blocage opérateur, courant sur l'IPTV). Le message doit
//       le dire et proposer la parade (Wi-Fi / DNS privé / VPN).
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/playlists/data/m3u_fetcher.dart';

void main() {
  const String url = 'http://thekung.example.com/get.php?username=U&password=P';

  test('échec DNS (host lookup) → message DNS explicite : réseau/opérateur, '
      'pas « mauvaise URL »', () {
    final String msg = M3uFetcher.friendlyFailure(
      Exception('ClientException with SocketException: Failed host lookup: '
          "'thekung.example.com' (OS Error: No address associated with "
          'hostname, errno = 7)'),
      url,
      9,
    );
    expect(msg, contains('DNS'));
    expect(msg, contains('opérateur'));
    expect(msg, contains('VPN'));
    expect(msg, isNot(contains('signatures de lecteur')),
        reason: 'un échec DNS n\'est pas un refus de signature');
  });

  test('refus serveur (HTTP 503) → message « signatures » générique, avec '
      'la dernière réponse', () {
    final String msg =
        M3uFetcher.friendlyFailure(Exception('HTTP 503 sur $url'), url, 9);
    expect(msg, contains('9 signatures'));
    expect(msg, contains('HTTP 503'));
  });

  test('fetch RÉEL sur un panel qui répond 503 partout → exception avec le '
      'statut (le déclencheur du repli Xtream)', () async {
    final HttpServer panel =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    panel.listen((HttpRequest req) async {
      req.response.statusCode = 503;
      await req.response.close();
    });
    try {
      await expectLater(
        M3uFetcher.fetch(
            'http://127.0.0.1:${panel.port}/get.php?username=U&password=P'),
        throwsA(predicate((Object? e) => '$e'.contains('HTTP 503'))),
      );
    } finally {
      await panel.close(force: true);
    }
  });
}
