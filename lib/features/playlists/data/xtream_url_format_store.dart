// =========================================================
//  xtream_url_format_store.dart — Format d'URL gagnant PAR SOURCE
// =========================================================
//  Quand la cascade de variantes Xtream (cf. xtream_url_variants.dart)
//  trouve la forme d'URL que le panel accepte (ex : `/live/U/P/ID.m3u8`
//  alors que la playlist fournissait `U/P/ID.ts`), on la MÉMORISE ici,
//  par source et par type de contenu (live / movie / series).
//
//  Résultat : les chaînes SUIVANTES de la même source appliquent
//  directement le format gagnant à l'ouverture — le zapping reste
//  instantané, la cascade n'a tourné qu'UNE fois. Si le format
//  mémorisé cesse de répondre (panel reconfiguré), le lecteur relance
//  la cascade une fois et met à jour (ou oublie) le format.
//
//  PERSISTANCE : colonne `url_formats` de la table `playlists`
//  (JSON {"live":"live:m3u8","movie":"none:"}), donc liée au cycle de
//  vie de la source (supprimée avec elle) et conservée entre
//  redémarrages. Un cache mémoire évite une lecture SQLite par zap.
//
//  FAIL-OPEN : aucune erreur de lecture/écriture ici ne doit JAMAIS
//  empêcher une lecture vidéo — en cas de pépin on se comporte comme
//  s'il n'y avait rien de mémorisé.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../player/data/xtream_url_variants.dart';
import 'playlist_database.dart';

class XtreamUrlFormatStore {
  XtreamUrlFormatStore._();
  static final XtreamUrlFormatStore instance = XtreamUrlFormatStore._();

  /// Source de la base — remplaçable dans les tests (FFI en mémoire).
  @visibleForTesting
  Future<Database> Function() databaseProvider =
      () => PlaylistDatabase.instance.database;

  /// Cache mémoire : playlistId → {'live': 'live:m3u8', …}.
  final Map<int, Map<String, String>> _cache = <int, Map<String, String>>{};

  /// Playlists dont la ligne a déjà été lue (même si vide) — évite de
  /// retaper SQLite à chaque zap quand rien n'est mémorisé.
  final Set<int> _loaded = <int>{};

  /// Format gagnant mémorisé pour (source, type), ou `null`.
  Future<String?> winningFormat(
    int playlistId,
    XtreamContentType type,
  ) async {
    await _ensureLoaded(playlistId);
    return _cache[playlistId]?[type.name];
  }

  /// Mémorise [formatCode] comme format gagnant de (source, type).
  Future<void> saveWinningFormat(
    int playlistId,
    XtreamContentType type,
    String formatCode,
  ) async {
    await _ensureLoaded(playlistId);
    final Map<String, String> formats =
        _cache.putIfAbsent(playlistId, () => <String, String>{});
    if (formats[type.name] == formatCode) return; // déjà à jour
    formats[type.name] = formatCode;
    await _persist(playlistId, formats);
  }

  /// Oublie le format mémorisé de (source, type) — panel reconfiguré,
  /// le format ne répond plus. Renvoie `true` s'il y avait quelque
  /// chose à oublier.
  Future<bool> clearWinningFormat(
    int playlistId,
    XtreamContentType type,
  ) async {
    await _ensureLoaded(playlistId);
    final Map<String, String>? formats = _cache[playlistId];
    if (formats == null || formats.remove(type.name) == null) return false;
    await _persist(playlistId, formats);
    return true;
  }

  /// Vide le cache mémoire (tests / resynchronisation).
  @visibleForTesting
  void resetCache() {
    _cache.clear();
    _loaded.clear();
  }

  Future<void> _ensureLoaded(int playlistId) async {
    if (_loaded.contains(playlistId)) return;
    try {
      final Database db = await databaseProvider();
      final List<Map<String, Object?>> rows = await db.query(
        'playlists',
        columns: <String>['url_formats'],
        where: 'id = ?',
        whereArgs: <Object>[playlistId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final Object? raw = rows.first['url_formats'];
        if (raw is String && raw.isNotEmpty) {
          final Object? decoded = jsonDecode(raw);
          if (decoded is Map) {
            _cache[playlistId] = decoded.map(
              (Object? k, Object? v) =>
                  MapEntry<String, String>('$k', '$v'),
            );
          }
        }
      }
    } catch (e) {
      // Fail-open : on continue sans mémoire (la cascade retombera
      // sur ses pattes) mais on ne marque PAS la playlist chargée,
      // pour retenter à la prochaine occasion.
      if (kDebugMode) debugPrint('[XtreamFormat] lecture KO: $e');
      return;
    }
    _loaded.add(playlistId);
  }

  Future<void> _persist(int playlistId, Map<String, String> formats) async {
    try {
      final Database db = await databaseProvider();
      await db.update(
        'playlists',
        <String, Object?>{
          'url_formats': formats.isEmpty ? null : jsonEncode(formats),
        },
        where: 'id = ?',
        whereArgs: <Object>[playlistId],
      );
    } catch (e) {
      // Fail-open : le cache mémoire reste correct pour la session
      // courante même si l'écriture disque a échoué.
      if (kDebugMode) debugPrint('[XtreamFormat] écriture KO: $e');
    }
  }
}
