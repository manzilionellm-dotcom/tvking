// =========================================================
//  recent_vod_repository.dart — « Derniers films vus » (TV)
// =========================================================
//  Mémorise les derniers FILMS ouverts (max 12) pour les reproposer en
//  première rangée de l'onglet Films, façon Netflix (« Revoir »).
//
//  Stockage : SharedPreferences (une petite liste JSON locale). AUCUN lien
//  avec le lecteur vidéo : on note simplement « ce film a été ouvert »
//  au moment où l'utilisateur lance la lecture. Zéro risque stabilité.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vod_movie.dart';

class RecentVodRepository {
  RecentVodRepository._();
  static final RecentVodRepository instance = RecentVodRepository._();

  static const String _key = 'tv_recent_vod';
  static const int _max = 12;

  List<VodMovie> _items = <VodMovie>[];

  /// Derniers films ouverts, du plus récent au plus ancien.
  List<VodMovie> get items => List<VodMovie>.unmodifiable(_items);

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> raw = prefs.getStringList(_key) ?? <String>[];
      _items = raw
          .map(_decode)
          .whereType<VodMovie>()
          .toList(growable: true);
    } catch (e) {
      // Best-effort : une entrée corrompue ne doit jamais casser l'écran.
      debugPrint('[RecentVod] load: $e');
      _items = <VodMovie>[];
    }
  }

  Future<void> add(VodMovie m) async {
    _items.removeWhere((VodMovie e) => e.id == m.id);
    _items.insert(0, m);
    if (_items.length > _max) _items = _items.sublist(0, _max);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _key, _items.map(_encode).toList(growable: false));
    } catch (e) {
      debugPrint('[RecentVod] save: $e');
    }
  }

  String _encode(VodMovie m) => jsonEncode(<String, Object?>{
        'id': m.id,
        'name': m.name,
        'category': m.category,
        'streamUrl': m.streamUrl,
        'containerExt': m.containerExt,
        'posterUrl': m.posterUrl,
        'rating': m.rating,
        'year': m.year,
      });

  VodMovie? _decode(String s) {
    try {
      final Map<String, dynamic> j = jsonDecode(s) as Map<String, dynamic>;
      return VodMovie(
        id: j['id'] as String,
        name: j['name'] as String,
        category: (j['category'] as String?) ?? '',
        streamUrl: j['streamUrl'] as String,
        containerExt: (j['containerExt'] as String?) ?? 'mp4',
        posterUrl: j['posterUrl'] as String?,
        rating: j['rating'] as String?,
        year: j['year'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
