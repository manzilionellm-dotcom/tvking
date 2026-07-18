// =========================================================
//  vod_novelty_service.dart — « Nouveautés » du catalogue (Cinéma)
// =========================================================
//  POURQUOI (recherche rétention 2026-07-17) : la raison n°1 de ROUVRIR
//  une plateforme chaque jour, c'est « qu'est-ce qu'il y a de NOUVEAU ? ».
//  Ce service repère, en LOCAL, les films et séries APPARUS depuis la
//  dernière visite du client — sans rien demander à un service tiers, sans
//  contenu ajouté : on compare juste les IDENTIFIANTS du catalogue de SA
//  source à ce qu'on avait déjà vu.
//
//  COMMENT (robuste, anti-« tout est nouveau ») :
//   • On garde un dictionnaire { id → date de première apparition } dans
//     SharedPreferences, PAR PROFIL (comme le reste du Cinéma).
//   • PREMIÈRE utilisation (dictionnaire vide) : on enregistre TOUT le
//     catalogue actuel comme « déjà connu » (date 0) → aucune fausse
//     rangée « 900 nouveautés » au premier lancement.
//   • Ensuite, un id absent du dictionnaire = VRAIE nouveauté : on
//     l'enregistre avec la date du jour. Il reste « nouveau » pendant
//     [kFreshWindow] (14 j), puis rejoint le fond de catalogue.
//
//  Best-effort absolu : tout est try/catch. En cas de souci, la liste des
//  nouveautés est simplement vide — l'accueil s'affiche normalement.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profiles/profiles_repository.dart';

class VodNoveltyService {
  VodNoveltyService._();
  static final VodNoveltyService instance = VodNoveltyService._();

  /// Durée pendant laquelle un contenu reste « nouveau » après sa première
  /// apparition dans le catalogue de la source.
  static const Duration kFreshWindow = Duration(days: 14);

  static const String _movieBase = 'vod_novelty_movies.v1';
  static const String _seriesBase = 'vod_novelty_series.v1';

  String get _movieKey => '$_movieBase${ProfilesRepository.instance.keySuffix}';
  String get _seriesKey =>
      '$_seriesBase${ProfilesRepository.instance.keySuffix}';

  // id → epochMs de première apparition. 0 = ligne de base (déjà connu au
  // premier lancement, donc jamais affiché comme « nouveau »).
  final Map<String, int> _movieFirstSeen = <String, int>{};
  final Map<String, int> _seriesFirstSeen = <String, int>{};
  bool _movieLoaded = false;
  bool _seriesLoaded = false;

  // ---- FILMS -------------------------------------------------------------

  /// Réconcilie le catalogue films avec l'historique de nouveauté, en
  /// utilisant [nowMs] comme horloge (injecté → testable, pas de Date.now
  /// caché). Renvoie les ids considérés NOUVEAUX (apparus dans la fenêtre
  /// fraîche). Persiste le dictionnaire mis à jour.
  Future<Set<String>> reconcileMovies(
    Iterable<String> catalogIds, {
    required int nowMs,
  }) async {
    await _ensureMoviesLoaded();
    return _reconcile(_movieFirstSeen, catalogIds, nowMs: nowMs, save: _saveMovies);
  }

  /// Version synchrone pure — pour l'UI qui a déjà les ids en cache et veut
  /// juste savoir lesquels sont neufs (sans re-persister). À utiliser APRÈS
  /// un reconcileMovies (qui, lui, met à jour le dictionnaire).
  Set<String> freshMovieIds({required int nowMs}) =>
      _freshWithin(_movieFirstSeen, nowMs: nowMs);

  Future<void> _ensureMoviesLoaded() async {
    if (_movieLoaded) return;
    _movieLoaded = true;
    await _load(_movieKey, _movieFirstSeen);
  }

  Future<void> _saveMovies() => _save(_movieKey, _movieFirstSeen);

  // ---- SÉRIES ------------------------------------------------------------

  Future<Set<String>> reconcileSeries(
    Iterable<String> catalogIds, {
    required int nowMs,
  }) async {
    await _ensureSeriesLoaded();
    return _reconcile(_seriesFirstSeen, catalogIds,
        nowMs: nowMs, save: _saveSeries);
  }

  Set<String> freshSeriesIds({required int nowMs}) =>
      _freshWithin(_seriesFirstSeen, nowMs: nowMs);

  Future<void> _ensureSeriesLoaded() async {
    if (_seriesLoaded) return;
    _seriesLoaded = true;
    await _load(_seriesKey, _seriesFirstSeen);
  }

  Future<void> _saveSeries() => _save(_seriesKey, _seriesFirstSeen);

  // ---- cœur PUR (testable) ----------------------------------------------

  /// Logique de réconciliation, extraite et statique pour les tests :
  ///  • dictionnaire vide → ligne de base (tout à 0, rien de neuf) ;
  ///  • id inconnu → enregistré à [nowMs] (nouveauté) ;
  ///  • purge des ids DISPARUS du catalogue (source qui retire un film) ;
  ///  • renvoie les ids « frais » (première apparition dans la fenêtre).
  @visibleForTesting
  static Set<String> reconcilePure(
    Map<String, int> firstSeen,
    Iterable<String> catalogIds, {
    required int nowMs,
  }) {
    final Set<String> ids = catalogIds.toSet();
    final bool baseline = firstSeen.isEmpty;
    // Purge des disparus (garde le dictionnaire borné à la taille du
    // catalogue réel — une source qui tourne ne fait pas fuir la mémoire).
    firstSeen.removeWhere((String id, _) => !ids.contains(id));
    for (final String id in ids) {
      if (firstSeen.containsKey(id)) continue;
      firstSeen[id] = baseline ? 0 : nowMs;
    }
    return _freshWithinStatic(firstSeen, nowMs: nowMs);
  }

  static Set<String> _freshWithinStatic(
    Map<String, int> firstSeen, {
    required int nowMs,
  }) {
    final int cutoff = nowMs - kFreshWindow.inMilliseconds;
    return <String>{
      for (final MapEntry<String, int> e in firstSeen.entries)
        if (e.value > 0 && e.value >= cutoff) e.key,
    };
  }

  Set<String> _freshWithin(Map<String, int> firstSeen, {required int nowMs}) =>
      _freshWithinStatic(firstSeen, nowMs: nowMs);

  Future<Set<String>> _reconcile(
    Map<String, int> firstSeen,
    Iterable<String> catalogIds, {
    required int nowMs,
    required Future<void> Function() save,
  }) async {
    try {
      final Set<String> fresh =
          reconcilePure(firstSeen, catalogIds, nowMs: nowMs);
      await save();
      return fresh;
    } catch (e) {
      debugPrint('[Novelty] reconcile: $e');
      return <String>{};
    }
  }

  Future<void> _load(String key, Map<String, int> into) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = prefs.getString(key) ?? '{}';
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      into.clear();
      j.forEach((String id, Object? v) {
        final int? ms = (v as num?)?.toInt();
        if (ms != null) into[id] = ms;
      });
    } catch (e) {
      debugPrint('[Novelty] load $key: $e');
    }
  }

  Future<void> _save(String key, Map<String, int> from) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(from));
    } catch (e) {
      debugPrint('[Novelty] save $key: $e');
    }
  }
}
