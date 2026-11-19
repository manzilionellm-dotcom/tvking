// =========================================================
//  cinema_taste.dart — Carnet des rayons que le client ouvre
// =========================================================
//  Un petit compteur par catégorie, par profil, pour les films et
//  pour les séries. Il sert seulement à RANGER le cinéma (voir
//  cinema_shelf_order.dart). Rien ne quitte la box.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cinema_shelf_order.dart';

abstract final class CinemaTaste {
  static const String _prefix = 'zuno.cinema.taste.v1.';

  /// [kind] : « movie » ou « series ». [profileId] : « p1 », « p2 »…
  static String keyFor(String kind, String profileId) =>
      '$_prefix$kind.$profileId';

  static Map<String, int> decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final Object? data = jsonDecode(raw);
      if (data is! Map) return <String, int>{};
      final Map<String, int> out = <String, int>{};
      data.forEach((Object? k, Object? v) {
        if (k is String && k.isNotEmpty && v is int && v > 0) out[k] = v;
      });
      return out;
    } catch (_) {
      return <String, int>{};
    }
  }

  static Future<Map<String, int>> read(String kind, String profileId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return decode(prefs.getString(keyFor(kind, profileId)));
    } catch (e) {
      if (kDebugMode) debugPrint('[Cinéma] carnet illisible : $e');
      return <String, int>{};
    }
  }

  /// Compte une ouverture de titre dans [categoryKey].
  static Future<void> note(
    String kind,
    String profileId,
    String categoryKey,
  ) async {
    if (categoryKey.isEmpty) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String key = keyFor(kind, profileId);
      final Map<String, int> next =
          noteCinemaShelf(decode(prefs.getString(key)), categoryKey);
      await prefs.setString(key, jsonEncode(next));
    } catch (e) {
      if (kDebugMode) debugPrint('[Cinéma] carnet non enregistré : $e');
    }
  }

  /// Efface les carnets d'un profil supprimé.
  static Future<void> drop(String profileId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      for (final String key in prefs.getKeys().toList()) {
        if (key.startsWith(_prefix) && key.endsWith('.$profileId')) {
          await prefs.remove(key);
        }
      }
    } catch (_) {}
  }
}
