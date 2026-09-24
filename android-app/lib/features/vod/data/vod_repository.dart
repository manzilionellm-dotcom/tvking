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
      if (p.type == PlaylistType.xtream &&
          (p.xtreamServer ?? '').isNotEmpty) {
        xt = p;
        break;
      }
    }
    if (xt == null) {
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

  /// Liste des catégories présentes dans le cache courant.
  List<String> categories() {
    final List<VodMovie> m = _cache ?? const <VodMovie>[];
    final Set<String> set = <String>{for (final VodMovie v in m) v.category};
    final List<String> list = set.toList()..sort();
    return list;
  }
}
