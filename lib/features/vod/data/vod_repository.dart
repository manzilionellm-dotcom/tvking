// =========================================================
//  vod_repository.dart — Catalogue de films (VOD), « façon Netflix »
// =========================================================
//  Récupère la liste des films depuis le compte Xtream connecté
//  (XtreamClient.fetchVodMovies) avec TROIS étages de vitesse :
//
//    1. CACHE MÉMOIRE : instantané tant que l'app vit ;
//    2. CACHE DISQUE (JSON, dossier de l'app) : à la RÉOUVERTURE de l'app,
//       l'écran Films s'affiche IMMÉDIATEMENT depuis le disque (décodage en
//       ISOLATE — jamais sur le thread UI), pendant qu'un rafraîchissement
//       réseau part EN ARRIÈRE-PLAN (stale-while-revalidate — la technique
//       de Netflix) ; s'il rapporte du neuf, [notifyListeners] prévient
//       l'écran qui se met à jour SANS spinner ;
//    3. RÉSEAU : uniquement au tout premier lancement (cache vide) ou sur
//       forceRefresh explicite.
//
//  Fini le « rond qui tourne » à chaque ouverture du Cinéma.
//
//  S'il n'y a pas de compte Xtream (que des M3U), ou si le serveur ne
//  propose pas de VOD, on renvoie une liste vide → l'UI affiche un
//  message clair.
// =========================================================

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/playlist.dart';
import '../../playlists/data/xtream_client.dart';
import '../domain/vod_info.dart';
import '../domain/vod_movie.dart';
import 'catalog_disk_cache.dart';
import 'm3u_vod_source.dart';
import '../../player/data/stream_diagnostics.dart';

/// Décode le fichier de cache (JSON → films) — TOP-LEVEL pour tourner dans
/// un isolate via [compute] : 10 000 films = ~2-5 Mo de JSON, un décodage
/// sur le thread UI gèlerait l'interface (anti-fluidité).
List<VodMovie> decodeVodCatalog(String raw) {
  final Map<String, dynamic> root = jsonDecode(raw) as Map<String, dynamic>;
  if (root['v'] != 1) return const <VodMovie>[]; // version inconnue → ignore
  final List<dynamic> list = root['m'] as List<dynamic>;
  return list
      .map((dynamic e) => VodMovie.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// Encode le catalogue pour le disque — TOP-LEVEL pour [compute]. La clé de
/// source 'k' est écrite EN TÊTE (lue sans décoder tout le fichier — cf.
/// CatalogDiskCache.sourceKeyOf).
String encodeVodCatalog((List<VodMovie>, String) input) =>
    jsonEncode(<String, dynamic>{
      'v': 1,
      'k': input.$2,
      'm': input.$1.map((VodMovie m) => m.toJson()).toList(growable: false),
    });

class VodRepository extends ChangeNotifier {
  VodRepository._() {
    // Les films M3U vivent dans SQLite (table channels, is_live=0) : quand
    // la source change (import, refresh, suppression), on invalide la part
    // M3U et on prévient les écrans — même contrat que le refresh silencieux.
    PlaylistRepository.instance.channelsStream.listen((_) {
      if (_m3uMovies == null) return;
      _m3uMovies = null;
      notifyListeners();
    });
  }
  static final VodRepository instance = VodRepository._();

  /// Part XTREAM du catalogue (mémoire ← disque ← réseau).
  List<VodMovie>? _cache;

  /// Part M3U du catalogue (films `is_live=0` relus de SQLite — SQLite EST
  /// leur cache disque, pas besoin d'un second fichier JSON).
  List<VodMovie>? _m3uMovies;

  /// Un seul rafraîchissement réseau à la fois (anti-tempête de requêtes).
  bool _refreshing = false;

  /// Cache disque partagé (socle commun films/séries — voir
  /// catalog_disk_cache.dart, clé de source incluse).
  final CatalogDiskCache<VodMovie> _disk = CatalogDiskCache<VodMovie>(
    fileName: 'vod_catalog_cache.json',
    decode: decodeVodCatalog,
    encode: encodeVodCatalog,
  );

  /// Empreinte de la source ACTIVE (serveur + utilisateur Xtream). Le cache
  /// disque n'est relu QUE si elle correspond — jamais le catalogue d'un
  /// ancien compte après un « Changer la source ».
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

  /// Renvoie le catalogue de films UNIFIÉ : part Xtream (get_vod_streams)
  /// + part M3U (fichiers VOD de la playlist, classés au parsing).
  /// [forceRefresh] re-tape le serveur (Xtream) et relit SQLite (M3U).
  ///
  /// Chemin RAPIDE (façon Netflix) : mémoire, sinon DISQUE (immédiat, avec
  /// rafraîchissement réseau silencieux derrière), sinon réseau. Les écrans
  /// qui veulent suivre les mises à jour silencieuses s'abonnent au
  /// [ChangeNotifier] (addListener) et relisent fetchMovies() — qui répond
  /// alors depuis la mémoire, sans re-travail.
  Future<List<VodMovie>> fetchMovies({bool forceRefresh = false}) async {
    final List<VodMovie> xtream =
        await _fetchXtreamMovies(forceRefresh: forceRefresh);
    final List<VodMovie> m3u = await _fetchM3uMovies(forceRefresh: forceRefresh);
    if (m3u.isEmpty) return xtream;
    if (xtream.isEmpty) return m3u;
    return <VodMovie>[...xtream, ...m3u];
  }

  /// Films M3U (SQLite → mémoire). SQLite est déjà local : pas d'étage
  /// disque supplémentaire, une requête bornée suffit à (re)chauffer.
  Future<List<VodMovie>> _fetchM3uMovies({bool forceRefresh = false}) async {
    if (!forceRefresh && _m3uMovies != null) return _m3uMovies!;
    try {
      final List<Channel> vod =
          await PlaylistRepository.instance.getVodChannels();
      final List<Channel> movies = splitM3uVod(vod).movies;
      _m3uMovies =
          movies.map(m3uChannelToMovie).toList(growable: false);
      if (_m3uMovies!.isNotEmpty) {
        _diag('M3U : ${_m3uMovies!.length} films détectés dans la playlist');
      }
    } catch (e) {
      // Fail-open : une erreur SQLite ne prive pas l'écran de la part Xtream.
      if (kDebugMode) debugPrint('[VOD] m3u error: $e');
      _m3uMovies = const <VodMovie>[];
    }
    return _m3uMovies!;
  }

  /// Part Xtream seule (mémoire → disque → réseau) — logique historique.
  Future<List<VodMovie>> _fetchXtreamMovies({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) {
      _diag('mémoire : ${_cache!.length} films');
      return _cache!;
    }
    final String key = await _sourceKey();
    if (!forceRefresh) {
      final List<VodMovie>? disk = await _disk.load(key);
      if (disk != null && disk.isNotEmpty) {
        _cache = disk;
        _diag('disque (source $key) : ${disk.length} films → '
            'rafraîchissement en arrière-plan');
        unawaited(_refreshInBackground());
        return disk;
      }
    }
    _diag('réseau demandé (source $key)…');
    final List<VodMovie> fresh = await _fetchFromNetwork();
    if (fresh.isNotEmpty) {
      _cache = fresh;
      _diag('réseau OK : ${fresh.length} films reçus');
      unawaited(_disk.save(fresh, key));
    } else {
      // Réseau vide / panne : on NE MET PAS en cache le vide (sinon l'écran
      // resterait vide toute la session) → réessai à la prochaine ouverture.
      // On conserve un éventuel cache existant (pas de destruction).
      _diag(
          'réseau : 0 film (source sans VOD, compte M3U, ou panne) — '
          'réessai à la prochaine ouverture',
          level: 'warn');
    }
    return _cache ?? const <VodMovie>[];
  }

  void _diag(String m, {String level = 'info'}) =>
      StreamDiagnostics.instance.recordEvent('cinéma', m, level: level);

  /// Appel réseau brut (liste vide en cas d'erreur — fail-open, et AUCUN
  /// effet de bord sur _cache : c'est l'appelant qui décide quoi garder).
  Future<List<VodMovie>> _fetchFromNetwork() async {
    final XtreamClient? client = await _client();
    if (client == null) return const <VodMovie>[];
    try {
      return await client.fetchVodMovies();
    } catch (e) {
      if (kDebugMode) debugPrint('[VOD] fetch error: $e');
      return const <VodMovie>[];
    } finally {
      client.dispose();
    }
  }

  /// Rafraîchissement SILENCIEUX (stale-while-revalidate) : re-télécharge le
  /// catalogue derrière l'écran déjà affiché ; s'il a changé, prévient les
  /// abonnés. Panne / M3U seul → on garde le cache affiché, sans y toucher.
  /// Détection de changement ROBUSTE (empreinte de TOUS les ids) et
  /// sauvegarde disque UNIQUEMENT si changement (pas de réécriture de
  /// plusieurs Mo à chaque ouverture).
  Future<void> _refreshInBackground() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final List<VodMovie> fresh = await _fetchFromNetwork();
      if (fresh.isEmpty) return;
      final List<VodMovie> old = _cache ?? const <VodMovie>[];
      final bool changed = catalogChanged(
        <String>[for (final VodMovie m in old) m.id],
        <String>[for (final VodMovie m in fresh) m.id],
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

  /// Liste des catégories présentes dans le cache courant (Xtream + M3U).
  List<String> categories() {
    final List<VodMovie> m = <VodMovie>[
      ...?_cache,
      ...?_m3uMovies,
    ];
    final Set<String> set = <String>{for (final VodMovie v in m) v.category};
    final List<String> list = set.toList()..sort();
    return list;
  }
}
