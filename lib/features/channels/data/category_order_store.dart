// =========================================================
//  category_order_store.dart — Ordre PERSONNALISÉ des catégories
// =========================================================
//  L'utilisateur choisit l'ordre de ses catégories (glisser pour monter /
//  descendre, ex. remonter « Français » tout en haut). Le choix est
//  PERSISTÉ (SharedPreferences) et appliqué partout où les catégories sont
//  listées (téléphone ET TV).
//
//  Les catégories NON classées par l'utilisateur gardent leur ordre par
//  défaut (par nombre de chaînes, etc.), APRÈS les catégories classées —
//  donc réordonner quelques catégories ne casse jamais l'affichage des
//  autres, et une nouvelle catégorie apparue après coup reste visible.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CategoryOrderStore extends ChangeNotifier {
  CategoryOrderStore._();
  static final CategoryOrderStore instance = CategoryOrderStore._();

  static const String _kKey = 'category_custom_order_v1';

  List<String> _order = <String>[];
  bool _loaded = false;

  /// Ordre personnalisé courant (noms de catégories), du haut vers le bas.
  List<String> get order => List<String>.unmodifiable(_order);

  /// `true` si l'utilisateur a défini un ordre (sinon : ordre par défaut).
  bool get hasCustomOrder => _order.isNotEmpty;

  /// Charge l'ordre persisté UNE fois (idempotent, best-effort).
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _order = p.getStringList(_kKey) ?? <String>[];
    } catch (_) {
      _order = <String>[];
    }
    _loaded = true;
    notifyListeners();
  }

  /// Enregistre le nouvel ordre choisi par l'utilisateur (et notifie l'UI).
  Future<void> setOrder(List<String> names) async {
    _order = List<String>.from(names);
    _loaded = true;
    notifyListeners();
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setStringList(_kKey, _order);
    } catch (_) {
      // best-effort : l'ordre reste appliqué en mémoire pour cette session.
    }
  }

  /// Remet l'ordre par défaut (efface la personnalisation).
  Future<void> reset() => setOrder(<String>[]);

  /// Applique l'ordre personnalisé à [items] : d'abord les catégories
  /// classées (dans l'ordre choisi), puis le RESTE dans son ordre d'origine.
  /// Tri STABLE (on ne mélange jamais les non classées entre elles).
  List<T> applyOrder<T>(List<T> items, String Function(T) nameOf) {
    if (_order.isEmpty) return items;
    final Map<String, int> rank = <String, int>{};
    for (int i = 0; i < _order.length; i++) {
      rank[_order[i]] = i;
    }
    final List<T> ranked = <T>[];
    final List<T> rest = <T>[];
    for (final T it in items) {
      if (rank.containsKey(nameOf(it))) {
        ranked.add(it);
      } else {
        rest.add(it);
      }
    }
    ranked.sort((T a, T b) => rank[nameOf(a)]!.compareTo(rank[nameOf(b)]!));
    return <T>[...ranked, ...rest];
  }
}
