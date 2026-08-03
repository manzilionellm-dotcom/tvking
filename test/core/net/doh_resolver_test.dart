// =========================================================
//  doh_resolver_test.dart — Résolution DNS-over-HTTPS
// =========================================================
//  Terrain 2026-07-08 : domaines wildcard de panel (*.801802.com)
//  bloqués par le DNS opérateur. Le résolveur DoH doit :
//    - parser une réponse Cloudflare/Google (enregistrements A) ;
//    - mettre en cache (pas de 2e requête tant que c'est frais) ;
//    - basculer sur le fournisseur suivant si le premier échoue ;
//    - renvoyer vide si aucun ne répond ;
//  et, bout en bout, un client HTTP muni de DoH doit joindre un serveur
//  via un HÔTE INEXISTANT côté DNS système (résolu par le DoH stubbé
//  vers 127.0.0.1) — exactement le cas du domaine bloqué.
// =========================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/net/doh_resolver.dart';

String _dohJson(List<String> ips, {int ttl = 300}) => jsonEncode(
      <String, Object?>{
        'Status': 0,
        'Answer': <Map<String, Object?>>[
          for (final String ip in ips)
            <String, Object?>{'name': 'x', 'type': 1, 'TTL': ttl, 'data': ip},
        ],
      },
    );

void main() {
  final DohResolver r = DohResolver.instance;

  setUp(() {
    r
      ..clearCache()
      ..httpGetOverride = null;
  });
  tearDown(() => r.httpGetOverride = null);

  test('parse une réponse DoH (enregistrements A) → adresses', () async {
    r.httpGetOverride =
        (String ip, String host, String name) async => _dohJson(
              <String>['104.21.43.5', '172.67.215.12'],
            );
    final List<InternetAddress> addrs = await r.resolve('thekung.801802.com');
    expect(addrs.map((InternetAddress a) => a.address),
        containsAll(<String>['104.21.43.5', '172.67.215.12']));
  });

  test('cache : une 2e résolution ne relance PAS de requête', () async {
    int calls = 0;
    r.httpGetOverride = (String ip, String host, String name) async {
      calls++;
      return _dohJson(<String>['1.2.3.4']);
    };
    await r.resolve('panel.example.com');
    await r.resolve('panel.example.com');
    expect(calls, 1, reason: 'la 2e doit venir du cache');
  });

  test('bascule sur le 2e fournisseur si le 1er échoue', () async {
    final List<String> providersTried = <String>[];
    r.httpGetOverride = (String ip, String host, String name) async {
      providersTried.add(ip);
      if (ip == '1.1.1.1') throw const SocketException('bloqué');
      return _dohJson(<String>['9.9.9.9']);
    };
    final List<InternetAddress> addrs = await r.resolve('panel.example.com');
    expect(addrs.single.address, '9.9.9.9');
    expect(providersTried, <String>['1.1.1.1', '8.8.8.8'],
        reason: 'Cloudflare puis Google');
  });

  test('aucun fournisseur ne répond → liste vide (pas d\'exception)',
      () async {
    r.httpGetOverride =
        (String ip, String host, String name) async => throw 'KO';
    expect(await r.resolve('panel.example.com'), isEmpty);
  });

  test('cache NÉGATIF : un hôte irrésolu n\'est re-sondé qu\'une fois',
      () async {
    int calls = 0;
    r.httpGetOverride = (String ip, String host, String name) async {
      calls++;
      throw const SocketException('bloqué partout');
    };
    expect(await r.resolve('mort.example.com'), isEmpty);
    final int afterFirst = calls; // 2 fournisseurs tentés
    // 2e appel immédiat : doit venir du cache négatif (aucun nouvel essai).
    expect(await r.resolve('mort.example.com'), isEmpty);
    expect(calls, afterFirst, reason: 'le cache négatif évite la re-cascade');
  });

  test('repli AAAA quand le fournisseur répond sans A (IPv6-only)', () async {
    final List<String> typesSeen = <String>[];
    r.httpGetOverride = (String ip, String host, String name) async {
      // Le stub ignore le type (signature 3-arg) : on simule un domaine qui
      // n'a PAS d'A en renvoyant vide au 1er appel, puis un AAAA au 2e.
      typesSeen.add(ip);
      if (typesSeen.length == 1) {
        return jsonEncode(<String, Object?>{'Status': 0, 'Answer': <Object>[]});
      }
      return jsonEncode(<String, Object?>{
        'Status': 0,
        'Answer': <Map<String, Object?>>[
          <String, Object?>{
            'name': 'x',
            'type': 28, // AAAA
            'TTL': 300,
            'data': '2606:4700::6812:2b05',
          },
        ],
      });
    };
    final List<InternetAddress> addrs = await r.resolve('v6only.example.com');
    expect(addrs.single.type, InternetAddressType.IPv6);
  });

  test('plafond du cache : ne dépasse jamais la borne (anti-OOM)', () async {
    r.httpGetOverride =
        (String ip, String host, String name) async => _dohJson(<String>['1.2.3.4']);
    // Résout bien plus d'hôtes distincts que la borne interne (256) : sans
    // éviction, la map exploserait. On vérifie qu'une résolution ancienne a
    // été évincée (nouvelle requête réseau) tout en gardant les récentes.
    int calls = 0;
    r.httpGetOverride = (String ip, String host, String name) async {
      calls++;
      return _dohJson(<String>['1.2.3.4']);
    };
    for (int i = 0; i < 400; i++) {
      await r.resolve('host$i.example.com');
    }
    final int callsAfterFill = calls;
    // Le tout 1er hôte a dû être évincé → une nouvelle résolution le re-sonde.
    await r.resolve('host0.example.com');
    expect(calls, callsAfterFill + 1,
        reason: 'host0 évincé par le plafond → re-résolu');
    // Un hôte récent reste en cache (aucune nouvelle requête).
    await r.resolve('host399.example.com');
    expect(calls, callsAfterFill + 1, reason: 'host399 encore en cache');
  });

  group('resolveHostForMedia (lecture directe mpv — contournement DNS)', () {
    test('IP littérale → renvoyée telle quelle, aucune requête réseau',
        () async {
      // Aucun stub DoH : si la fonction tentait de résoudre, elle
      // échouerait. Une IP littérale doit court-circuiter toute résolution.
      r.httpGetOverride =
          (String ip, String host, String name) async => throw 'ne doit pas être appelé';
      final InternetAddress? out = await resolveHostForMedia('203.0.113.7');
      expect(out, isNotNull);
      expect(out!.address, '203.0.113.7');
    });

    test('hôte bloqué côté système → repli DoH (IP renvoyée)', () async {
      // `.invalid` (RFC 2606) : jamais résolvable en système → force le DoH.
      r.httpGetOverride = (String ip, String host, String name) async {
        expect(name, 'panel-bloque.invalid');
        return _dohJson(<String>['198.51.100.42']);
      };
      final InternetAddress? out =
          await resolveHostForMedia('panel-bloque.invalid');
      expect(out, isNotNull);
      expect(out!.address, '198.51.100.42');
    });

    test('hôte irrésolu (ni système ni DoH) → null', () async {
      r.httpGetOverride =
          (String ip, String host, String name) async => throw 'KO';
      expect(await resolveHostForMedia('panel-bloque.invalid'), isNull);
    });
  });

  test(
      'BOUT EN BOUT : client DoH joint un serveur via un hôte que le DNS '
      'système ne connaît pas (résolu vers 127.0.0.1 par le DoH stubbé)',
      () async {
    final HttpServer srv =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((HttpRequest req) async {
      req.response.statusCode = 200;
      req.response.write('OK ${req.headers.host}');
      await req.response.close();
    });

    // Le DoH renvoie 127.0.0.1 pour un domaine qui n'existe PAS côté
    // système. On utilise le TLD `.invalid` (RFC 2606 : garanti JAMAIS
    // résolvable) pour être sûr que la résolution système échoue et que
    // le DoH prenne le relais — le cas exact du domaine bloqué.
    const String blocked = 'panel-bloque.invalid';
    r.httpGetOverride = (String ip, String host, String name) async {
      expect(name, blocked);
      return _dohJson(<String>['127.0.0.1']);
    };

    final HttpClient client = HttpClient();
    installDohResolution(client, acceptInvalidCertificate: true);
    // Hôte impossible à résoudre en système → forcément passé par le DoH.
    final HttpClientRequest req = await client
        .getUrl(Uri.parse('http://$blocked:${srv.port}/get.php'));
    final HttpClientResponse resp = await req.close();
    final String body = await resp.transform(utf8.decoder).join();
    expect(resp.statusCode, 200);
    // Le serveur a bien reçu l'en-tête Host D'ORIGINE (pas l'IP) — c'est
    // ce qui fait router Cloudflare vers le bon sous-domaine wildcard.
    expect(body, contains(blocked));

    client.close(force: true);
    await srv.close(force: true);
  });

  group('preferIpv4', () {
    test('choisit l’IPv4 même si l’IPv6 est en tête (box IPv6 cassée)', () {
      final List<InternetAddress> addrs = <InternetAddress>[
        InternetAddress('2606:4700::6812:1b39', type: InternetAddressType.IPv6),
        InternetAddress('104.18.27.57', type: InternetAddressType.IPv4),
      ];
      expect(preferIpv4(addrs).type, InternetAddressType.IPv4);
      expect(preferIpv4(addrs).address, '104.18.27.57');
    });

    test('retombe sur la 1re adresse si aucune IPv4 (source IPv6-only)', () {
      final List<InternetAddress> addrs = <InternetAddress>[
        InternetAddress('2606:4700::6812:1b39', type: InternetAddressType.IPv6),
      ];
      expect(preferIpv4(addrs).type, InternetAddressType.IPv6);
    });
  });
}
