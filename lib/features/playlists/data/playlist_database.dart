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
  // v2 ajoute la colonne `epg_url` à la table playlists.
  static const int _kDbVersion = 4;

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
        epg_url TEXT,
        created_at INTEGER NOT NULL,
        last_synced_at INTEGER,
        channel_count INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_playlists_active ON playlists(is_active)',
    );

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

    // v3 : sessions de visionnage pour le Hook Model (Continue Watching,
    // affinity scoring, time-of-day adaptation).
    await db.execute('''
      CREATE TABLE watch_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        channel_name TEXT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        duration_ms INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_ws_started ON watch_sessions(started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_ws_channel ON watch_sessions(channel_id)',
    );

    if (kDebugMode) debugPrint('[DB] Schéma v$version créé.');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (kDebugMode) {
      debugPrint('[DB] Migration $oldVersion → $newVersion');
    }
    if (oldVersion < 2) {
      // v2 : ajoute epg_url
      await db.execute('ALTER TABLE playlists ADD COLUMN epg_url TEXT');
    }
    if (oldVersion < 3) {
      // v3 : ajoute la table watch_sessions pour le tracking précis
      // du temps de visionnage par chaîne. Chaque entrée = une session
      // de lecture (open → close du player). Permet :
      //   - "Reprendre où tu t'es arrêté" précis à la seconde
      //   - Affinity scoring par genre (somme des durées par chaîne)
      //   - Adaptation horaire (heure de visionnage habituelle)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS watch_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          channel_id TEXT NOT NULL,
          channel_name TEXT,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          duration_ms INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ws_started ON watch_sessions(started_at DESC)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ws_channel ON watch_sessions(channel_id)',
      );
    }
    if (oldVersion < 4) {
      // v4 (Phase 1+/2026-06-01) : multi-serveurs avec is_active.
      // L'utilisateur peut ajouter N playlists et basculer entre
      // elles. La colonne is_active distingue celle qui sert de
      // source de chaines pour l'app a un instant donne.
      //
      // Migration : si une playlist existe deja (cas user single
      // serveur jusqu'a aujourd'hui), on la marque automatiquement
      // active pour ne pas casser son experience.
      await db.execute(
        'ALTER TABLE playlists ADD COLUMN is_active INTEGER NOT NULL DEFAULT 0',
      );
      // Marque la PREMIERE playlist (par created_at ASC = la plus
      // ancienne, probablement celle que l'user utilise actuellement)
      // comme active. SQLite n'a pas de UPDATE LIMIT 1 -> on passe par
      // un sous-select sur l'id.
      await db.execute('''
        UPDATE playlists SET is_active = 1
        WHERE id = (SELECT id FROM playlists ORDER BY created_at ASC LIMIT 1)
      ''');
      // Index partiel pour O(1) sur la lookup "active playlist".
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_playlists_active ON playlists(is_active)',
      );
    }
  }
}
