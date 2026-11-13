// =========================================================
//  schema_repair_test.dart — Base locale à jour « sur le papier »
//  mais sans ses colonnes
// =========================================================
//  Cas réel (PC Windows, 13/11/2026) : le fichier portait la version 7,
//  mais `playlists` n'avait pas la colonne `hidden`. Aucune migration ne
//  tournait, et tout ajout de liste échouait (« no such column: hidden »).
//  Règle : à l'ouverture, on regarde les colonnes réelles et on ajoute
//  celles qui manquent, sans rien effacer.
//
//  Vrai SQLite, fichier temporaire. Aucune adresse réelle.
// =========================================================
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';

Future<Set<String>> _columns(Database db, String table) async => <String>{
      for (final Map<String, Object?> row
          in await db.rawQuery('PRAGMA table_info($table)'))
        row['name']! as String,
    };

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('zuno-schema-');
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/lists.db';
  });

  tearDown(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    dir.deleteSync(recursive: true);
  });

  test('version récente mais colonnes absentes : elles sont ajoutées, '
      'les données restent', () async {
    // On fabrique le fichier fautif : version 7, vieux schéma.
    final Database old = await databaseFactory.openDatabase(
      '${dir.path}/lists.db',
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (Database db, int v) async {
          await db.execute('''
            CREATE TABLE playlists (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              m3u_url TEXT,
              xtream_server TEXT,
              xtream_username TEXT,
              xtream_password TEXT,
              created_at INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE channels (
              local_id INTEGER PRIMARY KEY AUTOINCREMENT,
              playlist_id INTEGER NOT NULL,
              external_id TEXT NOT NULL,
              name TEXT NOT NULL,
              category TEXT NOT NULL DEFAULT 'Autres',
              stream_url TEXT NOT NULL
            )''');
          await db.insert('playlists', <String, Object?>{
            'name': 'Ma liste',
            'type': 'm3u',
            'm3u_url': 'http://example.invalid/liste.m3u',
            'created_at': 1,
          });
          await db.insert('channels', <String, Object?>{
            'playlist_id': 1,
            'external_id': 'c1',
            'name': 'Chaîne 1',
            'stream_url': 'http://example.invalid/c1',
          });
        },
      ),
    );
    await old.close();

    final Database db = await PlaylistDatabase.instance.database;
    expect(
      await _columns(db, 'playlists'),
      containsAll(<String>[
        'hidden',
        'is_active',
        'epg_url',
        'last_synced_at',
        'channel_count',
      ]),
    );
    expect(
      await _columns(db, 'channels'),
      containsAll(<String>[
        'http_headers',
        'catchup_supported',
        'catchup_days',
        'catchup_source',
        'logo_url',
        'is_live',
      ]),
    );
    // La requête qui plantait sur ce PC passe, et rien n'a disparu.
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT * FROM channels WHERE local_id > ? AND playlist_id NOT IN '
      '(SELECT id FROM playlists WHERE hidden = 1) ORDER BY local_id ASC',
      <Object>[0],
    );
    expect(rows.single['name'], 'Chaîne 1');
    expect(rows.single['is_live'], 1);
    final List<Map<String, Object?>> lists = await db.query('playlists');
    expect(lists.single['name'], 'Ma liste');
    expect(lists.single['hidden'], 0);
    // Tables de service créées si elles manquaient.
    await db.query('deleted_sources');
    await db.query('watch_sessions');
    // Une deuxième passe ne fait plus rien.
    expect(await PlaylistDatabase.repairSchema(db), 0);
  });

  test('base neuve : rien à réparer', () async {
    final Database db = await PlaylistDatabase.instance.database;
    expect(await PlaylistDatabase.repairSchema(db), 0);
    expect(await _columns(db, 'playlists'), contains('hidden'));
  });
}
