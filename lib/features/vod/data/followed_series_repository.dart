// =========================================================
//  followed_series_repository.dart — « Vos séries » + nouveaux épisodes
// =========================================================
//  POURQUOI (recherche rétention 2026-07-17) : pour les SÉRIES, le moteur
//  de retour n°1 c'est « un nouvel épisode est dispo ». On le détecte en
//  LOCAL, à partir de la source du client, sans service tiers :
//
//   1. Dès que le client OUVRE une fiche série, on la « suit » et on
//      mémorise son nombre d'épisodes du moment (name, poster, count).
//   2. Plus tard, un rafraîchissement DISCRET (à l'ouverture de l'onglet
//      Séries, JAMAIS pendant une lecture) re-demande le nombre d'épisodes
//      des séries suivies, une par une, throttlé. Si le compte a AUGMENTÉ,
//      la série est marquée « nouveaux épisodes » → rangée dédiée + badge.
//   3. Rouvrir la fiche remet le compteur à jour et efface le drapeau.
//
//  Courtoisie réseau (comptes 1-connexion) : le rafraîchissement est
//  SÉRIEL (une série à la fois), plafonné par passage, et l'appelant ne le
//  lance qu'hors lecture. Best-effort : tout échec est silencieux.
//
//  Stockage : SharedPreferences JSON, PAR PROFIL (comme le reste du Cinéma).
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profiles/profiles_repository.dart';

/// Une série suivie + l'état « nouveaux épisodes ».
class FollowedSeries {
  FollowedSeries({
    required this.id,
    required this.name,
    this.posterUrl,
    this.category = '',
    this.episodeCount = 0,
    this.hasNew = false,
    this.lastCheckedMs = 0,
  });

  final String id;
  final String name;
  final String? posterUrl;
  final String category;
  int episodeCount;
  bool hasNew;
  int lastCheckedMs;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'posterUrl': posterUrl,
        'category': category,
        'episodeCount': episodeCount,
        'hasNew': hasNew,
        'lastCheckedMs': lastCheckedMs,
      };

  factory FollowedSeries.fromJson(Map<String, dynamic> j) => FollowedSeries(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        posterUrl: j['posterUrl'] as String?,
        category: (j['category'] as String?) ?? '',
        episodeCount: (j['episodeCount'] as num?)?.toInt() ?? 0,
        hasNew: (j['hasNew'] as bool?) ?? false,
        lastCheckedMs: (j['lastCheckedMs'] as num?)?.toInt() ?? 0,
      );
}

class FollowedSeriesRepository extends ChangeNotifier {
  FollowedSeriesRepository._();
  static final FollowedSeriesRepository instance =
      FollowedSeriesRepository._();

  static const String _baseKey = 'vod_followed_series.v1';
  static const int _max = 60; // borne mémoire/stockage

  /// Ne re-vérifie pas une série plus d'une fois toutes les 6 h (économie
  /// réseau — les catalogues ne bougent pas toutes les minutes).
  static const Duration kRecheckAfter = Duration(hours: 6);

  /// Nombre max de séries re-vérifiées par ouverture de l'onglet (courtoisie
  /// 1-connexion : on étale dans le temps plutôt que rafaler la source).
  static const int kMaxRefreshPerPass = 6;

  String get _key => '$_baseKey${ProfilesRepository.instance.keySuffix}';

  final Map<String, FollowedSeries> _items = <String, FollowedSeries>{};
  bool _loaded = false;
  bool _refreshing = false;

  List<FollowedSeries> get all => _items.values.toList(growable: false);

  /// Séries suivies ayant de nouveaux épisodes (les plus récentes d'abord
  /// n'a pas de sens ici : ordre d'insertion, suffisant).
  List<FollowedSeries> get withNewEpisodes =>
      _items.values.where((FollowedSeries s) => s.hasNew).toList();

  bool hasNew(String id) => _items[id]?.hasNew ?? false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = prefs.getString(_key) ?? '[]';
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      _items.clear();
      for (final dynamic e in list) {
        if (e is Map<String, dynamic>) {
          final FollowedSeries s = FollowedSeries.fromJson(e);
          _items[s.id] = s;
        }
      }
    } catch (e) {
      debugPrint('[FollowedSeries] load: $e');
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // Borne : on garde les plus récemment vérifiées.
      final List<FollowedSeries> items = _items.values.toList()
        ..sort((FollowedSeries a, FollowedSeries b) =>
            b.lastCheckedMs.compareTo(a.lastCheckedMs));
      final List<FollowedSeries> kept = items.take(_max).toList();
      await prefs.setString(
          _key, jsonEncode(kept.map((FollowedSeries s) => s.toJson()).toList()));
    } catch (e) {
      debugPrint('[FollowedSeries] persist: $e');
    }
  }

  /// Le client ouvre une fiche série → on la suit et on cale le compteur
  /// d'épisodes sur la valeur du moment (donc aucun « faux nouveau » : ce
  /// qu'il vient de voir est la référence). Efface tout drapeau « nouveau ».
  Future<void> markOpened({
    required String id,
    required String name,
    String? posterUrl,
    String category = '',
    required int episodeCount,
    required int nowMs,
  }) async {
    await load();
    final FollowedSeries s = _items[id] ??
        FollowedSeries(id: id, name: name, posterUrl: posterUrl,
            category: category);
    s.episodeCount = episodeCount;
    s.hasNew = false;
    s.lastCheckedMs = nowMs;
    _items[id] = s;
    notifyListeners();
    await _persist();
  }

  /// RÉCONCILIATION discrète : pour chaque série suivie « périmée » (non
  /// vérifiée depuis kRecheckAfter), demande le nombre d'épisodes courant
  /// via [episodeCountOf] (fourni par l'appelant → aucune dépendance réseau
  /// ici, donc testable). Marque « nouveau » si le compte a augmenté.
  /// Plafonné et séquentiel (courtoisie 1-connexion).
  Future<void> refreshStale({
    required Future<int?> Function(String seriesId) episodeCountOf,
    required int nowMs,
    int maxPass = kMaxRefreshPerPass,
  }) async {
    await load();
    if (_refreshing) return;
    _refreshing = true;
    try {
      final List<FollowedSeries> stale = _items.values
          .where((FollowedSeries s) =>
              nowMs - s.lastCheckedMs >= kRecheckAfter.inMilliseconds)
          .take(maxPass)
          .toList();
      bool changed = false;
      for (final FollowedSeries s in stale) {
        final int? count = await episodeCountOf(s.id);
        s.lastCheckedMs = nowMs;
        if (count != null && count > 0) {
          // Nouveau seulement si on avait DÉJÀ un compte de référence
          // (>0) et qu'il a grandi — jamais au tout premier relevé.
          if (s.episodeCount > 0 && count > s.episodeCount) {
            s.hasNew = true;
          }
          s.episodeCount = count;
          changed = true;
        }
      }
      if (changed) {
        notifyListeners();
        await _persist();
      }
    } catch (e) {
      debugPrint('[FollowedSeries] refresh: $e');
    } finally {
      _refreshing = false;
    }
  }

  /// Efface le drapeau « nouveaux épisodes » (série ouverte / vue).
  Future<void> clearNew(String id) async {
    final FollowedSeries? s = _items[id];
    if (s == null || !s.hasNew) return;
    s.hasNew = false;
    notifyListeners();
    await _persist();
  }
}
