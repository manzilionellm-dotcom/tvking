// =========================================================
//  favorites_repository.dart — Gestion des favoris
// =========================================================
//  Chaque profil a SES favoris. La table d'origine `favorites`
//  (une seule colonne, d'avant les profils) n'est pas vidée :
//  au premier lancement on COPIE ses lignes dans le tiroir du
//  profil 1, puis on n'y revient plus. Rien n'est perdu, et
//  un favori retiré ne revient pas.
//
//  Stream `favoritesStream` émet l'ensemble des IDs du profil
//  EN COURS à chaque changement → les cœurs se mettent à jour.
//  Changer de profil recharge cet ensemble. Ça ne coupe pas
//  la chaîne qui joue.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../profiles/data/active_profile.dart';
import '../../profiles/domain/family_profile.dart';
import '../../profiles/domain/profile_migration.dart';
import 'playlist_database.dart';

class FavoritesRepository {
  FavoritesRepository._();
  static final FavoritesRepository instance = FavoritesRepository._();

  static const String _kScoped = 'favorites_by_profile';

  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  Set<String> _cache = <String>{};
  /// Base pour laquelle le schéma est prêt (06/10/2026 : le drapeau était
  /// global au processus ; une base rouverte — tests — restait sans table).
  Database? _initializedFor;
  bool get _initialized => _initializedFor != null;
  bool _listening = false;

  Stream<Set<String>> get favoritesStream => _controller.stream;
  Set<String> get current => _cache;

  Future<void> initialize() async {
    final Database db = await PlaylistDatabase.instance.database;
    if (identical(_initializedFor, db)) return;
    await _ensureSchema(db);
    await _migrateLegacyOnce(db);
    _initializedFor = db;
    _listenProfile();
    await _reload();
  }

  Future<void> _ensureSchema(Database db) async {
    // Ancienne table : on la CRÉE si besoin (premier install) mais
    // on ne la supprime jamais. Elle sert de copie de secours.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        channel_id TEXT PRIMARY KEY
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_kScoped (
        profile_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        PRIMARY KEY (profile_id, channel_id)
      )
    ''');
  }

  /// Copie `favorites` → tiroir du profil 1, une seule fois.
  /// `INSERT OR IGNORE` = la même règle que [ProfileMigration.mergeFavorites] :
  /// on AJOUTE, on n'efface rien, on n'écrase pas une ligne déjà là.
  Future<void> _migrateLegacyOnce(Database db) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool done = prefs.getBool(ProfileKeys.favoritesMigrated) ?? false;
      if (!ProfileMigration.shouldCopyLegacy(alreadyMigrated: done)) return;
      // L'id est la constante `p1`, pas une saisie utilisateur.
      await db.execute('''
        INSERT OR IGNORE INTO $_kScoped (profile_id, channel_id)
        SELECT '${ProfileIds.origin}', channel_id FROM favorites
      ''');
      await prefs.setBool(ProfileKeys.favoritesMigrated, true);
    } catch (e) {
      if (kDebugMode) debugPrint('[Favoris] migration profil : $e');
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
    // Deux essais : si l'utilisateur change de profil pendant la
    // lecture, on ne publie pas le tiroir du précédent.
    for (int attempt = 0; attempt < 2; attempt++) {
      final String id = ActiveProfile.instance.id;
      final List<Map<String, Object?>> rows = await db.query(
        _kScoped,
        columns: <String>['channel_id'],
        where: 'profile_id = ?',
        whereArgs: <String>[id],
      );
      if (id != ActiveProfile.instance.id) continue;
      _cache = rows
          .map((Map<String, Object?> r) => r['channel_id'] as String)
          .toSet();
      if (!_controller.isClosed) _controller.add(<String>{..._cache});
      return;
    }
  }

  bool isFavorite(String channelId) => _cache.contains(channelId);

  Future<void> toggle(String channelId) async {
    await initialize();
    final String profileId = ActiveProfile.instance.id;
    final Database db = await PlaylistDatabase.instance.database;
    final bool removing = _cache.contains(channelId);

    if (removing) {
      await db.delete(
        _kScoped,
        where: 'profile_id = ? AND channel_id = ?',
        whereArgs: <String>[profileId, channelId],
      );
    } else {
      await db.insert(
        _kScoped,
        <String, Object?>{
          'profile_id': profileId,
          'channel_id': channelId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    // On recharge depuis le profil ACTUEL (il a pu changer
    // pendant l'écriture). La chaîne en cours, elle, continue.
    await _reload();
  }

  /// Retire ces chaînes des favoris de TOUS les profils, et de
  /// l'ancienne table. Les autres chaînes restent.
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
        'favorites',
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

  /// Oublie les favoris d'un profil supprimé. Jamais le profil 1 :
  /// ses lignes restent, comme l'ancienne table.
  Future<void> dropProfile(String profileId) async {
    if (ProfileIds.origin == profileId) return;
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
