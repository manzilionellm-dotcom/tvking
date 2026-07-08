// =========================================================
//  playlist_database_migration_test.dart — Migrations IDEMPOTENTES
// =========================================================
//  Bug terrain (2026-07-08, capture client) : « DatabaseException
//  (duplicate column name: url_formats …) ALTER TABLE playlists ADD
//  COLUMN url_formats TEXT » à CHAQUE ajout de source — l'appareil
//  n'acceptait aucun M3U/Xtream « depuis le premier jour ».
//
//  Cause : sur ce téléphone, la table `playlists` portait DÉJÀ la
//  colonne `url_formats` alors que le numéro de version de la base
//  était resté en arrière (APK réinstallés dans le désordre — même
//  versionCode —, migration interrompue…). Les ALTER TABLE de
//  `_onUpgrade` n'étaient pas idempotents : la migration explosait,
//  l'ouverture de la base échouait, plus AUCUNE source ne pouvait être
//  ajoutée.
//
//  Ces tests rejouent exactement cet état de base (vraie SQLite FFI)
//  et vérifient que la migration passe désormais sans erreur, colonnes
//  déjà présentes ou non.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';

void main() {
  sqfliteFfiInit();

  Future<Database> emptyDb() =>
      databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

  /// Schéma v1 minimal (tel que créé par les toutes premières versions).
  Future<void> createV1Schema(Database db) async {
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE channels (
        id TEXT PRIMARY KEY,
        playlist_id INTEGER,
        name TEXT
      )
    ''');
  }

  test(
      'LA base du terrain : colonne url_formats DÉJÀ présente + version '
      'en retard → la migration passe (plus de « duplicate column »)',
      () async {
    final Database db = await emptyDb();
    await createV1Schema(db);
    // L'état exact du téléphone client : les colonnes des migrations
    // suivantes existent DÉJÀ (posées par une installation précédente)
    // alors que la version enregistrée impose de rejouer TOUTES les
    // migrations.
    await db.execute('ALTER TABLE playlists ADD COLUMN epg_url TEXT');
    await db.execute(
        'ALTER TABLE playlists ADD COLUMN is_active INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE channels ADD COLUMN http_headers TEXT');
    await db.execute('ALTER TABLE playlists ADD COLUMN url_formats TEXT');

    // Avant le correctif : DatabaseException « duplicate column name ».
    await PlaylistDatabase.instance.debugUpgrade(db, 1, 6);

    // La base reste pleinement utilisable après la migration.
    await db.insert('playlists', <String, Object?>{
      'name': 'M3U du revendeur',
      'created_at': 1,
      'url_formats': '{"live":"live:m3u8"}',
    });
    final List<Map<String, Object?>> rows =
        await db.query('playlists', where: 'is_active = 0');
    expect(rows, hasLength(1));
    await db.close();
  });

  test('base v1 SAINE (aucune colonne en avance) → migration complète, '
      'toutes les colonnes ajoutées', () async {
    final Database db = await emptyDb();
    await createV1Schema(db);

    await PlaylistDatabase.instance.debugUpgrade(db, 1, 6);

    final List<Map<String, Object?>> playlistCols =
        await db.rawQuery('PRAGMA table_info(playlists)');
    final Set<String> names = playlistCols
        .map((Map<String, Object?> c) => c['name']! as String)
        .toSet();
    expect(names, containsAll(<String>['epg_url', 'is_active', 'url_formats']));
    final List<Map<String, Object?>> channelCols =
        await db.rawQuery('PRAGMA table_info(channels)');
    expect(
      channelCols.map((Map<String, Object?> c) => c['name']),
      contains('http_headers'),
    );
    await db.close();
  });

  test('migration rejouée DEUX fois de suite → toujours idempotente',
      () async {
    final Database db = await emptyDb();
    await createV1Schema(db);
    await PlaylistDatabase.instance.debugUpgrade(db, 1, 6);
    // Rejouer (crash entre l'ALTER et l'écriture du numéro de version).
    await PlaylistDatabase.instance.debugUpgrade(db, 1, 6);
    final List<Map<String, Object?>> cols =
        await db.rawQuery('PRAGMA table_info(playlists)');
    expect(
      cols.where((Map<String, Object?> c) => c['name'] == 'url_formats'),
      hasLength(1),
    );
    await db.close();
  });
}
