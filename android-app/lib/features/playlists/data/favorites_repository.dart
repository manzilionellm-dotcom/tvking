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

  /// Profil autre que Maison. null = table SQLite d'origine.
  String? _scopeId;

  /// Prévenu quand les favoris d'un profil (pas Maison) changent,
  /// pour les écrire à part. Maison ne passe pas par ici.
  void Function(String profileId, Set<String> ids)? onScopeChanged;

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

  /// Revient aux favoris SQLite (profil Maison, ou fonction coupée).
  Future<void> bindHome() async {
    if (_scopeId == null && _initialized) {
      if (!_controller.isClosed) _controller.add(<String>{..._cache});
      return;
    }
    _scopeId = null;
    _initialized = false;
    await initialize();
  }

  /// Favoris d'un autre profil, déjà lus. N'écrit pas dans SQLite.
  Future<void> bindProfile(String profileId, Set<String> ids) async {
    _scopeId = profileId;
    _cache = <String>{...ids};
    _initialized = true;
    if (!_controller.isClosed) _controller.add(<String>{..._cache});
  }

  Future<void> toggle(String channelId) async {
    if (_scopeId != null) {
      if (_cache.contains(channelId)) {
        _cache.remove(channelId);
      } else {
        _cache.add(channelId);
      }
      final Set<String> copy = <String>{..._cache};
      if (!_controller.isClosed) _controller.add(copy);
      onScopeChanged?.call(_scopeId!, copy);
      return;
    }
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
