// =========================================================
//  home_layout_repository.dart — Accueil dynamique (SDUI)
// =========================================================
//  Centre de contrôle, Module 1/8 : l'admin pilote depuis le panel
//  l'ORDRE des sections de l'accueil, leur VISIBILITÉ, un RUBAN
//  (NOUVEAU / POPULAIRE / …) et la mise en VEDETTE — sans publier de
//  nouvelle version de l'app.
//
//  Principe (server-driven UI) :
//    1. L'app a un ordre PAR DÉFAUT codé en dur (kDefaultHomeOrder).
//    2. Au démarrage, on lit la config distante /api/home-layout.
//    3. On FUSIONNE : la config distante surcharge l'ordre/visibilité/
//       ruban/vedette par clé ; les clés absentes gardent leur défaut.
//    4. On met en CACHE la dernière config valide (SharedPreferences)
//       → l'app marche hors-ligne et ne « clignote » pas au lancement.
//
//  Dégradation gracieuse : si le réseau échoue ET qu'il n'y a pas de
//  cache, on retombe sur l'ordre par défaut. L'accueil s'affiche
//  TOUJOURS. Aucune dépendance au cast.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../subscription/data/subscription_backend.dart';

/// Clés stables des sections de l'accueil. DOIVENT rester alignées avec
/// HOME_SECTION_KEYS côté serveur (api_v1.js) et avec le rendu de
/// SimpleHomeScreen.
class HomeSectionKey {
  static const String recent = 'recent';
  static const String favorites = 'favorites';
  static const String sport = 'sport';
  static const String entertainment = 'entertainment';
  static const String info = 'info';
  static const String kids = 'kids';
  static const String general = 'general';
  static const String cinema = 'cinema';
}

/// Ordre par défaut (utilisé tant que l'admin n'a rien changé / hors-ligne).
const List<String> kDefaultHomeOrder = <String>[
  HomeSectionKey.recent,
  HomeSectionKey.favorites,
  HomeSectionKey.sport,
  HomeSectionKey.entertainment,
  HomeSectionKey.info,
  HomeSectionKey.kids,
  HomeSectionKey.general,
  HomeSectionKey.cinema,
];

/// Réglage d'UNE section tel que renvoyé par le serveur. Immuable.
@immutable
class HomeSectionConfig {
  const HomeSectionConfig({
    required this.key,
    required this.position,
    required this.enabled,
    required this.ribbon,
    required this.featured,
  });

  final String key;
  final int position;
  final bool enabled;

  /// Ruban affiché en coin de section ('' = aucun).
  final String ribbon;

  /// Section mise en avant (style renforcé).
  final bool featured;

  static HomeSectionConfig? fromJson(Map<String, dynamic> j) {
    final String key = (j['key'] ?? '').toString();
    if (key.isEmpty) return null;
    int asInt(Object? v) =>
        v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
    bool asBool(Object? v) => v == true || v == 1 || v == '1';
    return HomeSectionConfig(
      key: key,
      position: asInt(j['position']),
      enabled: j['enabled'] == null ? true : asBool(j['enabled']),
      ribbon: (j['ribbon'] ?? '').toString(),
      featured: asBool(j['featured']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'position': position,
        'enabled': enabled ? 1 : 0,
        'ribbon': ribbon,
        'featured': featured ? 1 : 0,
      };
}

/// Singleton + ChangeNotifier : l'accueil écoute et se reconstruit dès
/// que la config arrive (cache puis réseau).
class HomeLayoutRepository extends ChangeNotifier {
  HomeLayoutRepository._();
  static final HomeLayoutRepository instance = HomeLayoutRepository._();

  static const String _cacheKey = 'home_layout.cache.v1';

  /// Config par clé. Vide tant que rien n'est chargé → ordre par défaut.
  Map<String, HomeSectionConfig> _byKey = <String, HomeSectionConfig>{};
  bool _initialized = false;
  Future<void>? _pending;
  int _revision = 0;

  /// Réglage d'une section, ou `null` si non piloté (→ défauts).
  HomeSectionConfig? config(String key) => _byKey[key];

  /// Charge le cache (immédiat) puis rafraîchit depuis le réseau.
  Future<void> initialize({bool strict = false}) async {
    if (!_initialized) {
      _initialized = true;
      await _loadCache();
    } else if (!strict) {
      return;
    }
    // Rafraîchissement réseau en tâche de fond (ne bloque pas l'accueil).
    if (strict) {
      await refresh(strict: true);
    } else {
      unawaited(refresh());
    }
  }

  Future<void> _loadCache() async {
    final int before = _revision;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final next = _parseItems(jsonDecode(raw));
      // Une commande distante passée pendant la lecture du disque gagne.
      if (_revision == before) _apply(next);
    } catch (e) {
      if (kDebugMode) debugPrint('[HomeLayout] cache: ${e.runtimeType}');
    }
  }

  /// Va chercher la config distante. Silencieux en cas d'échec.
  Future<void> refresh({bool strict = false}) async {
    try {
      // Une lecture partie avant l'ordre peut encore contenir l'ancienne valeur.
      // Le strict attend sa fin, puis démarre sa propre lecture après l'ordre.
      // La boucle sérialise aussi plusieurs ordres stricts sans réponse tardive.
      if (strict) {
        while (_pending != null) {
          final previous = _pending!;
          try {
            await previous;
          } catch (_) {
            // Seule la nouvelle lecture décide du succès de cet ordre.
          }
          if (identical(_pending, previous)) _pending = null;
        }
      }
      final Future<void> pending = _pending ??= _fetchAndApply();
      try {
        await pending;
      } finally {
        if (identical(_pending, pending)) _pending = null;
      }
    } catch (e) {
      if (strict) rethrow;
      if (kDebugMode) debugPrint('[HomeLayout] refresh: ${e.runtimeType}');
    }
  }

  Future<void> _fetchAndApply() async {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/home-layout'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        throw StateError('Disposition distante non confirmée');
      }
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Disposition distante invalide');
      }
      final next = _parseItems(decoded['items']);
      // Mémorise la dernière config valide.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool saved = await prefs.setString(_cacheKey,
          jsonEncode(next.values.map((item) => item.toJson()).toList()));
      if (!saved) throw StateError('Disposition non mémorisée');
      _apply(next);
  }

  Map<String, HomeSectionConfig> _parseItems(Object? list) {
    if (list is! List || list.length > 256) {
      throw const FormatException('Sections distantes invalides');
    }
    final Map<String, HomeSectionConfig> next = <String, HomeSectionConfig>{};
    for (final Object? it in list) {
      if (it is! Map<String, dynamic> || it['key'] is! String ||
          (it['key'] as String).trim().isEmpty ||
          (it['key'] as String).length > 80 ||
          (it['ribbon'] != null && it['ribbon'] is! String) ||
          (it['position'] != null &&
              int.tryParse('${it['position']}') == null)) {
        throw const FormatException('Section distante invalide');
      }
      for (final String flag in <String>['enabled', 'featured']) {
        final Object? value = it[flag];
        if (value != null && value != true && value != false &&
            value != 0 && value != 1 && value != '0' && value != '1') {
          throw const FormatException('Visibilité distante invalide');
        }
      }
      final HomeSectionConfig c = HomeSectionConfig.fromJson(it)!;
      if (next.containsKey(c.key)) {
        throw const FormatException('Section distante dupliquée');
      }
      next[c.key] = c;
    }
    return next;
  }

  void _apply(Map<String, HomeSectionConfig> next) {
    _byKey = next;
    _revision++;
    notifyListeners();
  }

  /// Renvoie les clés à AFFICHER, dans l'ordre voulu :
  ///   - les clés pilotées triées par `position` ;
  ///   - puis les clés par défaut non pilotées (sécurité : on n'en perd
  ///     jamais une nouvelle non encore connue du serveur) ;
  ///   - en retirant celles désactivées (`enabled == false`).
  List<String> orderedVisibleKeys(List<String> defaults) {
    if (_byKey.isEmpty) return List<String>.from(defaults);
    final List<HomeSectionConfig> known = _byKey.values
        .where((HomeSectionConfig c) => c.enabled)
        .toList()
      ..sort((HomeSectionConfig a, HomeSectionConfig b) =>
          a.position.compareTo(b.position));
    final List<String> result =
        known.map((HomeSectionConfig c) => c.key).toList();
    // Ajoute les clés par défaut jamais vues par le serveur (à la fin).
    for (final String k in defaults) {
      if (!_byKey.containsKey(k)) result.add(k);
    }
    return result;
  }
}
