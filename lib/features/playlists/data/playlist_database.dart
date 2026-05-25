// =========================================================
//  playlist_database.dart — Accès SQLite pour les playlists
// =========================================================
//  Ouvre (ou crée) la base `tv_king.db` dans le dossier de
//  données de l'app, et y maintient 2 tables :
//
//    - playlists  : les sources ajoutées par l'utilisateur
//    - channels   : toutes les chaînes connues, liées à une
//                   playlist via playlist_id
//
//  La base est ouverte une seule fois (singleton) puis
//  réutilisée par tout le repository. Les futures évolutions
//  de schéma se feront via incrément de `_kDbVersion` et
//  migrations.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class PlaylistDatabase {
  PlaylistDatabase._();
  static final PlaylistDatabase instance = PlaylistDatabase._();

  static const String _kDbFileName = 'tv_king.db';
  static const int _kDbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final String dirPath = (await getApplicationDocumentsDirectory()).path;
    final String dbPath = p.join(dirPath, _kDbFileName);

    if (kDebugMode) {
      debugPrint('[DB] Ouverture de la base SQLite : $dbPath');
    }

    return openDatabase(
      dbPath,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        m3u_url TEXT,
        xtream_server TEXT,
        xtream_username TEXT,
        xtream_password TEXT,
        created_at INTEGER NOT NULL,
        last_synced_at INTEGER,
        channel_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE channels (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        external_id TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'Autres',
        stream_url TEXT NOT NULL,
        logo_url TEXT,
        is_live INTEGER NOT NULL DEFAULT 1,
        catchup_supported INTEGER NOT NULL DEFAULT 0,
        catchup_days INTEGER,
        catchup_source TEXT,
        FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_channels_playlist ON channels(playlist_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_channels_category ON channels(category)
    ''');

    if (kDebugMode) debugPrint('[DB] Schéma v$version créé.');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Place-holder pour les futures migrations.
    if (kDebugMode) {
      debugPrint('[DB] Migration $oldVersion → $newVersion (pas encore implémenté)');
    }
  }
}
