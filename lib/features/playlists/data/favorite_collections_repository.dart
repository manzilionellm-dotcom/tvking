// =========================================================
//  favorite_collections_repository.dart — Collections de favoris (TV)
// =========================================================
//  Permet de RANGER ses chaînes favorites par thème (« Sport », « Enfants »,
//  « Films »…), façon listes Netflix. Une collection = un nom + la liste des
//  identifiants de chaînes (external_id, le même que FavoritesRepository).
//
//  Stockage : SharedPreferences (petit JSON local). AUCUN lien avec le
//  lecteur vidéo ni avec l'écran Direct : les collections vivent dans leur
//  propre écran (cf. tv_collections_screen.dart) → zéro risque stabilité.
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/profiles/profiles_repository.dart';

/// Une collection nommée de chaînes favorites.
class FavoriteCollection {
  FavoriteCollection({required this.name, required this.ids});

  final String name;
  final List<String> ids; // external_id des chaînes, ordre d'ajout
}

class FavoriteCollectionsRepository extends ChangeNotifier {
  FavoriteCollectionsRepository._();
  static final FavoriteCollectionsRepository instance =
      FavoriteCollectionsRepository._();

  static const String _baseKey = 'tv_fav_collections';
  static const int maxCollections = 12;

  /// Clé PAR PROFIL (suffixe vide pour « Famille » → données conservées).
  String get _key => '$_baseKey${ProfilesRepository.instance.keySuffix}';

  List<FavoriteCollection> _items = <FavoriteCollection>[];

  List<FavoriteCollection> get collections =>
      List<FavoriteCollection>.unmodifiable(_items);

  /// (Re)charge les collections DU PROFIL ACTIF. Volontairement idempotent et
  /// re-jouable : un changement de profil rappelle simplement load().
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = prefs.getString(_key) ?? '[]';
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      _items = list
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> j) => FavoriteCollection(
                name: (j['name'] as String?) ?? '',
                ids: ((j['ids'] as List<dynamic>?) ?? <dynamic>[])
                    .whereType<String>()
                    .toList(growable: true),
              ))
          .where((FavoriteCollection c) => c.name.isNotEmpty)
          .toList(growable: true);
    } catch (e) {
      debugPrint('[Collections] load: $e');
      _items = <FavoriteCollection>[];
    }
    notifyListeners();
  }

  FavoriteCollection? byName(String name) {
    for (final FavoriteCollection c in _items) {
      if (c.name == name) return c;
    }
    return null;
  }

  Future<void> create(String name) async {
    final String n = name.trim();
    if (n.isEmpty || byName(n) != null) return;
    if (_items.length >= maxCollections) return;
    _items.add(FavoriteCollection(name: n, ids: <String>[]));
    await _save();
  }

  Future<void> delete(String name) async {
    _items.removeWhere((FavoriteCollection c) => c.name == name);
    await _save();
  }

  /// Ajoute/retire la chaîne [channelId] de la collection [name].
  Future<void> toggle(String name, String channelId) async {
    final FavoriteCollection? c = byName(name);
    if (c == null) return;
    if (!c.ids.remove(channelId)) c.ids.add(channelId);
    await _save();
  }

  bool contains(String name, String channelId) =>
      byName(name)?.ids.contains(channelId) ?? false;

  Future<void> _save() async {
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(_items
            .map((FavoriteCollection c) =>
                <String, Object?>{'name': c.name, 'ids': c.ids})
            .toList(growable: false)),
      );
    } catch (e) {
      debugPrint('[Collections] save: $e');
    }
  }
}
