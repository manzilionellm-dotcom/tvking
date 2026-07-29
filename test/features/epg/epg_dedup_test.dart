// =========================================================
//  epg_dedup_test.dart — RÉGRESSION audit 2026-07-29
// =========================================================
//  Bug : l'import XMLTV ré-insérait toute la fenêtre future à CHAQUE
//  sync (aucune contrainte d'unicité, insert sans conflictAlgorithm,
//  purge limitée au passé) → la table epg_programs doublait à chaque
//  refresh et le guide affichait les émissions en double.
//
//  Vérifie sur SQLite FFI + faux client HTTP :
//    1. initialize() purge les doublons hérités puis pose l'index
//       UNIQUE (channel_id, start_time) ;
//    2. deux downloadAndImport successifs du même XMLTV laissent la
//       table au MÊME nombre de lignes (REPLACE, pas doublon).
// =========================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';

String _fmt(DateTime t) => '${t.year.toString().padLeft(4, '0')}'
    '${t.month.toString().padLeft(2, '0')}'
    '${t.day.toString().padLeft(2, '0')}'
    '${t.hour.toString().padLeft(2, '0')}'
    '${t.minute.toString().padLeft(2, '0')}00 +0000';

String _xmltv() {
  final DateTime base = DateTime.now().toUtc();
  final StringBuffer b = StringBuffer('<?xml version="1.0"?><tv>');
  b.write('<channel id="c1"><display-name>C1</display-name></channel>');
  for (int i = 0; i < 3; i++) {
    final DateTime start = base.add(Duration(hours: 1 + i));
    final DateTime stop = base.add(Duration(hours: 2 + i));
    b.write('<programme start="${_fmt(start)}" stop="${_fmt(stop)}" '
        'channel="c1"><title>Programme $i</title></programme>');
  }
  b.write('</tv>');
  return b.toString();
}

Future<int> _count(Database db, String channelId) async {
  final List<Map<String, Object?>> r = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM epg_programs WHERE channel_id = ?',
      <Object>[channelId]);
  return (r.first['n'] as int?) ?? -1;
}

void main() {
  sqfliteFfiInit();

  test(
      'initialize() dédoublonne les bases héritées et pose idx_epg_uniq ; '
      'deux imports successifs ne dupliquent plus les programmes', () async {
    final Database db =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await PlaylistDatabase.instance.debugCreate(db);
    PlaylistDatabase.instance.debugSetDatabase(db);

    // État HÉRITÉ : table déjà présente avec des doublons (créée par une
    // version antérieure, sans contrainte d'unicité).
    await db.execute('''
      CREATE TABLE epg_programs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        stop_time INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        category TEXT,
        icon_url TEXT
      )
    ''');
    final int t0 = DateTime.now()
        .add(const Duration(hours: 5))
        .millisecondsSinceEpoch;
    for (int i = 0; i < 2; i++) {
      await db.insert('epg_programs', <String, Object?>{
        'channel_id': 'legacy',
        'start_time': t0,
        'stop_time': t0 + 3600000,
        'title': 'Doublon hérité',
      });
    }

    await EpgRepository.instance.initialize();

    // 1. Doublons hérités purgés + index unique présent.
    final int legacyCount = await _count(db, 'legacy');
    expect(legacyCount, 1, reason: 'les doublons hérités doivent être purgés');
    final List<Map<String, Object?>> idx = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_epg_uniq'");
    expect(idx, isNotEmpty, reason: "l'index unique doit exister");

    // 2. Import du même XMLTV deux fois → pas de doublons.
    final MockClient fake = MockClient((http.Request req) async =>
        http.Response.bytes(utf8.encode(_xmltv()), 200));

    final int n1 = await EpgRepository.instance.downloadAndImport(
      url: 'http://panel.example/xmltv.php',
      knownChannelIds: <String>{'c1'},
      httpClient: fake,
    );
    expect(n1, 3);
    final int afterFirst = await _count(db, 'c1');
    expect(afterFirst, 3);

    await EpgRepository.instance.downloadAndImport(
      url: 'http://panel.example/xmltv.php',
      knownChannelIds: <String>{'c1'},
      httpClient: fake,
    );
    final int afterSecond = await _count(db, 'c1');
    expect(afterSecond, 3,
        reason: 're-sync = REPLACE, la table ne doit PAS doubler');

    await db.close();
  });
}
