// =========================================================
//  relay_upstream_reconnect_test.dart — Relais DLNA live (2026-07-09)
// =========================================================
//  Les serveurs Xtream ferment périodiquement la socket HTTP d'un
//  live (comportement normal), et un creux WiFi côté téléphone casse
//  le GET upstream. Avant le fix, le relais pass-through
//  (`_proxyUpstream`) propageait l'EOF à la TV → STOPPED → tout le
//  failover SOAP à re-dérouler (gel visible plusieurs secondes).
//
//  Ce test monte un upstream factice qui COUPE la connexion après
//  chaque salve d'octets, et vérifie que le client (la « TV ») reçoit
//  les salves de PLUSIEURS connexions upstream successives sur UNE
//  SEULE réponse HTTP ininterrompue — la reconnexion est invisible.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/dlna_profiles.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';

void main() {
  // PAS de TestWidgetsFlutterBinding ici : il remplacerait HttpClient
  // par un mock qui répond 400 à tout — or ce test exerce de VRAIES
  // sockets loopback (même approche que hls_relay_session_test).

  test('relais live : reconnexion upstream sans couper la TV', () async {
    // Upstream factice : chaque connexion envoie 1000 octets marqués
    // du numéro de connexion, puis FERME (simule la coupure Xtream).
    int connections = 0;
    final HttpServer upstream =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((HttpRequest req) async {
      connections++;
      final int marker = connections;
      // Pas de Content-Length → chunked → le relais voit un flux LIVE
      // (longueur inconnue) et doit reconnecter au lieu de couper.
      req.response.headers.contentType = ContentType('video', 'mp2t');
      req.response.add(List<int>.filled(1000, marker));
      await req.response.flush();
      await req.response.close();
    });

    final LocalCastServer server = LocalCastServer.instance;
    const DlnaProfile profile = DlnaProfile(
      mime: 'video/mp2t',
      profileName: 'MPEG_TS_SD_NA_ISO',
      transferMode: DlnaTransferMode.streaming,
      objectClass: 'object.item.videoItem.videoBroadcast',
      fileExtension: 'ts',
    );
    final String? relayUrl = await server.registerRelay(
      upstreamUrl: 'http://127.0.0.1:${upstream.port}/live.ts',
      profile: profile,
      receiverHost: '127.0.0.1',
    );
    expect(relayUrl, isNotNull);

    // On interroge le serveur via loopback quel que soit l'IP LAN
    // annoncée (le conteneur de test n'a pas forcément la même
    // interface que receiverHost).
    final Uri lanUri = Uri.parse(relayUrl!);
    final Uri localUri = lanUri.replace(host: '127.0.0.1');

    final HttpClient tv = HttpClient();
    final HttpClientRequest get = await tv.getUrl(localUri);
    final HttpClientResponse resp = await get.close();
    expect(resp.statusCode, 200);

    // Lit jusqu'à voir des octets provenant d'au moins 2 connexions
    // upstream distinctes (marqueurs 1 et 2) sur la MÊME réponse.
    final Set<int> markersSeen = <int>{};
    final Completer<void> sawTwo = Completer<void>();
    final StreamSubscription<List<int>> sub = resp.listen((List<int> chunk) {
      markersSeen.addAll(chunk);
      if (markersSeen.contains(1) &&
          markersSeen.contains(2) &&
          !sawTwo.isCompleted) {
        sawTwo.complete();
      }
    }, onDone: () {
      if (!sawTwo.isCompleted) {
        sawTwo.completeError(
          StateError('Réponse fermée après 1 seule connexion upstream — '
              'la reconnexion transparente ne fonctionne pas '
              '(marqueurs vus: $markersSeen)'),
        );
      }
    });

    await sawTwo.future.timeout(const Duration(seconds: 15));
    expect(connections, greaterThanOrEqualTo(2));

    // La « TV » zappe : fermer le client doit arrêter la boucle relais.
    await sub.cancel();
    tv.close(force: true);
    server.clearRelay(relayUrl);
    await upstream.close(force: true);
    await server.stop();
  });

  test('VOD (Content-Length connu) : pas de reconnexion, EOF propagé',
      () async {
    final HttpServer upstream =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    int connections = 0;
    upstream.listen((HttpRequest req) async {
      connections++;
      final List<int> body = List<int>.filled(500, 7);
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.contentLength = body.length; // VOD : longueur CONNUE
      req.response.add(body);
      await req.response.close();
    });

    final LocalCastServer server = LocalCastServer.instance;
    const DlnaProfile profile = DlnaProfile(
      mime: 'video/mp4',
      profileName: null,
      transferMode: DlnaTransferMode.streaming,
      objectClass: 'object.item.videoItem',
      fileExtension: 'mp4',
    );
    final String? relayUrl = await server.registerRelay(
      upstreamUrl: 'http://127.0.0.1:${upstream.port}/film.mp4',
      profile: profile,
      receiverHost: '127.0.0.1',
    );
    expect(relayUrl, isNotNull);
    final Uri localUri = Uri.parse(relayUrl!).replace(host: '127.0.0.1');

    final HttpClient tv = HttpClient();
    final HttpClientRequest get = await tv.getUrl(localUri);
    final HttpClientResponse resp = await get.close();
    final List<int> received = <int>[];
    await for (final List<int> chunk in resp) {
      received.addAll(chunk);
    }
    // La réponse se TERMINE (pas de reconnexion infinie) avec
    // exactement le contenu d'UNE connexion upstream.
    expect(received.length, 500);
    expect(connections, 1);

    tv.close(force: true);
    server.clearRelay(relayUrl);
    await upstream.close(force: true);
    await server.stop();
  });
}
