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
  // v5 ajoute `http_headers` à la table channels (User-Agent/Referer par
  // chaîne, imposés par certains panels IPTV — sinon 403 à la lecture).
  // v6 ajoute `url_formats` à la table playlists (format d'URL gagnant
  // mémorisé PAR SOURCE par la cascade Xtream — zapping sans re-sonde).
  static const int _kDbVersion = 6;

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
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Active les clés étrangères SUR CHAQUE connexion. SQLite les
  /// désactive par défaut : sans ce PRAGMA, le `ON DELETE CASCADE` de la
  /// table `channels` ne se déclenche JAMAIS → en supprimant une liste,
  /// ses chaînes restaient orphelines en base et réapparaissaient à
  /// l'écran (bug « les listes effacées ne s'effacent pas »).
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Accès de TEST à la migration (bug terrain du 2026-07-08 : une base
  /// portant déjà une colonne re-migrée doit passer sans erreur).
  @visibleForTesting
  Future<void> debugUpgrade(Database db, int oldVersion, int newVersion) =>
      _onUpgrade(db, oldVersion, newVersion);

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
        is_active INTEGER NOT NULL DEFAULT 0,
        url_formats TEXT
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
        http_headers TEXT,
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

  /// `ALTER TABLE … ADD COLUMN` IDEMPOTENT : ne fait rien si la colonne
  /// existe déjà. Indispensable sur le terrain (bug 2026-07-08 : « ça
  /// n'accepte pas M3U depuis le premier jour ») : certaines
  /// installations ont une base où la colonne est DÉJÀ présente alors
  /// que le numéro de version est resté en arrière (APK réinstallés
  /// dans le désordre — même versionCode —, migration rejouée après une
  /// interruption…). Le « duplicate column name » faisait alors échouer
  /// TOUTE la migration, et avec elle l'ouverture de la base → plus
  /// aucun ajout de source possible sur l'appareil.
  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final List<Map<String, Object?>> cols =
        await db.rawQuery('PRAGMA table_info($table)');
    final bool exists = cols.any((Map<String, Object?> c) =>
        (c['name'] as String?)?.toLowerCase() == column.toLowerCase());
    if (exists) {
      if (kDebugMode) {
        debugPrint('[DB] $table.$column existe déjà — migration ignorée');
      }
      return;
    }
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (kDebugMode) {
      debugPrint('[DB] Migration $oldVersion → $newVersion');
    }
    if (oldVersion < 2) {
      // v2 : ajoute epg_url
      await _addColumnIfMissing(db, 'playlists', 'epg_url', 'TEXT');
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
      await _addColumnIfMissing(
          db, 'playlists', 'is_active', 'INTEGER NOT NULL DEFAULT 0');
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
    if (oldVersion < 5) {
      // v5 (2026-06-09) : en-têtes HTTP par chaîne (User-Agent / Referer /
      // Origin / Cookie). Certains panels IPTV exigent un UA/Referer précis
      // par chaîne ; sans lui le serveur répond 403 et « la chaîne ne marche
      // pas ». Le parser M3U les remplit désormais ; ils sont stockés ici en
      // JSON. Colonne ajoutée NULL → les chaînes déjà en base la rempliront
      // au prochain rafraîchissement de la playlist.
      await _addColumnIfMissing(db, 'channels', 'http_headers', 'TEXT');
    }
    if (oldVersion < 6) {
      // v6 (2026-07-08) : format d'URL GAGNANT mémorisé PAR SOURCE
      // (JSON {"live":"live:m3u8","movie":"none:"…}). Rempli par la
      // cascade de variantes Xtream quand une variante débloque un
      // flux : les chaînes suivantes de la même source utilisent
      // directement ce format (zapping instantané, pas de re-sonde).
      // Cf. XtreamUrlFormatStore. IDEMPOTENT : c'est cette migration
      // qui échouait en « duplicate column name: url_formats » sur les
      // appareils dont la base portait déjà la colonne (bug terrain du
      // 2026-07-08 — l'ajout de source était impossible).
      await _addColumnIfMissing(db, 'playlists', 'url_formats', 'TEXT');
    }
  }
}
