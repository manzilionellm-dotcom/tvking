// =========================================================
//  remote_theme_repository.dart — Thème piloté par le panel
// =========================================================
//  Récupère le thème distant (`GET /api/theme`) posé par le panel
//  « Thème » et l'applique à l'app au démarrage :
//    - nom affiché de l'app   → BrandConfig
//    - couleur d'accent (hex) → AccentController.applyCustom
//
//  Best-effort : si le réseau échoue ou que rien n'est configuré, l'app
//  garde ses défauts (BLACK7 ROYAL, braise). Le fond clair/blanc (`bg`)
//  est lu mais pas encore appliqué (l'app est conçue en sombre — étape
//  suivante). Aucune dépendance au cast.
// =========================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/branding/brand_config.dart';
import '../../../core/theme/accent_controller.dart';
import '../../subscription/data/subscription_backend.dart';

abstract final class RemoteThemeRepository {
  /// Récupère le thème distant et l'applique (nom + couleur d'accent).
  static Future<void> fetchAndApply() async {
    try {
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/theme'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map) return;

      // Nom affiché ('' = on garde le nom du flavor).
      final String name = (decoded['appName'] ?? '').toString();
      BrandConfig.instance.setOverrideName(name);

      // Couleur d'accent (#RRGGBB). Invalide/vide = on garde la braise.
      final Color? accent = _parseHex((decoded['accent'] ?? '').toString());
      if (accent != null) {
        AccentController.instance.applyCustom(accent);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteTheme] $e');
    }
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
