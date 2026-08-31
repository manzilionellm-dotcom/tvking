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
//
//  ---------------------------------------------------------
//  VAGUE 2 (30/08) — UN HISTORIQUE PAR PROFIL
//  ---------------------------------------------------------
//  Demande du propriétaire : chaque profil de la famille a « son propre
//  historique ». C'est celui-ci que l'on voit : la rangée « Continuer à
//  regarder » de l'accueil. Ce que papa a regardé ne doit plus s'afficher
//  chez enfant deux.
//
//  Les autres données par profil du projet passent par un SUFFIXE de clé
//  SharedPreferences. Ici on est en SQLite : le pendant du suffixe est une
//  COLONNE `profile_id` et une clé primaire (profil, chaîne) — sans ça,
//  `channel_id` étant seul en clé primaire, deux profils regardant la même
//  chaîne écraseraient mutuellement leur ligne.
//
//  LA MIGRATION EST LE MOMENT DÉLICAT : l'historique existant appartient à
//  tout le monde et ne doit pas disparaître. Il est donc recopié tel quel
//  sous le profil « default » (« Famille »), le tout dans UNE transaction :
//  si quoi que ce soit échoue, l'ancienne table est encore là, intacte.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/flavor/flavor.dart';
import '../../../core/profiles/profiles_repository.dart';
import '../../playlists/data/playlist_database.dart';

class RecentlyWatchedRepository {
  RecentlyWatchedRepository._();
  static final RecentlyWatchedRepository instance =
      RecentlyWatchedRepository._();

  static const int _kMaxEntries = 50;

  /// Le profil dont on lit/écrit l'historique. `default` = « Famille »,
  /// c'est-à-dire l'historique historique (celui d'avant les profils).
  static String get _profileId => ProfilesRepository.instance.active.id;

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

    // Table dans sa forme ACTUELLE (installation neuve). Les box déjà
    // installées passent par _migrateToPerProfile juste après.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recently_watched (
        profile_id TEXT NOT NULL DEFAULT 'default',
        channel_id TEXT NOT NULL,
        last_watched_at INTEGER NOT NULL,
        PRIMARY KEY (profile_id, channel_id)
      )
    ''');
    await _migrateToPerProfile(db);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recent_profile_ts
      ON recently_watched(profile_id, last_watched_at DESC)
    ''');

    _initialized = true;
    await reload();
  }

  /// Ajoute la colonne `profile_id` aux box installées AVANT les profils.
  ///
  ///  On ne peut pas simplement faire `ALTER TABLE ... ADD COLUMN` : il
  ///  faut aussi changer la CLÉ PRIMAIRE (de `channel_id` seul à
  ///  `(profile_id, channel_id)`), et SQLite ne sait pas modifier une clé
  ///  primaire en place. On recrée donc la table et on recopie.
  ///
  ///  TOUT DANS UNE TRANSACTION : si la recopie échoue à mi-chemin, rien
  ///  n'est validé et l'ancienne table est toujours là. Un historique perdu
  ///  ne se retrouve pas — celui-là, on ne le joue pas « best-effort ».
  Future<void> _migrateToPerProfile(Database db) async {
    try {
      final List<Map<String, Object?>> cols =
          await db.rawQuery('PRAGMA table_info(recently_watched)');
      final bool hasProfile =
          cols.any((Map<String, Object?> c) => c['name'] == 'profile_id');
      if (hasProfile) return; // déjà au bon format
      await db.transaction((Transaction txn) async {
        await txn.execute('''
          CREATE TABLE recently_watched_v2 (
            profile_id TEXT NOT NULL DEFAULT 'default',
            channel_id TEXT NOT NULL,
            last_watched_at INTEGER NOT NULL,
            PRIMARY KEY (profile_id, channel_id)
          )
        ''');
        // L'historique existant devient celui de « Famille » : c'est bien
        // lui qui l'a produit, et c'est le profil ouvert par défaut. Personne
        // ne constate de perte au premier lancement après la mise à jour.
        await txn.execute(
          "INSERT INTO recently_watched_v2 (profile_id, channel_id, last_watched_at) "
          "SELECT 'default', channel_id, last_watched_at FROM recently_watched",
        );
        await txn.execute('DROP TABLE recently_watched');
        await txn
            .execute('ALTER TABLE recently_watched_v2 RENAME TO recently_watched');
      });
      if (kDebugMode) debugPrint('[Recents] migration par profil OK');
    } catch (e) {
      // La transaction a été annulée : l'ancienne table est intacte et
      // l'app continue de fonctionner (historique partagé). On TRACE, sinon
      // on chercherait longtemps pourquoi les profils partagent le leur.
      debugPrint('[Recents] migration par profil ECHOUEE: $e');
    }
  }

  /// Relit l'historique du profil ACTIF. Appelée à chaque bascule de profil.
  Future<void> reload() async {
    if (!_initialized) return initialize();
    final Database db = await PlaylistDatabase.instance.database;
    List<Map<String, Object?>> rows;
    try {
      rows = await db.query(
        'recently_watched',
        where: 'profile_id = ?',
        whereArgs: <Object?>[_profileId],
        orderBy: 'last_watched_at DESC',
        limit: _kMaxEntries,
      );
    } catch (_) {
      // Migration échouée : la table n'a pas de colonne profile_id. On
      // retombe sur l'historique partagé plutôt que d'afficher du vide.
      rows = await db.query('recently_watched',
          orderBy: 'last_watched_at DESC', limit: _kMaxEntries);
    }
    _cache = rows
        .map((Map<String, Object?> r) => r['channel_id'] as String)
        .toList();
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
    final String profile = _profileId;

    await db.insert(
      'recently_watched',
      <String, Object?>{
        'profile_id': profile,
        'channel_id': channelId,
        'last_watched_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Nettoyage : on garde max 50 entrées PAR PROFIL. Le plafond est par
    // profil et non global : sinon l'enfant qui zappe beaucoup effacerait
    // l'historique de son père.
    final List<Map<String, Object?>> rows = await db.query(
      'recently_watched',
      where: 'profile_id = ?',
      whereArgs: <Object?>[profile],
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
          where: 'profile_id = ? AND '
              'channel_id IN (${toDrop.map((_) => '?').join(',')})',
          whereArgs: <Object?>[profile, ...toDrop],
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

  /// RESTAURE l'historique depuis le serveur (synchro multi-box) UNIQUEMENT
  /// si le local est vide (nouvelle box / réinstallation). N'écrase JAMAIS un
  /// historique local existant — le local reste prioritaire (et c'est lui que
  /// le heartbeat renvoie au serveur). Ordre décroissant préservé.
  Future<void> seedIfEmpty(List<String> ids) async {
    if (ids.isEmpty) return;
    // Mode incognito (flavor « Privé ») : aucun historique, jamais.
    if (FlavorConfig.current.adultOnly) return;
    await initialize();
    if (_cache.isNotEmpty) return; // le local gagne
    final Database db = await PlaylistDatabase.instance.database;
    final Batch batch = db.batch();
    int ts = DateTime.now().millisecondsSinceEpoch;
    final List<String> kept = <String>[];
    final String profile = _profileId;
    for (final String id in ids.take(_kMaxEntries)) {
      if (id.isEmpty) continue;
      batch.insert(
        'recently_watched',
        <String, Object?>{
          'profile_id': profile,
          'channel_id': id,
          'last_watched_at': ts,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      kept.add(id);
      ts -= 1; // garde l'ordre (plus récent en premier)
    }
    if (kept.isEmpty) return;
    await batch.commit(noResult: true);
    _cache = kept;
    if (!_controller.isClosed) _controller.add(_cache);
  }

  /// Efface l'historique du profil ACTIF uniquement. Effacer le sien ne
  /// doit pas effacer celui des autres membres de la famille.
  Future<void> clear() async {
    final Database db = await PlaylistDatabase.instance.database;
    try {
      await db.delete('recently_watched',
          where: 'profile_id = ?', whereArgs: <Object?>[_profileId]);
    } catch (_) {
      // Migration échouée (table restée à l'ancien format) : on efface tout,
      // ce qui était le comportement d'avant les profils.
      await db.delete('recently_watched');
    }
    _cache = <String>[];
    if (!_controller.isClosed) _controller.add(_cache);
  }
}
