// =========================================================
//  replace_channels_transaction_test.dart — « tout ou rien » des listes
// =========================================================
//  Le rafraîchissement d'une liste efface puis réinsère ses chaînes dans
//  UNE transaction (PlaylistRepository._replaceChannelsOf). Ce test
//  vérifie le MÉCANISME exact employé (transaction + lots `txn.batch()`
//  + `commit`) sur la vraie base du projet : pas de blocage, et une
//  transaction qui échoue laisse l'ancienne liste intacte.
// =========================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';

Map<String, Object?> _row(int pl, int i) => <String, Object?>{
      'playlist_id': pl,
      'external_id': 'c$pl-$i',
      'name': 'Chaîne $i',
      'category': 'Test',
      'stream_url': 'http://flux.example.invalid/$i',
      'logo_url': null,
      'is_live': 1,
      'catchup_supported': 0,
      'catchup_days': 0,
      'catchup_source': null,
    };

Future<void> _replace(Database db, int pl, int n, {bool failAfter = false}) {
  return db.transaction((Transaction txn) async {
    await txn.delete('channels', where: 'playlist_id = ?', whereArgs: <Object>[pl]);
    const int chunk = 7;
    for (int i = 0; i < n; i += chunk) {
      final Batch b = txn.batch();
      for (int j = i; j < n && j < i + chunk; j++) {
        b.insert('channels', _row(pl, j));
      }
      await b.commit(noResult: true);
    }
    if (failAfter) throw StateError('processus tué au milieu');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('zuno-tx-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    // Clé étrangère : les chaînes appartiennent à une liste existante.
    final Database db = await PlaylistDatabase.instance.database;
    for (final int id in <int>[1, 2]) {
      await db.insert('playlists', <String, Object?>{
        'id': id,
        'name': 'Liste $id',
        'type': 'm3u',
        'created_at': 0,
      });
    }
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<int> count(Database db, int pl) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM channels WHERE playlist_id = ?', <Object>[pl]);
    return (rows.first['n'] as int?) ?? 0;
  }

  test('lots dans une transaction : pas de blocage, remplacement complet', () async {
    final Database db = await PlaylistDatabase.instance.database;
    await _replace(db, 1, 20);
    expect(await count(db, 1), 20);
    await _replace(db, 1, 33).timeout(const Duration(seconds: 10));
    expect(await count(db, 1), 33);
  });

  test('une transaction interrompue laisse l\'ancienne liste intacte', () async {
    final Database db = await PlaylistDatabase.instance.database;
    await _replace(db, 2, 10);
    expect(await count(db, 2), 10);
    await expectLater(_replace(db, 2, 25, failAfter: true), throwsStateError);
    expect(await count(db, 2), 10, reason: 'ni vide ni tronquée');
    // L'autre liste n'a pas bougé.
    expect(await count(db, 1), 33);
  });
}
