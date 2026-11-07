import '../../../core/theme/remote_palette.dart';
// =========================================================
//  remote_theme_repository.dart — Thème piloté par le panel
// =========================================================
//  Récupère le thème distant (`GET /api/theme`) posé par le panel
//  « Thème » et l'applique à l'app au démarrage :
//    - nom affiché de l'app   → BrandConfig
//    - fond clair/sombre + accent → palette mobile et TV, sans remonter les écrans
//
//  Best-effort : si le réseau échoue ou que rien n'est configuré, l'app
//  conserve le dernier thème valide en cache ; le choix local reste
//  disponible lorsque l'admin efface l'accent distant. Aucune dépendance au cast.
// =========================================================

import 'dart:convert';
import '../../../core/network/api_config.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app/app_platform.dart';
import '../../../core/branding/brand_config.dart';
import '../../subscription/data/subscription_backend.dart';

abstract final class RemoteThemeRepository {
  static String get _cacheKey => 'remote_theme.${AppPlatform.id}.v1';
  static Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString(_cacheKey);
      if (cached != null) {
        final Object? data = jsonDecode(cached);
        if (data is Map) applySnapshot(data);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteTheme] cache: $e');
    }
    await fetchAndApply();
  }

  /// Récupère le thème distant et l'applique (nom + couleur d'accent).
  static Future<void> fetchAndApply() async {
    try {
      // Thème PAR PLATEFORME : le mobile lit le thème mobile, DeFew TV
      // lit le thème TV (?platform=tv).
      final http.Response resp = await http
          .get(
              Uri.parse(
                  '$kSubscriptionBaseUrl/api/theme?platform=${AppPlatform.id}'),
              headers: kNoCacheHeaders)
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map) return;

      applySnapshot(decoded);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(decoded));
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteTheme] $e');
    }
  }

  /// Validated snapshot ingestion shared by network and offline restore.
  static void applySnapshot(Map<dynamic, dynamic> data) {
    // Nom affiché ('' = on garde le nom du flavor).
    final String name = (data['appName'] ?? '').toString();
    BrandConfig.instance.setOverrideName(name);

    // Couleur d'accent (#RRGGBB). Invalide/vide = on garde la braise.
    final Color? accent = _parseHex((data['accent'] ?? '').toString());
    RemotePalette.instance
        .apply(background: (data['bg'] ?? 'dark').toString(), accent: accent);
  }

  /// Parse un hex `#RRGGBB` (ou `RRGGBB`) en Color opaque. `null` si invalide.
  static Color? _parseHex(String hex) {
    String h = hex.trim();
    if (h.isEmpty) return null;
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length != 6) return null;
    final int? v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
}
