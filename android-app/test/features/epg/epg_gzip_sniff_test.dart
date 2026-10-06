// =========================================================
//  epg_gzip_sniff_test.dart — Guide : « FormatException: Filter error »
// =========================================================
//  Boîte noire de la SHIELD (06/10/2026) : le guide échoue avec
//  « FormatException: Filter error ». Cette erreur vient du décodeur gzip
//  de dart:io quand on lui donne des octets qui ne sont PAS du gzip.
//
//  Vrai serveur HTTP local, vrai client `http.Client()` (celui de la box),
//  vrai code `fetchXmltvRows`. Trois façons réelles de servir un guide :
//    1. fichier `.xml.gz` (octets gzip, sans Content-Encoding) ;
//    2. XML compressé par le serveur (`Content-Encoding: gzip`) : le client
//       HTTP de dart:io le DÉCOMPRESSE déjà ; l'ancien code redécompressait
//       → Filter error (reproduit ci-dessous avec le repli allumé) ;
//    3. adresse en `.gz` qui répond du XML en clair → même erreur avant.
//  Règle : on décide d'après les deux premiers octets (1f 8b), pas d'après
//  l'adresse ni les en-têtes. Repli `zuno.epg.gzip_by_header`.
// =========================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/epg/data/epg_fetch.dart';

String _stamp(DateTime t) {
  final DateTime u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
}

String _guide() {
  final DateTime now = DateTime.now();
  final StringBuffer b = StringBuffer('<?xml version="1.0"?><tv>');
  for (int i = 0; i < 4; i++) {
    final DateTime s = now.add(Duration(hours: i));
    b.write('<programme start="${_stamp(s)}" stop="${_stamp(s.add(const Duration(hours: 1)))}" '
        'channel="TF1.fr"><title>Programme $i</title></programme>');
  }
  b.write('</tv>');
  return b.toString();
}

// Pas de TestWidgetsFlutterBinding ici : il remplace HttpClient par un
// faux qui répond 400 à tout. Ce test veut le VRAI client de la box.
void main() {
  late HttpServer server;
  late String base;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    final List<int> xml = utf8.encode(_guide());
    server.listen((HttpRequest req) async {
      final HttpResponse r = req.response;
      switch (req.uri.path) {
        case '/fichier.xml.gz': // vrai fichier compressé, aucun en-tête
          r.headers.contentType = ContentType('application', 'octet-stream');
          r.add(gzip.encode(xml));
        case '/serveur.xml': // compression HTTP faite par le serveur
          r.headers.contentType = ContentType('application', 'xml');
          r.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
          r.add(gzip.encode(xml));
        case '/faux.xml.gz': // l'adresse dit .gz, le serveur répond en clair
          r.headers.contentType = ContentType('application', 'xml');
          r.add(xml);
        default:
          r.statusCode = 404;
      }
      await r.close();
    });
  });

  tearDownAll(() => server.close(force: true));
  tearDown(() => RepairFlags.epgGzipByHeader = false);

  Future<int> fetch(String path) async {
    final http.Client client = http.Client();
    try {
      return await fetchXmltvRows(
        url: '$base$path',
        client: client,
        onRows: (_) async {},
      );
    } finally {
      client.close();
    }
  }

  test('fichier .xml.gz sans en-tête : décompressé, 4 programmes', () async {
    expect(await fetch('/fichier.xml.gz'), 4);
  });

  test('Content-Encoding: gzip (déjà décompressé par le client) : 4 programmes', () async {
    expect(await fetch('/serveur.xml'), 4);
  });

  test('adresse .gz qui répond en clair : 4 programmes', () async {
    expect(await fetch('/faux.xml.gz'), 4);
  });

  test('contre-preuve : décision par en-tête (repli) → Filter error', () async {
    RepairFlags.epgGzipByHeader = true;
    await expectLater(fetch('/serveur.xml'), throwsA(isA<FormatException>()));
    await expectLater(fetch('/faux.xml.gz'), throwsA(isA<FormatException>()));
    expect(await fetch('/fichier.xml.gz'), 4, reason: 'le vrai fichier gzip marchait déjà');
  });

  group('sniffGzip (octets bruts)', () {
    test('signature coupée entre deux paquets', () async {
      final List<int> gz = gzip.encode(utf8.encode('<tv></tv>'));
      final Stream<List<int>> s = Stream<List<int>>.fromIterable(<List<int>>[
        gz.sublist(0, 1), gz.sublist(1),
      ]);
      expect(utf8.decode(await sniffGzip(s).expand((List<int> c) => c).toList()), '<tv></tv>');
    });

    test('flux vide ou d’un seul octet : rendu tel quel', () async {
      expect(await sniffGzip(const Stream<List<int>>.empty()).toList(), isEmpty);
      expect(await sniffGzip(Stream<List<int>>.value(<int>[0x3c])).expand((List<int> c) => c).toList(),
          <int>[0x3c]);
    });
  });
}
