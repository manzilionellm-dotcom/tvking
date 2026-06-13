// =========================================================
//  recently_watched_repository.dart — Historique des visionnages
// =========================================================
//  Sert à alimenter la section "Continue Watching" de l'accueil.
//
//  Modèle ultra simple en Phase 1 : on stocke juste les IDs
//  des chaînes ouvertes + un timestamp. Quand on ouvre une
//  chaîne via le helper `playChannel`, on enregistre l'event.
//
//  Limite : on garde les 50 dernières chaînes uniques. Au-delà
//  on supprime les plus anciennes. Évite que la table gonfle.
//
//  Phase ultérieure (3+) : on stockera aussi la position dans
//  les programmes catch-up (timestamp dans le replay).
// =========================================================

import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../../core/flavor/flavor.dart';
import '../../playlists/data/playlist_database.dart';

class RecentlyWatchedRepository {
  RecentlyWatchedRepository._();
  static final RecentlyWatchedRepository instance =
      RecentlyWatchedRepository._();

  static const int _kMaxEntries = 50;

  final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();

  /// Stream émettant la liste des IDs de chaînes, triés du plus
  /// récemment visionné au plus ancien.
  Stream<List<String>> get stream => _controller.stream;

  List<String> _cache = <String>[];
  bool _initialized = false;

  List<String> get current => List<String>.unmodifiable(_cache);

  Future<void> initialize() async {
    if (_initialized) return;
    final Database db = await PlaylistDatabase.instance.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recently_watched (
        channel_id TEXT PRIMARY KEY,
        last_watched_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recent_ts
      ON recently_watched(last_watched_at DESC)
    ''');

    final List<Map<String, Object?>> rows = await db.query(
      'recently_watched',
      orderBy: 'last_watched_at DESC',
      limit: _kMaxEntries,
    );
    _cache = rows
        .map((Map<String, Object?> r) => r['channel_id'] as String)
        .toList();
    _initialized = true;
    if (!_controller.isClosed) _controller.add(_cache);
  }

  Future<void> record(String channelId) async {
    // Mode incognito (flavor adulte « Privé ») : on n'enregistre AUCUN
    // historique de visionnage → pas de « Continuer à regarder », rien à
    // retrouver pour un tiers. Discrétion totale.
    if (FlavorConfig.current.adultOnly) return;
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'recently_watched',
      <String, Object?>{
        'channel_id': channelId,
        'last_watched_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Nettoyage : on garde max 50 entrées
    final List<Map<String, Object?>> rows = await db.query(
      'recently_watched',
      orderBy: 'last_watched_at DESC',
    );
    if (rows.length > _kMaxEntries) {
      final List<String> toDrop = rows
          .skip(_kMaxEntries)
          .map((Map<String, Object?> r) => r['channel_id'] as String)
          .toList();
      if (toDrop.isNotEmpty) {
        await db.delete(
          'recently_watched',
          where: 'channel_id IN (${toDrop.map((_) => '?').join(',')})',
          whereArgs: toDrop,
        );
      }
    }

    _cache = rows
        .take(_kMaxEntries)
        .map((Map<String, Object?> r) => r['channel_id'] as String)
        .toList();
    // S'assurer que celui qu'on vient d'enregistrer est tout en haut
    _cache
      ..remove(channelId)
      ..insert(0, channelId);
    if (_cache.length > _kMaxEntries) {
      _cache.removeRange(_kMaxEntries, _cache.length);
    }

    if (!_controller.isClosed) _controller.add(_cache);
  }

  Future<void> clear() async {
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('recently_watched');
    _cache = <String>[];
    if (!_controller.isClosed) _controller.add(_cache);
  }
}
