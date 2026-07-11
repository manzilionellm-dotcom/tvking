// =========================================================
//  series_repository.dart — Catalogue de séries (VOD)
// =========================================================
//  Récupère la liste des séries depuis le compte Xtream connecté
//  (XtreamClient.fetchSeries) avec cache mémoire. Les ÉPISODES d'une série
//  sont chargés À LA DEMANDE (fetchEpisodes) à l'ouverture de la fiche, car
//  ils nécessitent un 2e appel réseau (get_series_info) par série.
//
//  Sans compte Xtream (M3U seul) ou sans séries → listes vides → message clair.
// =========================================================

import 'package:flutter/foundation.dart';

import '../../../core/i18n/l10n_now.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../domain/vod_series.dart';

class SeriesRepository {
  SeriesRepository._();
  static final SeriesRepository instance = SeriesRepository._();

  List<VodSeries>? _cache;

  /// Construit un client Xtream depuis la playlist active (ou null si aucune).
  Future<XtreamClient?> _client() async {
    final List<Playlist> playlists =
        await PlaylistRepository.instance.getAllPlaylists();
    for (final Playlist p in playlists) {
      if (p.type == PlaylistType.xtream && (p.xtreamServer ?? '').isNotEmpty) {
        return XtreamClient(
          serverUrl: p.xtreamServer!,
          username: p.xtreamUsername ?? '',
          password: p.xtreamPassword ?? '',
        );
      }
    }
    return null;
  }

  /// Catalogue des séries (vignettes). [forceRefresh] re-tape le serveur.
  Future<List<VodSeries>> fetchSeries({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;
    final XtreamClient? client = await _client();
    if (client == null) {
      _cache = const <VodSeries>[];
      return _cache!;
    }
    try {
      final List<VodSeries> series = await client.fetchSeries();
      _cache = series;
      return series;
    } catch (e) {
      if (kDebugMode) debugPrint('[Series] fetch error: $e');
      return const <VodSeries>[];
    } finally {
      client.dispose();
    }
  }

  /// Épisodes d'une série (chargés à la demande, non mis en cache global).
  Future<List<VodEpisode>> fetchEpisodes(String seriesId) async {
    final XtreamClient? client = await _client();
    if (client == null) return const <VodEpisode>[];
    try {
      return await client.fetchSeriesEpisodes(seriesId);
    } catch (e) {
      if (kDebugMode) debugPrint('[Series] episodes error: $e');
      return const <VodEpisode>[];
    } finally {
      client.dispose();
    }
  }

  /// Catégories présentes dans le cache courant (ordre d'apparition).
  /// Le repli « Autres » (catégorie vide côté serveur) est TRADUIT via
  /// `l10nNow` : la liste est recalculée à chaque appel, donc le libellé
  /// suit la langue active (clé existante sectionOthers).
  List<String> categories() {
    final List<VodSeries> s = _cache ?? const <VodSeries>[];
    final List<String> cats = <String>[];
    final Set<String> seen = <String>{};
    for (final VodSeries v in s) {
      final String c = v.category.trim().isEmpty
          ? l10nNow.sectionOthers
          : v.category.trim();
      if (seen.add(c)) cats.add(c);
    }
    return cats;
  }
}
