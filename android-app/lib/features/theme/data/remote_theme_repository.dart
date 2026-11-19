// =========================================================
//  remote_theme_repository.dart — Thème piloté par le panel
// =========================================================
//  Récupère le thème distant (`GET /api/theme`) posé par le panel
//  « Thème » et l'applique à l'app au démarrage :
//    - nom affiché de l'app   → BrandConfig
//    - couleur d'accent (hex) → AccentController.applyCustom
//
//  Best-effort : si le réseau échoue ou que rien n'est configuré, l'app
//  garde le dernier thème valide. Les parcours TV utilisent désormais la
//  palette contextuelle (clair/sombre compris), sans recolorer le Cast.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/app/app_platform.dart';
import '../../../core/branding/brand_config.dart';
import '../../../core/theme/accent_controller.dart';
import '../../../core/theme/remote_theme_settings.dart';
import '../../../core/theme/theme_mode_repository.dart';
import '../../subscription/data/subscription_backend.dart';

abstract final class RemoteThemeRepository {
  static final ValueNotifier<RemoteThemeSettings> current =
      ValueNotifier<RemoteThemeSettings>(const RemoteThemeSettings());
  static int _request = 0;

  /// Récupère le thème distant. Une réponse ancienne ne peut pas annuler
  /// une modification plus récente reçue sur le canal du panel.
  static Future<void> fetchAndApply({bool strict = false}) async {
    final request = ++_request;
    try {
      // Thème PAR PLATEFORME : le mobile lit le thème mobile, DeFew TV
      // lit le thème TV (?platform=tv).
      final http.Response resp = await http
          .get(
            Uri.parse(
              '$kSubscriptionBaseUrl/api/theme?platform=${AppPlatform.id}',
            ),
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200)
        throw StateError('theme_http_${resp.statusCode}');
      if (request != _request) throw StateError('theme_request_superseded');
      final Object? decoded = jsonDecode(resp.body);
      final settings = RemoteThemeSettings.parse(decoded);
      if (settings == null)
        throw const FormatException('Invalid theme response');
      BrandConfig.instance.setOverrideName(settings.appName);
      if (settings.accent case final accent?) {
        AccentController.instance.applyCustom(accent);
      } else {
        AccentController.instance.clearCustom();
      }
      ThemeModeRepository.instance.applyRemoteMode(settings.mode);
      current.value = settings;
    } catch (e) {
      if (strict) rethrow;
      if (kDebugMode) debugPrint('[RemoteTheme] $e');
    }
  }
}
