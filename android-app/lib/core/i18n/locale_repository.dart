// =========================================================
//  locale_repository.dart — Choix de langue de l'app
// =========================================================
//  Persiste la langue préférée dans SharedPreferences et notifie
//  les listeners (MaterialApp) à chaque changement.
//
//  Valeurs spéciales :
//    - null = "Système" (l'app suit la langue de l'OS)
//    - Locale(...) = forçage explicite
//
//  Les langues supportées sont déclarées dans `supportedLocales`
//  ci-dessous. Pour ajouter une langue : créer un `app_<code>.arb`
//  dans `lib/l10n/` puis ajouter la Locale ici. Le générateur
//  gen-l10n s'occupe du reste.
// =========================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleRepository extends ChangeNotifier {
  LocaleRepository._();
  static final LocaleRepository instance = LocaleRepository._();

  static const String _kKey = 'app.locale.v1';

  /// Liste maître des langues qu'on supporte. Ordre = ordre
  /// d'affichage dans le picker de Réglages.
  ///
  /// Note : `nb` = norvégien bokmål (le plus courant des deux
  /// standards écrits du norvégien). `sw` = swahili. `ar` est
  /// rendu en RTL automatiquement par Flutter via `Directionality`.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('fr'), // Français — défaut
    Locale('en'), // English
    Locale('es'), // Español
    Locale('sv'), // Svenska
    Locale('da'), // Dansk
    Locale('nb'), // Norsk bokmål
    Locale('ar'), // العربية (RTL)
    Locale('sw'), // Kiswahili
  ];

  /// Label humain pour le picker — affiché dans la langue native
  /// (jamais traduit), pour que chaque user reconnaisse sa langue
  /// même s'il a l'app dans une langue qu'il ne lit pas.
  static const Map<String, String> localeLabels = <String, String>{
    'fr': 'Français',
    'en': 'English',
    'es': 'Español',
    'sv': 'Svenska',
    'da': 'Dansk',
    'nb': 'Norsk',
    'ar': 'العربية',
    'sw': 'Kiswahili',
  };

  Locale? _locale; // null = suit l'OS
  Locale? get locale => _locale;

  Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_kKey);
    if (stored == null || stored.isEmpty || stored == 'system') {
      _locale = null;
    } else {
      _locale = Locale(stored);
    }
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.setString(_kKey, 'system');
    } else {
      await prefs.setString(_kKey, locale.languageCode);
    }
    notifyListeners();
  }
}
