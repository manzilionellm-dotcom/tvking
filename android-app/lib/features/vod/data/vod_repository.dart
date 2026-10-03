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

import 'package:flutter/foundation.dart';

import '../../cinema/data/catalog_cache_policy.dart';
import '../../cinema/data/cinema_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/playlist.dart';
import '../../playlists/data/xtream_client.dart';
import '../domain/vod_movie.dart';

class VodRepository {
  VodRepository._();
  static final VodRepository instance = VodRepository._();

  List<VodMovie>? _cache;

  /// Renvoie le catalogue de films. [forceRefresh] re-tape le serveur.
  Future<List<VodMovie>> fetchMovies({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;

    final List<Playlist> playlists =
        await PlaylistRepository.instance.getAllPlaylists();
    Playlist? xt;
    for (final Playlist p in playlists) {
      if (p.type == PlaylistType.xtream && (p.xtreamServer ?? '').isNotEmpty) {
        xt = p;
        break;
      }
    }
    if (xt == null) {
      final List<VodMovie> saved = await _savedMovies();
      if (saved.isNotEmpty) return saved;
      _cache = const <VodMovie>[];
      return _cache!;
    }

    final XtreamClient client = XtreamClient(
      serverUrl: xt.xtreamServer!,
      username: xt.xtreamUsername ?? '',
      password: xt.xtreamPassword ?? '',
    );
    try {
      final List<VodMovie> movies = await client.fetchVodMovies();
      // Une réponse vide n'efface pas ce qu'on a déjà (mémoire ou disque).
      final List<VodMovie> chosen = keepPreviousWhenEmpty<VodMovie>(
        incoming: movies,
        previous: _cache ?? const <VodMovie>[],
        disk: movies.isNotEmpty ? const <VodMovie>[] : await _savedMovies(),
      );
      if (chosen.isNotEmpty) _cache = chosen;
      return chosen;
    } catch (e) {
      if (kDebugMode) debugPrint('[VOD] fetch error: $e');
      final List<VodMovie> chosen = keepPreviousWhenEmpty<VodMovie>(
        incoming: null,
        previous: _cache ?? const <VodMovie>[],
        disk: await _savedMovies(),
      );
      if (chosen.isNotEmpty) _cache = chosen;
      return chosen;
    } finally {
      client.dispose();
    }
  }

  Future<List<VodMovie>> _savedMovies() async {
    try {
      return await CinemaRepository.instance.cachedVodMovies();
    } catch (e) {
      if (kDebugMode) debugPrint('[VOD] cache disque illisible : $e');
      return const <VodMovie>[];
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
