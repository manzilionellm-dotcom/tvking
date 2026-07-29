// =========================================================
//  epg_resync_ids_test.dart — RÉGRESSION audit 2026-07-29
// =========================================================
//  Bug : `resyncEpgAll()` lisait `columns: ['id']` alors que la table
//  `channels` n'a QUE `local_id`/`external_id`. La DatabaseException
//  était avalée par le catch global → la resynchronisation périodique
//  du guide (12 h, main_tv) n'a JAMAIS eu lieu ; le guide se vidait au
//  bout de ~48 h sur une box allumée en continu.
//
//  Ce test exécute la requête RÉELLE (epgChannelIdsForPlaylist) contre
//  le VRAI schéma (PlaylistDatabase.debugCreate) en SQLite FFI : si la
//  colonne redevient fausse, le test lève.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';

void main() {
  sqfliteFfiInit();

  test(
      'epgChannelIdsForPlaylist lit external_id sur le vrai schéma '
      '(régression : colonne id inexistante → resync EPG morte)', () async {
    final Database db =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await PlaylistDatabase.instance.debugCreate(db);

    await db.insert('playlists', <String, Object?>{
      'name': 'Test',
      'type': 'm3u',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    for (final String extId in <String>['xtream-1', 'xtream-2', 'tvg-fr-3']) {
      await db.insert('channels', <String, Object?>{
        'playlist_id': 1,
        'external_id': extId,
        'name': 'Chaîne $extId',
        'category': 'Test',
        'stream_url': 'http://example.com/$extId.ts',
        'is_live': 1,
      });
    }
    // Une chaîne d'une AUTRE playlist ne doit pas remonter.
    await db.insert('playlists', <String, Object?>{
      'name': 'Autre',
      'type': 'm3u',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('channels', <String, Object?>{
      'playlist_id': 2,
      'external_id': 'xtream-999',
      'name': 'Hors playlist',
      'category': 'Test',
      'stream_url': 'http://example.com/999.ts',
      'is_live': 1,
    });

    final Set<String> ids = await PlaylistRepository.instance
        .epgChannelIdsForPlaylist(1, db: db);

    expect(ids, <String>{'xtream-1', 'xtream-2', 'tvg-fr-3'});
    await db.close();
  });
}
