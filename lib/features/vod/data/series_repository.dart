// =========================================================
//  series_repository.dart — Catalogue de séries (VOD)
// =========================================================
//  Récupère la liste des séries depuis le compte Xtream connecté
//  (XtreamClient.fetchSeries) avec cache mémoire. Les ÉPISODES d'une série
//  sont chargés À LA DEMANDE (fetchEpisodes) à l'ouverture de la fiche, car
//  ils nécessitent un 2e appel réseau (get_series_info) par série.
//
//  Sans compte Xtream (M3U seul) ou sans séries → listes vides → message clair.
//
//  VITESSE « façon Netflix » (même mécanique que VodRepository) : cache
//  MÉMOIRE → cache DISQUE (ouverture instantanée + rafraîchissement réseau
//  silencieux, notifyListeners quand du neuf arrive) → réseau en dernier.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/i18n/l10n_now.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../domain/vod_info.dart';
import '../domain/vod_series.dart';

/// Décodage du cache disque en ISOLATE (10 000 séries possibles).
List<VodSeries> decodeSeriesCatalog(String raw) {
  final Map<String, dynamic> root = jsonDecode(raw) as Map<String, dynamic>;
  if (root['v'] != 1) return const <VodSeries>[];
  return (root['s'] as List<dynamic>)
      .map((dynamic e) => VodSeries.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// Encodage du cache disque en ISOLATE.
String encodeSeriesCatalog(List<VodSeries> series) =>
    jsonEncode(<String, dynamic>{
      'v': 1,
      's': series.map((VodSeries s) => s.toJson()).toList(growable: false),
    });

class SeriesRepository extends ChangeNotifier {
  SeriesRepository._();
  static final SeriesRepository instance = SeriesRepository._();

  List<VodSeries>? _cache;
  bool _refreshing = false;

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
  /// Mémoire → disque (instantané + refresh silencieux) → réseau.
  Future<List<VodSeries>> fetchSeries({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;
    if (!forceRefresh) {
      final List<VodSeries>? disk = await _loadDiskCache();
      if (disk != null && disk.isNotEmpty) {
        _cache = disk;
        unawaited(_refreshInBackground());
        return disk;
      }
    }
    final List<VodSeries> fresh = await _fetchFromNetwork();
    if (fresh.isNotEmpty || forceRefresh) {
      _cache = fresh;
      unawaited(_saveDiskCache(fresh));
    }
    return _cache ?? fresh;
  }

  Future<List<VodSeries>> _fetchFromNetwork() async {
    final XtreamClient? client = await _client();
    if (client == null) {
      _cache = const <VodSeries>[];
      return const <VodSeries>[];
    }
    try {
      return await client.fetchSeries();
    } catch (e) {
      if (kDebugMode) debugPrint('[Series] fetch error: $e');
      return const <VodSeries>[];
    } finally {
      client.dispose();
    }
  }

  /// Stale-while-revalidate : re-télécharge derrière l'écran affiché et
  /// prévient les abonnés si le catalogue a changé.
  Future<void> _refreshInBackground() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final List<VodSeries> fresh = await _fetchFromNetwork();
      if (fresh.isEmpty) return; // panne → on garde le cache affiché
      final List<VodSeries>? old = _cache;
      final bool changed = old == null ||
          old.length != fresh.length ||
          (old.isNotEmpty &&
              (old.first.id != fresh.first.id || old.last.id != fresh.last.id));
      _cache = fresh;
      unawaited(_saveDiskCache(fresh));
      if (changed) notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  Future<File> _cacheFile() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File('${dir.path}/series_catalog_cache.json');
  }

  Future<List<VodSeries>?> _loadDiskCache() async {
    try {
      final File f = await _cacheFile();
      if (!await f.exists()) return null;
      final String raw = await f.readAsString();
      if (raw.isEmpty) return null;
      return await compute(decodeSeriesCatalog, raw);
    } catch (e) {
      if (kDebugMode) debugPrint('[Series] cache disque illisible: $e');
      return null;
    }
  }

  Future<void> _saveDiskCache(List<VodSeries> series) async {
    try {
      final String raw = await compute(encodeSeriesCatalog, series);
      final File f = await _cacheFile();
      await f.writeAsString(raw, flush: true);
    } catch (e) {
      if (kDebugMode) debugPrint('[Series] cache disque non écrit: $e');
    }
  }

  /// Épisodes d'une série (chargés à la demande, non mis en cache global).
  Future<List<VodEpisode>> fetchEpisodes(String seriesId) async {
    return (await fetchDetail(seriesId)).episodes;
  }

  /// Fiche COMPLÈTE d'une série : épisodes + métadonnées riches (synopsis,
  /// casting, genre, image de fond) — le MÊME appel `get_series_info` sert
  /// les deux, aucun réseau supplémentaire. `info` est `null` si le serveur
  /// n'en fournit pas (fail-open : la fiche s'affiche avec ce qu'elle a).
  Future<({VodInfo? info, List<VodEpisode> episodes})> fetchDetail(
      String seriesId) async {
    final XtreamClient? client = await _client();
    if (client == null) return (info: null, episodes: const <VodEpisode>[]);
    try {
      return await client.fetchSeriesDetail(seriesId);
    } catch (e) {
      if (kDebugMode) debugPrint('[Series] detail error: $e');
      return (info: null, episodes: const <VodEpisode>[]);
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
