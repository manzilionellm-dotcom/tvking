// =========================================================
//  doh_https_test.dart — Le résolveur DoH ne doit pas tuer le HTTPS
// =========================================================
//  CAUSE RACINE terrain (boîte noire du 2026-08-03, 18:36). Toutes les
//  sources HTTPS de l'app échouaient, avec deux messages en alternance :
//      HttpException: Connection closed before full header was received
//      HttpException: Invalid request method
//  Ce sont les erreurs de l'analyseur HTTP de Dart quand la réponse
//  n'est pas du HTTP — une alerte TLS binaire, renvoyée parce que la
//  requête était partie EN CLAIR sur le port 443.
//
//  Explication, dans `http_impl.dart` du SDK Dart : dès qu'un
//  `connectionFactory` est posé, la branche `SecureSocket.startConnect`
//  n'est plus jamais prise, et le socket rendu par la fabrique est
//  utilisé TEL QUEL. Le nôtre était un socket nu. Poser le résolveur
//  DoH cassait donc TOUT le HTTPS des clients concernés — playlists,
//  sondes HLS, relais.
//
//  Personne ne l'avait vu en un an : les panels IPTV de nos clients
//  sont en `http://`, et un socket nu leur va très bien. Il a fallu une
//  démo servie par des CDN en HTTPS pour le révéler.
//
//  Ces tests montent un VRAI serveur HTTPS local et font une VRAIE
//  poignée de main. Un test qui se contenterait de vérifier la forme du
//  code n'aurait rien attrapé — le bug n'était visible que sur le fil.
// =========================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/net/doh_resolver.dart';

/// Serveur HTTPS local à certificat auto-signé — exactement ce que
/// servent beaucoup de panels IPTV, et ce que les lecteurs du marché
/// acceptent.
Future<HttpServer> _startTlsServer(String body) async {
  final SecurityContext ctx = SecurityContext()
    ..useCertificateChain('test/fixtures/tls/cert.pem')
    ..usePrivateKey('test/fixtures/tls/key.pem');
  final HttpServer server =
      await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
  server.listen((HttpRequest req) async {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.text
      ..write(body);
    await req.response.close();
  });
  return server;
}

void main() {
  test('un client avec DoH lit bien une source HTTPS', () async {
    final HttpServer server = await _startTlsServer('#EXTM3U\n#EXTINF:-1,A\n');
    addTearDown(() => server.close(force: true));

    final HttpClient client = HttpClient();
    installDohResolution(client, acceptInvalidCertificate: true);
    addTearDown(() => client.close(force: true));

    final HttpClientRequest req = await client
        .getUrl(Uri.parse('https://127.0.0.1:${server.port}/liste.m3u8'));
    final HttpClientResponse resp = await req.close();
    final String body = await resp.transform(utf8.decoder).join();

    expect(resp.statusCode, 200);
    expect(body, startsWith('#EXTM3U'),
        reason: 'avant le correctif : « Invalid request method » ou '
            '« Connection closed before full header was received » — la '
            'requête partait en clair sur le port TLS');
  });

  test('le HTTP en clair continue de passer, inchangé', () async {
    // Les panels de nos clients sont en http:// : c'est le chemin qui
    // marchait, et il ne doit surtout pas bouger.
    final HttpServer plain =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => plain.close(force: true));
    plain.listen((HttpRequest req) async {
      req.response.write('#EXTM3U');
      await req.response.close();
    });

    final HttpClient client = HttpClient();
    installDohResolution(client, acceptInvalidCertificate: true);
    addTearDown(() => client.close(force: true));

    final HttpClientResponse resp = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:${plain.port}/liste.m3u')))
        .close();
    expect(resp.statusCode, 200);
    expect(await resp.transform(utf8.decoder).join(), '#EXTM3U');
  });

  test('un certificat invalide est REFUSÉ quand on ne l\'autorise pas', () async {
    // Le drapeau doit vraiment commander quelque chose. S'il n'avait
    // aucun effet, on aurait rétabli un TLS permissif partout sans que
    // personne ne l'ait demandé.
    final HttpServer server = await _startTlsServer('secret');
    addTearDown(() => server.close(force: true));

    final HttpClient client = HttpClient();
    installDohResolution(client, acceptInvalidCertificate: false);
    addTearDown(() => client.close(force: true));

    await expectLater(
      client
          .getUrl(Uri.parse('https://127.0.0.1:${server.port}/x'))
          .then((HttpClientRequest r) => r.close()),
      throwsA(isA<HandshakeException>()),
    );
  });
}
