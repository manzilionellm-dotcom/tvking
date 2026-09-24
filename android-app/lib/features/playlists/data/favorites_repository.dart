// =========================================================
//  favorites_repository.dart — Gestion des favoris
// =========================================================
//  Stockage simple des IDs de chaînes mis en favoris.
//  Pour l'instant on stocke en SQLite via une table dédiée.
//
//  Stream `favoritesStream` émet l'ensemble des IDs à chaque
//  changement → les écrans qui affichent un cœur se remettent
//  à jour automatiquement (StreamBuilder).
// =========================================================

import 'dart:async';

import 'package:sqflite/sqflite.dart';

import 'playlist_database.dart';

class FavoritesRepository {
  FavoritesRepository._();
  static final FavoritesRepository instance = FavoritesRepository._();

  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  Set<String> _cache = <String>{};
  bool _initialized = false;

  Stream<Set<String>> get favoritesStream => _controller.stream;
  Set<String> get current => _cache;

  Future<void> initialize() async {
    if (_initialized) return;
    final Database db = await PlaylistDatabase.instance.database;

    // Crée la table si elle n'existe pas (compat avec base existante)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        channel_id TEXT PRIMARY KEY
      )
    ''');

    final List<Map<String, Object?>> rows = await db.query('favorites');
    _cache = rows
        .map((Map<String, Object?> r) => r['channel_id'] as String)
        .toSet();
    _initialized = true;
    if (!_controller.isClosed) _controller.add(_cache);
  }

  bool isFavorite(String channelId) => _cache.contains(channelId);

  Future<void> toggle(String channelId) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;

    if (_cache.contains(channelId)) {
      await db.delete('favorites',
          where: 'channel_id = ?', whereArgs: <String>[channelId]);
      _cache.remove(channelId);
    } else {
      await db.insert(
        'favorites',
        <String, Object?>{'channel_id': channelId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      _cache.add(channelId);
    }

    if (!_controller.isClosed) _controller.add(<String>{..._cache});
  }
}
