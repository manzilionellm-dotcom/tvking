// =========================================================
//  country_history_repository.dart — "Vos pays" (récents)
// =========================================================
//  Mémorise les derniers pays ouverts par l'utilisateur (codes ISO),
//  du plus récent au plus ancien, persistés localement. Sert à la
//  rangée "Vos pays" épinglée en haut de l'écran "Choisis un pays" :
//  pour ceux qui ne cherchent pas, ils retapent direct leur pays.
//
//  ChangeNotifier → l'écran se met à jour tout seul. getRecentCountries
//  est l'unique point de lecture (facile à remplacer plus tard).
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CountryHistoryRepository extends ChangeNotifier {
  CountryHistoryRepository._();
  static final CountryHistoryRepository instance = CountryHistoryRepository._();

  static const String _kKey = 'country.history.v1';
  static const int _kMax = 8;

  List<String> _recent = <String>[];
  bool _initialized = false;

  /// Codes pays récemment ouverts (plus récent en premier).
  List<String> getRecentCountries() => List<String>.unmodifiable(_recent);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _recent = p.getStringList(_kKey) ?? <String>[];
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[CountryHistory] load: $e');
    }
  }

  /// Enregistre l'ouverture d'un pays : passe en tête, dédupe, plafonne.
  Future<void> record(String code) async {
    if (code.isEmpty) return;
    _recent.remove(code);
    _recent.insert(0, code);
    if (_recent.length > _kMax) {
      _recent = _recent.sublist(0, _kMax);
    }
    notifyListeners();
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setStringList(_kKey, _recent);
    } catch (_) {/* best-effort */}
  }
}
