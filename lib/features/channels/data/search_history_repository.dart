// =========================================================
//  search_history_repository.dart — Historique de recherche (TV)
// =========================================================
//  Mémorise les DERNIÈRES recherches de chaînes (max 10), pour les
//  reproposer d'un clic — pas besoin de re-taper au clavier D-pad.
//
//  Stockage : SharedPreferences (liste de chaînes de caractères). C'est
//  léger, local, et SANS aucun rapport avec le lecteur vidéo : zéro impact
//  sur la stabilité de l'image.
// =========================================================
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profiles/profiles_repository.dart';

class SearchHistoryRepository {
  SearchHistoryRepository._();
  static final SearchHistoryRepository instance = SearchHistoryRepository._();

  static const String _baseKey = 'tv_search_history';

  /// Clé PAR PROFIL (suffixe vide pour « Famille » → données historiques
  /// conservées telles quelles).
  String get _key => '$_baseKey${ProfilesRepository.instance.keySuffix}';
  static const int _max = 10;

  List<String> _items = <String>[];

  /// Les recherches, de la plus récente à la plus ancienne (lecture seule).
  List<String> get items => List<String>.unmodifiable(_items);

  /// Charge l'historique depuis le stockage local. À appeler une fois.
  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _items = prefs.getStringList(_key) ?? <String>[];
  }

  /// Ajoute une recherche en tête (dédoublonnée, insensible à la casse) et
  /// plafonne la liste à [_max] entrées.
  Future<void> add(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return;
    _items.removeWhere((String e) => e.toLowerCase() == q.toLowerCase());
    _items.insert(0, q);
    if (_items.length > _max) {
      _items = _items.sublist(0, _max);
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _items);
  }

  /// Efface tout l'historique.
  Future<void> clear() async {
    _items = <String>[];
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
