// =========================================================
//  favorites_repository.dart — Gestion des favoris (AVEC portée / univers)
// =========================================================
//  Stockage des IDs de chaînes mis en favoris, RANGÉS PAR PORTÉE (« scope ») :
//  chaque univers garde SES favoris. Sur TV, « The Few » (accueil Classique)
//  utilise la portée `default` (= favoris historiques, rien n'est perdu) et
//  « Seven » (templates IBO/TiviMate) la portée `seven`. L'app téléphone ne
//  change jamais de portée → elle reste sur `default`.
//
//  L'API publique NE CHANGE PAS (current / favoritesStream / initialize /
//  isFavorite / toggle) → tous les écrans existants continuent tels quels.
//  Nouveauté : `setScope(...)` bascule l'univers actif (favoris rechargés +
//  notifiés). Le zap/affichage suit automatiquement (StreamBuilder/listen).
//
//  Stream `favoritesStream` émet l'ensemble des IDs de la portée ACTIVE à
//  chaque changement (ajout/retrait OU bascule d'univers).
// =========================================================

import 'dart:async';

import 'package:sqflite/sqflite.dart';

import 'playlist_database.dart';

class FavoritesRepository {
  FavoritesRepository._();
  static final FavoritesRepository instance = FavoritesRepository._();

  /// Portée par défaut : favoris historiques + app téléphone + accueil
  /// Classique (« The Few »).
  static const String defaultScope = 'default';

  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  Set<String> _cache = <String>{};
  bool _initialized = false;
  String _scope = defaultScope;

  Stream<Set<String>> get favoritesStream => _controller.stream;
  Set<String> get current => _cache;

  /// Univers actif (les favoris affichés/ajoutés concernent CETTE portée).
  String get scope => _scope;

  Future<void> initialize() async {
    if (_initialized) return;
    final Database db = await PlaylistDatabase.instance.database;

    // Ancienne table (compat app téléphone + anciennes installs).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        channel_id TEXT PRIMARY KEY
      )
    ''');
    // Table AVEC portée : chaque univers garde ses favoris.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites_scoped (
        scope TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        PRIMARY KEY (scope, channel_id)
      )
    ''');
    // Table témoin pour ne migrer QU'UNE SEULE FOIS (sinon un favori retiré
    // « ressusciterait » à chaque démarrage depuis l'ancienne table).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    final List<Map<String, Object?>> done = await db.query(
      'favorites_meta',
      where: 'key = ?',
      whereArgs: <Object>['migrated_scope_v1'],
    );
    if (done.isEmpty) {
      // Migration unique : les anciens favoris (non scopés) rejoignent la
      // portée par défaut → RIEN n'est perdu.
      await db.execute(
        'INSERT OR IGNORE INTO favorites_scoped (scope, channel_id) '
        'SELECT ?, channel_id FROM favorites',
        <Object>[defaultScope],
      );
      await db.insert(
        'favorites_meta',
        <String, Object?>{'key': 'migrated_scope_v1', 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    _initialized = true;
    await _reload();
  }

  /// Recharge le cache pour la portée ACTIVE et notifie.
  Future<void> _reload() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      'favorites_scoped',
      columns: <String>['channel_id'],
      where: 'scope = ?',
      whereArgs: <Object>[_scope],
    );
    _cache = rows
        .map((Map<String, Object?> r) => r['channel_id'] as String)
        .toSet();
    if (!_controller.isClosed) _controller.add(<String>{..._cache});
  }

  /// Bascule l'UNIVERS actif. Chaque univers a ses propres favoris : on
  /// recharge la liste correspondante et on notifie (les écrans se mettent à
  /// jour). No-op si c'est déjà la portée active.
  Future<void> setScope(String scope) async {
    await initialize();
    if (scope == _scope) return;
    _scope = scope;
    await _reload();
  }

  bool isFavorite(String channelId) => _cache.contains(channelId);

  Future<void> toggle(String channelId) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;

    if (_cache.contains(channelId)) {
      await db.delete(
        'favorites_scoped',
        where: 'scope = ? AND channel_id = ?',
        whereArgs: <Object>[_scope, channelId],
      );
      _cache.remove(channelId);
    } else {
      await db.insert(
        'favorites_scoped',
        <String, Object?>{'scope': _scope, 'channel_id': channelId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      _cache.add(channelId);
    }

    if (!_controller.isClosed) _controller.add(<String>{..._cache});
  }
}
