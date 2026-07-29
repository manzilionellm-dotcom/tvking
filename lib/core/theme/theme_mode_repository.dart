// =========================================================
//  theme_mode_repository.dart — Choix Cinema / Daylight / Système
// =========================================================
//  Persiste le mode préféré dans SharedPreferences et notifie
//  les listeners (MaterialApp) quand il change. Trois modes :
//
//    - Cinema  (dark Maison Noir, défaut)
//    - Daylight (light Maison Noir)
//    - System  (suit le réglage OS)
//
//  Note : par défaut, on force Cinema Mode (pas System) — l'app
//  est conçue comme un "club privé caché" et son identité est le
//  dark. Si l'utilisateur veut suivre l'OS, il le choisit
//  explicitement dans Réglages.
// =========================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeRepository extends ChangeNotifier {
  ThemeModeRepository._();
  static final ThemeModeRepository instance = ThemeModeRepository._();

  static const String _kKey = 'theme.mode.v1';

  ThemeMode _mode = ThemeMode.dark; // Cinema par défaut
  ThemeMode get mode => _mode;

  Future<void> initialize() async {
    // Best-effort (même modèle qu'AccentController) : un échec de
    // SharedPreferences AVANT runApp ne doit JAMAIS tuer le boot —
    // on garde le défaut sûr (Cinema / dark).
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? stored = prefs.getString(_kKey);
      switch (stored) {
        case 'light':
          _mode = ThemeMode.light;
        case 'system':
          _mode = ThemeMode.system;
        case 'dark':
        default:
          _mode = ThemeMode.dark;
      }
      notifyListeners();
    } catch (_) {
      // best-effort : en cas d'échec on reste sur le défaut (Cinema).
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, _serialize(mode));
    notifyListeners();
  }

  String _serialize(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.dark:
        return 'dark';
    }
  }
}
