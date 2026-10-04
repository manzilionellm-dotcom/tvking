// =========================================================
//  epg_isolate_import_test.dart — import du guide hors du fil UI
// =========================================================
//  Un vrai serveur HTTP local sert un XMLTV ; l'import passe par le
//  chemin ISOLATE (aucun client injecté) et par l'appariement Xtream
//  (epg_channel_id → chaînes de l'app). Base SQLite réelle (ffi).
//    1. Xtream : un programme XMLTV donne une rangée par chaîne appariée,
//       les identifiants non appariés sont ignorés.
//    2. Un serveur qui répond 500 lève et rend le verrou.
//    3. Un ré-import en isolate ne double pas le guide.
// =========================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/epg/data/epg_targets.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';

String _stamp(DateTime t) {
  final DateTime u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
}

String _guide(DateTime now) {
  final StringBuffer b = StringBuffer('<?xml version="1.0"?><tv>');
  for (final String ch in <String>['TF1.fr', 'France2.fr', 'Inconnue.fr']) {
    for (int i = 0; i < 3; i++) {
      final DateTime s = now.add(Duration(hours: i + 1));
      final DateTime e = s.add(const Duration(hours: 1));
      b.write('<programme start="${_stamp(s)}" stop="${_stamp(e)}" channel="$ch">'
          '<title>$ch n°$i</title></programme>');
    }
  }
  b.write('</tv>');
  return b.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late HttpServer server;
  String body = '';
  int status = 200;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    RepairFlags.debugReset();
    dir = await Directory.systemTemp.createTemp('zuno-epg-iso-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) async {
      req.response.statusCode = status;
      req.response.headers.contentType = ContentType('application', 'xml');
      req.response.add(utf8.encode(status == 200 ? body : 'erreur'));
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<List<Map<String, Object?>>> rows() async {
    final Database db = await PlaylistDatabase.instance.database;
    return db.query('epg_programs', orderBy: 'channel_id, start_time');
  }

  String url() => 'http://127.0.0.1:${server.port}/xmltv.php?username=u&password=p';

  test('Xtream : le XMLTV du serveur est apparié aux chaînes xtream-<id>, en isolate',
      () async {
    final EpgRepository repo = EpgRepository.instance;
    await repo.clearAll();
    body = _guide(DateTime.now());
    status = 200;
    final Map<String, List<String>> map = buildEpgIdMap(<String, String>{
      'xtream-1': 'TF1.fr',
      'xtream-2': 'tf1.fr', // TF1 FHD : même guide
      'xtream-3': 'France2.fr',
    });
    final int n = await repo.downloadAndImport(url: url(), channelIdMap: map);
    // 3 programmes TF1 × 2 chaînes + 3 programmes France 2 ; « Inconnue » ignorée.
    expect(n, 9);
    final List<Map<String, Object?>> all = await rows();
    expect(all.length, 9);
    expect(all.where((Map<String, Object?> r) => r['channel_id'] == 'xtream-2').length, 3);
    expect(all.any((Map<String, Object?> r) => r['channel_id'] == 'Inconnue.fr'), isFalse);
    expect(repo.isSyncing, isFalse);
  });

  test('serveur en erreur : exception, verrou rendu', () async {
    final EpgRepository repo = EpgRepository.instance;
    status = 500;
    await expectLater(
      repo.downloadAndImport(url: url(), channelIdMap: <String, List<String>>{
        'tf1.fr': <String>['xtream-1'],
      }),
      throwsA(isA<Exception>()),
    );
    expect(repo.isSyncing, isFalse);
    status = 200;
  });

  test('ré-import en isolate : pas de doublon', () async {
    final EpgRepository repo = EpgRepository.instance;
    body = _guide(DateTime.now());
    final Map<String, List<String>> map = buildEpgIdMap(<String, String>{
      'xtream-1': 'TF1.fr',
      'xtream-3': 'France2.fr',
    });
    expect(await repo.downloadAndImport(url: url(), channelIdMap: map), 6);
    expect(await repo.downloadAndImport(url: url(), channelIdMap: map), 6);
    final List<Map<String, Object?>> all = await rows();
    // xtream-2 (de la 1re passe) garde son guide ; 1 et 3 remplacés, pas doublés.
    expect(all.where((Map<String, Object?> r) => r['channel_id'] == 'xtream-1').length, 3);
    expect(all.where((Map<String, Object?> r) => r['channel_id'] == 'xtream-3').length, 3);
    expect(all.where((Map<String, Object?> r) => r['channel_id'] == 'xtream-2').length, 3);
  });
}
