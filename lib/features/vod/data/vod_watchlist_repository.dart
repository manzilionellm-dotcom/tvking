// =========================================================
//  vod_watchlist_repository.dart — « Ma Liste » (TV, façon Netflix)
// =========================================================
//  La liste PERSONNELLE de films à voir plus tard, propre à chaque PROFIL
//  (comme « Ma Liste » de Netflix). L'utilisateur ajoute/retire un film ;
//  il réapparaît en première rangée de l'onglet Films.
//
//  Stockage : SharedPreferences (petite liste JSON locale), clé SUFFIXÉE
//  par profil (vide pour « Famille » → aucune migration). AUCUN lien avec
//  le lecteur vidéo. Zéro risque stabilité.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profiles/profiles_repository.dart';
import '../domain/vod_movie.dart';

class VodWatchlistRepository extends ChangeNotifier {
  VodWatchlistRepository._();
  static final VodWatchlistRepository instance = VodWatchlistRepository._();

  static const String _baseKey = 'tv_watchlist_vod';

  /// Clé PAR PROFIL (suffixe vide pour « Famille » → données conservées).
  String get _key => '$_baseKey${ProfilesRepository.instance.keySuffix}';
  static const int _max = 60;

  List<VodMovie> _items = <VodMovie>[];

  /// Films de « Ma Liste », du plus récent ajout au plus ancien.
  List<VodMovie> get items => List<VodMovie>.unmodifiable(_items);

  bool contains(String id) => _items.any((VodMovie e) => e.id == id);

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> raw = prefs.getStringList(_key) ?? <String>[];
      _items = raw.map(_decode).whereType<VodMovie>().toList(growable: true);
    } catch (e) {
      // Best-effort : une entrée corrompue ne casse jamais l'écran.
      debugPrint('[Watchlist] load: $e');
      _items = <VodMovie>[];
    }
    notifyListeners();
  }

  /// Ajoute [m] s'il n'y est pas, sinon le retire. Renvoie l'état final
  /// (`true` = maintenant dans la liste).
  Future<bool> toggle(VodMovie m) async {
    final bool present = contains(m.id);
    if (present) {
      _items.removeWhere((VodMovie e) => e.id == m.id);
    } else {
      _items.insert(0, m);
      if (_items.length > _max) _items = _items.sublist(0, _max);
    }
    await _save();
    return !present;
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _key, _items.map(_encode).toList(growable: false));
    } catch (e) {
      debugPrint('[Watchlist] save: $e');
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
