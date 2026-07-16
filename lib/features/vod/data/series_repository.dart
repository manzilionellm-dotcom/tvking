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

import 'package:flutter/foundation.dart';

import '../../../core/i18n/l10n_now.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../domain/vod_info.dart';
import '../domain/vod_series.dart';
import 'catalog_disk_cache.dart';
import '../../player/data/stream_diagnostics.dart';

/// Décodage du cache disque en ISOLATE (10 000 séries possibles).
List<VodSeries> decodeSeriesCatalog(String raw) {
  final Map<String, dynamic> root = jsonDecode(raw) as Map<String, dynamic>;
  if (root['v'] != 1) return const <VodSeries>[];
  return (root['s'] as List<dynamic>)
      .map((dynamic e) => VodSeries.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// Encodage du cache disque en ISOLATE (clé de source 'k' en tête).
String encodeSeriesCatalog((List<VodSeries>, String) input) =>
    jsonEncode(<String, dynamic>{
      'v': 1,
      'k': input.$2,
      's': input.$1.map((VodSeries s) => s.toJson()).toList(growable: false),
    });

class SeriesRepository extends ChangeNotifier {
  SeriesRepository._();
  static final SeriesRepository instance = SeriesRepository._();

  List<VodSeries>? _cache;
  bool _refreshing = false;

  final CatalogDiskCache<VodSeries> _disk = CatalogDiskCache<VodSeries>(
    fileName: 'series_catalog_cache.json',
    decode: decodeSeriesCatalog,
    encode: encodeSeriesCatalog,
  );

  /// Empreinte de la source active (même contrat que VodRepository).
  Future<String> _sourceKey() async {
    final List<Playlist> playlists =
        await PlaylistRepository.instance.getAllPlaylists();
    for (final Playlist p in playlists) {
      if (p.type == PlaylistType.xtream && (p.xtreamServer ?? '').isNotEmpty) {
        return '${p.xtreamServer}|${p.xtreamUsername ?? ''}'
            .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      }
    }
    return 'none';
  }

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
    if (!forceRefresh && _cache != null) {
      _diag('mémoire : ${_cache!.length} séries');
      return _cache!;
    }
    final String key = await _sourceKey();
    if (!forceRefresh) {
      final List<VodSeries>? disk = await _disk.load(key);
      if (disk != null && disk.isNotEmpty) {
        _cache = disk;
        _diag('disque (source $key) : ${disk.length} séries');
        unawaited(_refreshInBackground());
        return disk;
      }
    }
    _diag('réseau demandé (source $key)…');
    final List<VodSeries> fresh = await _fetchFromNetwork();
    if (fresh.isNotEmpty) {
      _cache = fresh;
      _diag('réseau OK : ${fresh.length} séries reçues');
      unawaited(_disk.save(fresh, key));
    } else {
      // Réseau vide / panne : on NE MET PAS en cache le vide (sinon l'écran
      // resterait vide toute la session) → réessai à la prochaine ouverture.
      // On conserve un éventuel cache existant (pas de destruction).
      _diag(
          'réseau : 0 série (source sans séries, compte M3U, ou panne) — '
          'réessai à la prochaine ouverture',
          level: 'warn');
    }
    return _cache ?? const <VodSeries>[];
  }

  void _diag(String m, {String level = 'info'}) =>
      StreamDiagnostics.instance.recordEvent('séries', m, level: level);

  /// Appel réseau brut — AUCUN effet de bord sur _cache.
  Future<List<VodSeries>> _fetchFromNetwork() async {
    final XtreamClient? client = await _client();
    if (client == null) return const <VodSeries>[];
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
  /// prévient les abonnés si le catalogue a changé (empreinte de TOUS les
  /// ids) ; sauvegarde disque uniquement en cas de changement.
  Future<void> _refreshInBackground() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final List<VodSeries> fresh = await _fetchFromNetwork();
      if (fresh.isEmpty) return; // panne / M3U seul → cache affiché conservé
      final List<VodSeries> old = _cache ?? const <VodSeries>[];
      final bool changed = catalogChanged(
        <String>[for (final VodSeries s in old) s.id],
        <String>[for (final VodSeries s in fresh) s.id],
      );
      _cache = fresh;
      if (changed) {
        unawaited(_disk.save(fresh, await _sourceKey()));
        notifyListeners();
      }
    } finally {
      _refreshing = false;
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
    if (client == null) {
      _diag('ouverture série $seriesId : aucun compte Xtream (M3U seul) → '
          'pas d\'épisodes', level: 'warn');
      return (info: null, episodes: const <VodEpisode>[]);
    }
    try {
      final ({VodInfo? info, List<VodEpisode> episodes}) d =
          await client.fetchSeriesDetail(seriesId);
      _diag(d.episodes.isEmpty
          ? 'ouverture série $seriesId : 0 épisode renvoyé par le serveur'
          : 'ouverture série $seriesId : ${d.episodes.length} épisodes',
          level: d.episodes.isEmpty ? 'warn' : 'info');
      return d;
    } catch (e) {
      if (kDebugMode) debugPrint('[Series] detail error: $e');
      _diag('ouverture série $seriesId : ÉCHEC ($e)', level: 'error');
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
