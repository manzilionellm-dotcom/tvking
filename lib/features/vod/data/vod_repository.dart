// =========================================================
//  vod_repository.dart — Catalogue de films (VOD)
// =========================================================
//  Récupère la liste des films à la demande depuis le compte Xtream
//  connecté (via XtreamClient.fetchVodMovies). Mise en cache mémoire
//  pour ne pas retaper le réseau à chaque ouverture de l'écran Films.
//
//  S'il n'y a pas de compte Xtream (que des M3U), ou si le serveur ne
//  propose pas de VOD, on renvoie une liste vide → l'UI affiche un
//  message clair.
// =========================================================

import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/playlist.dart';
import '../../playlists/data/xtream_client.dart';
import '../domain/vod_info.dart';
import '../domain/vod_movie.dart';

class VodRepository {
  VodRepository._();
  static final VodRepository instance = VodRepository._();

  List<VodMovie>? _cache;

  /// Construit un client Xtream depuis la première playlist Xtream active
  /// (`null` si le compte est M3U seul → pas de VOD, pas de get_vod_info).
  Future<XtreamClient?> _client({Duration? timeout}) async {
    final List<Playlist> playlists =
        await PlaylistRepository.instance.getAllPlaylists();
    for (final Playlist p in playlists) {
      if (p.type == PlaylistType.xtream && (p.xtreamServer ?? '').isNotEmpty) {
        return XtreamClient(
          serverUrl: p.xtreamServer!,
          username: p.xtreamUsername ?? '',
          password: p.xtreamPassword ?? '',
          timeout: timeout ?? const Duration(seconds: 20),
        );
      }
    }
    return null;
  }

  /// Renvoie le catalogue de films. [forceRefresh] re-tape le serveur.
  Future<List<VodMovie>> fetchMovies({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;

    final XtreamClient? client = await _client();
    if (client == null) {
      _cache = const <VodMovie>[];
      return _cache!;
    }
    try {
      final List<VodMovie> movies = await client.fetchVodMovies();
      _cache = movies;
      return movies;
    } catch (e) {
      if (kDebugMode) debugPrint('[VOD] fetch error: $e');
      // Serveur sans VOD ou erreur → liste vide (cache court pour
      // permettre un retry rapide via forceRefresh).
      return const <VodMovie>[];
    } finally {
      client.dispose();
    }
  }

  // ============================================================
  //  Fiche détaillée (get_vod_info) — cache mémoire LRU borné
  // ============================================================

  /// Plafond du cache de fiches : ~30 fiches = quelques Ko de texte (le
  /// backdrop est une URL, pas une image). Assez pour une session de
  /// zapping dans les fiches, trop petit pour peser sur une box 1 Go.
  static const int _infoCacheMax = 30;

  /// Cache LRU : LinkedHashMap conserve l'ORDRE D'INSERTION → en retirant
  /// puis ré-insérant à chaque accès, la tête est toujours la fiche la
  /// moins récemment utilisée (celle qu'on évince en premier).
  /// PAS de cache disque, volontairement : anti-bloat (les fiches se
  /// re-fetchent en ~1 s et changent côté serveur).
  final LinkedHashMap<String, VodInfo> _infoCache =
      LinkedHashMap<String, VodInfo>();

  /// Fiche détaillée du film [movieId] (id de la forme `vod-<streamId>`).
  ///
  /// FAIL-OPEN : renvoie `null` pour une source M3U (pas de get_vod_info
  /// possible), un serveur sans fiche, ou toute erreur réseau — la fiche
  /// s'affiche alors avec les seules infos de la vignette. Les échecs ne
  /// sont PAS mis en cache : une réouverture retentera le fetch.
  Future<VodInfo?> fetchInfo(String movieId) async {
    // Seuls les films Xtream (`vod-…`) ont une fiche serveur.
    if (!movieId.startsWith('vod-')) return null;

    // Accès LRU : retirer + ré-insérer = marquer « utilisé récemment ».
    final VodInfo? cached = _infoCache.remove(movieId);
    if (cached != null) {
      _infoCache[movieId] = cached;
      return cached;
    }

    // Timeout plus court que le catalogue : une fiche pèse ~2 Ko — si le
    // serveur met > 12 s, on affiche la fiche « pauvre » plutôt qu'attendre.
    final XtreamClient? client =
        await _client(timeout: const Duration(seconds: 12));
    if (client == null) return null;
    try {
      final VodInfo? info =
          await client.fetchVodInfo(movieId.substring('vod-'.length));
      if (info != null) {
        _infoCache[movieId] = info;
        // Éviction LRU : la tête de la map est la moins récemment utilisée.
        if (_infoCache.length > _infoCacheMax) {
          _infoCache.remove(_infoCache.keys.first);
        }
      }
      return info;
    } catch (e) {
      if (kDebugMode) debugPrint('[VOD] info error: $e');
      return null;
    } finally {
      client.dispose();
    }
  }

  /// Liste des catégories présentes dans le cache courant.
  List<String> categories() {
    final List<VodMovie> m = _cache ?? const <VodMovie>[];
    final Set<String> set = <String>{for (final VodMovie v in m) v.category};
    final List<String> list = set.toList()..sort();
    return list;
  }
}
