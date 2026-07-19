// =========================================================
//  hidden_categories_store.dart — Catégories MASQUÉES par le client
// =========================================================
//  Le client peut MASQUER des catégories/groupes qu'il ne veut pas voir
//  (ex. les chaînes d'un pays qui ne l'intéresse pas) SANS contacter son
//  fournisseur. Le choix est PERSISTÉ (SharedPreferences) et appliqué
//  partout où les catégories sont listées (téléphone ET TV).
//
//  On MASQUE seulement l'AFFICHAGE : rien n'est supprimé de la source. Le
//  client peut ré-afficher à tout moment (rien n'est perdu).
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HiddenCategoriesStore extends ChangeNotifier {
  HiddenCategoriesStore._();
  static final HiddenCategoriesStore instance = HiddenCategoriesStore._();

  static const String _kKey = 'category_hidden_v1';

  final Set<String> _hidden = <String>{};
  bool _loaded = false;

  /// Noms de catégories actuellement masquées (copie non modifiable).
  Set<String> get hidden => Set<String>.unmodifiable(_hidden);

  /// Nombre de catégories masquées.
  int get count => _hidden.length;

  /// `true` si [cat] est masquée.
  bool isHidden(String cat) => _hidden.contains(cat);

  /// Charge l'ensemble persisté UNE fois (idempotent, best-effort).
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _hidden
        ..clear()
        ..addAll(p.getStringList(_kKey) ?? const <String>[]);
    } catch (_) {
      _hidden.clear();
    }
    _loaded = true;
    notifyListeners();
  }

  /// Masque [cat] (idempotent) et persiste.
  Future<void> hide(String cat) async {
    if (!_hidden.add(cat)) return;
    _loaded = true;
    notifyListeners();
    await _persist();
  }

  /// Ré-affiche [cat] (idempotent) et persiste.
  Future<void> unhide(String cat) async {
    if (!_hidden.remove(cat)) return;
    notifyListeners();
    await _persist();
  }

  /// Ré-affiche TOUT.
  Future<void> clear() async {
    if (_hidden.isEmpty) return;
    _hidden.clear();
    notifyListeners();
    await _persist();
  }

  /// Retire de [items] les catégories masquées (filtre l'affichage).
  List<T> applyFilter<T>(List<T> items, String Function(T) nameOf) {
    if (_hidden.isEmpty) return items;
    return items.where((T it) => !_hidden.contains(nameOf(it))).toList();
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setStringList(_kKey, _hidden.toList());
    } catch (_) {
      // best-effort : le masquage reste appliqué en mémoire cette session.
    }
  }
}
