// =========================================================
//  epg_replay_keep_test.dart — Guide : la journée passée des chaînes à
//  catch-up est gardée (pastilles REPLAY)
// =========================================================
//  Avant le 12/11/2026 : tout programme fini depuis plus d'1 h était écarté
//  à l'import, pour toutes les chaînes. Le guide d'une chaîne ne montrait
//  donc presque aucune émission à revoir, même quand le fournisseur garde
//  plusieurs jours d'archives.
//  Règle : les chaînes qui déclarent un catch-up gardent 24 h de passé ;
//  les autres gardent 1 h, comme avant (aucune rangée en plus pour elles).
//
//  Vrai serveur HTTP local et vrai `fetchXmltvRows`, comme
//  epg_gzip_sniff_test.dart. Identifiants fictifs.
// =========================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/features/epg/data/epg_fetch.dart';

String _stamp(DateTime t) {
  final DateTime u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
}

/// Pour chaque chaîne : un programme fini il y a 5 h, un fini il y a 30 h,
/// un en cours.
String _guide(List<String> channels) {
  final DateTime now = DateTime.now();
  final StringBuffer b = StringBuffer('<?xml version="1.0"?><tv>');
  void add(String channel, String title, Duration startAgo) {
    final DateTime s = now.subtract(startAgo);
    b.write('<programme start="${_stamp(s)}" '
        'stop="${_stamp(s.add(const Duration(hours: 1)))}" '
        'channel="$channel"><title>$title</title></programme>');
  }

  for (final String channel in channels) {
    add(channel, 'il y a 6 h', const Duration(hours: 6));
    add(channel, 'hier', const Duration(hours: 31));
    add(channel, 'en cours', const Duration(minutes: 20));
  }
  b.write('</tv>');
  return b.toString();
}

// Pas de TestWidgetsFlutterBinding : il remplace HttpClient par un faux.
void main() {
  late HttpServer server;
  late String url;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/guide.xml';
    final List<int> xml =
        utf8.encode(_guide(<String>['replay.fr', 'direct.fr']));
    server.listen((HttpRequest req) async {
      req.response.headers.contentType = ContentType('application', 'xml');
      req.response.add(xml);
      await req.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  Future<Map<String, List<String>>> titles({Set<String>? replayIds}) async {
    final Map<String, List<String>> byChannel = <String, List<String>>{};
    final http.Client client = http.Client();
    try {
      await fetchXmltvRows(
        url: url,
        client: client,
        knownIds: <String>{'replay.fr', 'direct.fr'},
        replayIds: replayIds,
        onRows: (List<Map<String, Object?>> rows) async {
          for (final Map<String, Object?> row in rows) {
            byChannel
                .putIfAbsent(row['channel_id']! as String, () => <String>[])
                .add(row['title']! as String);
          }
        },
      );
    } finally {
      client.close();
    }
    return byChannel;
  }

  test('sans chaîne à catch-up : 1 h de passé seulement, comme avant', () async {
    final Map<String, List<String>> got = await titles();
    expect(got['replay.fr'], <String>['en cours']);
    expect(got['direct.fr'], <String>['en cours']);
  });

  test('chaîne à catch-up : la journée passée est gardée, pas la veille', () async {
    final Map<String, List<String>> got =
        await titles(replayIds: <String>{'replay.fr'});
    expect(got['replay.fr'], <String>['il y a 6 h', 'en cours']);
    // La chaîne sans catch-up ne reçoit aucune rangée en plus.
    expect(got['direct.fr'], <String>['en cours']);
  });
}
