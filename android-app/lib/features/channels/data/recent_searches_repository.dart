// =========================================================
//  recent_searches_repository.dart — 10 dernières recherches
// =========================================================
//  Petit repo singleton qui persiste les dernières requêtes de
//  recherche faites par l'utilisateur (max 10, déduppliquées,
//  triées de la plus récente à la plus ancienne).
//
//  Conçu pour alimenter la rangée "Recherches récentes" affichée
//  au-dessus du clavier dès qu'on entre dans SearchScreen.
//
//  On stocke en SharedPreferences car c'est cheap, c'est local,
//  c'est synchrone après init. Pas de DB nécessaire pour 10 strings.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/flavor/flavor.dart';

class RecentSearchesRepository extends ChangeNotifier {
  RecentSearchesRepository._();
  static final RecentSearchesRepository instance =
      RecentSearchesRepository._();

  static const String _kKey = 'search.recent.v1';
  static const int _kMaxEntries = 10;
  static const int _kMinChars = 2;

  List<String> _recent = <String>[];
  bool _ready = false;

  List<String> get current => List<String>.unmodifiable(_recent);
  bool get isReady => _ready;

  Future<void> initialize() async {
    if (_ready) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _recent = prefs.getStringList(_kKey) ?? <String>[];
    _ready = true;
    notifyListeners();
  }

  /// À appeler quand l'utilisateur lance une vraie recherche (pas
  /// à chaque keystroke). On dédupe (insensible à la casse + trim)
  /// et on garde max 10 entrées.
  Future<void> record(String query) async {
    // Mode incognito (flavor « Privé ») : pas d'historique de recherche.
    if (FlavorConfig.current.adultOnly) return;
    final String clean = query.trim();
    if (clean.length < _kMinChars) return;

    final String lower = clean.toLowerCase();
    _recent = <String>[
      clean,
      ..._recent.where((String r) => r.toLowerCase() != lower),
    ];
    if (_recent.length > _kMaxEntries) {
      _recent = _recent.sublist(0, _kMaxEntries);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String query) async {
    final String lower = query.trim().toLowerCase();
    _recent = _recent
        .where((String r) => r.toLowerCase() != lower)
        .toList();
    notifyListeners();
    await _persist();
  }

  Future<void> clearAll() async {
    _recent = <String>[];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kKey, _recent);
    } catch (e) {
      if (kDebugMode) debugPrint('[RecentSearches] persist error: $e');
    }
  }
}
