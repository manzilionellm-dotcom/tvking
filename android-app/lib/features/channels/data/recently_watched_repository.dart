// =========================================================
//  recently_watched_repository.dart — Historique des visionnages
// =========================================================
//  Sert à la section « récemment regardées » / « continuer ».
//
//  Chaque profil a SON historique (50 chaînes max). L'ancienne
//  table `recently_watched` est copiée UNE FOIS dans le tiroir
//  du profil 1, puis laissée telle quelle (rien n'est effacé).
//
//  Mode incognito (flavor adulte « Privé ») : on n'enregistre
//  AUCUN historique, quel que soit le profil.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/flavor/flavor.dart';
import '../../profiles/data/active_profile.dart';
import '../../profiles/domain/family_profile.dart';
import '../../profiles/domain/profile_migration.dart';
import '../../playlists/data/playlist_database.dart';

class RecentlyWatchedRepository {
  RecentlyWatchedRepository._();
  static final RecentlyWatchedRepository instance = RecentlyWatchedRepository._();

  static const int _kMaxEntries = 50;
  static const String _kScoped = 'recently_watched_by_profile';

  final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();

  /// Stream émettant la liste des IDs de chaînes DU PROFIL EN COURS,
  /// du plus récemment visionné au plus ancien.
  Stream<List<String>> get stream => _controller.stream;

  List<String> _cache = <String>[];
  bool _initialized = false;
  bool _listening = false;

  List<String> get current => List<String>.unmodifiable(_cache);

  Future<void> initialize() async {
    if (_initialized) return;
    final Database db = await PlaylistDatabase.instance.database;
    await _ensureSchema(db);
    await _migrateLegacyOnce(db);
    _initialized = true;
    _listenProfile();
    await _reload();
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recently_watched (
        channel_id TEXT PRIMARY KEY,
        last_watched_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_kScoped (
        profile_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        last_watched_at INTEGER NOT NULL,
        PRIMARY KEY (profile_id, channel_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recent_profile_ts
      ON $_kScoped(profile_id, last_watched_at DESC)
    ''');
  }

  /// Copie l'historique d'avant les profils dans le tiroir du
  /// profil 1. `INSERT OR IGNORE` ne remplace pas une ligne
  /// déjà présente (même règle que [ProfileMigration.mergeHistory]).
  Future<void> _migrateLegacyOnce(Database db) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool done = prefs.getBool(ProfileKeys.historyMigrated) ?? false;
      if (!ProfileMigration.shouldCopyLegacy(alreadyMigrated: done)) return;
      await db.execute('''
        INSERT OR IGNORE INTO $_kScoped (profile_id, channel_id, last_watched_at)
        SELECT '${ProfileIds.origin}', channel_id, last_watched_at
        FROM recently_watched
      ''');
      await prefs.setBool(ProfileKeys.historyMigrated, true);
    } catch (e) {
      if (kDebugMode) debugPrint('[Historique] migration profil : $e');
    }
  }

  void _listenProfile() {
    if (_listening) return;
    _listening = true;
    ActiveProfile.instance.listenable.addListener(_onProfile);
  }

  void _onProfile() {
    if (_initialized) unawaited(_reload());
  }

  Future<void> _reload() async {
    final Database db = await PlaylistDatabase.instance.database;
    for (int attempt = 0; attempt < 2; attempt++) {
      final String id = ActiveProfile.instance.id;
      final List<Map<String, Object?>> rows = await db.query(
        _kScoped,
        columns: <String>['channel_id'],
        where: 'profile_id = ?',
        whereArgs: <String>[id],
        orderBy: 'last_watched_at DESC',
        limit: _kMaxEntries,
      );
      if (id != ActiveProfile.instance.id) continue;
      _cache = rows
          .map((Map<String, Object?> r) => r['channel_id'] as String)
          .toList(growable: false);
      if (!_controller.isClosed) _controller.add(_cache);
      return;
    }
  }

  Future<void> record(String channelId) async {
    if (FlavorConfig.current.adultOnly) return;
    await initialize();
    final String profileId = ActiveProfile.instance.id;
    final Database db = await PlaylistDatabase.instance.database;
    final int now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      _kScoped,
      <String, Object?>{
        'profile_id': profileId,
        'channel_id': channelId,
        'last_watched_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final List<Map<String, Object?>> rows = await db.query(
      _kScoped,
      columns: <String>['channel_id'],
      where: 'profile_id = ?',
      whereArgs: <String>[profileId],
      orderBy: 'last_watched_at DESC',
    );
    if (rows.length > _kMaxEntries) {
      final List<String> toDrop = rows
          .skip(_kMaxEntries)
          .map((Map<String, Object?> r) => r['channel_id'] as String)
          .toList();
      if (toDrop.isNotEmpty) {
        await db.delete(
          _kScoped,
          where:
              'profile_id = ? AND channel_id IN (${toDrop.map((_) => '?').join(',')})',
          whereArgs: <Object>[profileId, ...toDrop],
        );
      }
    }
    await _reload();
  }

  /// Restaure l'historique serveur UNIQUEMENT si le tiroir du
  /// profil en cours est vide. N'écrase jamais un historique
  /// déjà là, et n'écrit pas dans le tiroir d'un autre profil.
  Future<void> seedIfEmpty(List<String> ids) async {
    if (ids.isEmpty) return;
    if (FlavorConfig.current.adultOnly) return;
    await initialize();
    if (_cache.isNotEmpty) return;
    final String profileId = ActiveProfile.instance.id;
    final Database db = await PlaylistDatabase.instance.database;
    final Batch batch = db.batch();
    int ts = DateTime.now().millisecondsSinceEpoch;
    final List<String> kept = <String>[];
    for (final String id in ids.take(_kMaxEntries)) {
      if (id.isEmpty) continue;
      batch.insert(
        _kScoped,
        <String, Object?>{
          'profile_id': profileId,
          'channel_id': id,
          'last_watched_at': ts,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      kept.add(id);
      ts -= 1;
    }
    if (kept.isEmpty) return;
    await batch.commit(noResult: true);
    await _reload();
  }

  /// Retire ces chaînes de l'historique de TOUS les profils, et de
  /// l'ancienne table. Le reste de l'historique reste.
  Future<void> forgetChannels(Iterable<String> channelIds) async {
    final List<String> ids = channelIds
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    const int chunk = 400;
    for (int i = 0; i < ids.length; i += chunk) {
      final List<String> part = ids.sublist(
        i,
        i + chunk > ids.length ? ids.length : i + chunk,
      );
      final String marks = List<String>.filled(part.length, '?').join(',');
      await db.delete(
        'recently_watched',
        where: 'channel_id IN ($marks)',
        whereArgs: part,
      );
      await db.delete(
        _kScoped,
        where: 'channel_id IN ($marks)',
        whereArgs: part,
      );
    }
    await _reload();
  }

  /// Vide l'historique du profil en cours seulement.
  Future<void> clear() async {
    await initialize();
    final String profileId = ActiveProfile.instance.id;
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete(
      _kScoped,
      where: 'profile_id = ?',
      whereArgs: <String>[profileId],
    );
    await _reload();
  }

  /// Oublie l'historique d'un profil supprimé. Jamais le profil 1.
  Future<void> dropProfile(String profileId) async {
    if (profileId == ProfileIds.origin) return;
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete(
      _kScoped,
      where: 'profile_id = ?',
      whereArgs: <String>[profileId],
    );
    if (ActiveProfile.instance.id == profileId) await _reload();
  }
}
