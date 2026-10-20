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

class LocaleRepository extends ChangeNotifier with WidgetsBindingObserver {
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
    Locale('fr'), // Français — premier choix manuel, pas langue par défaut
    Locale('en'), // English
    Locale('es'), // Español
    Locale('sv'), // Svenska
    Locale('da'), // Dansk
    Locale('nb'), // Norsk bokmål
    Locale('ar'), // العربية (RTL)
    Locale('sw'), // Kiswahili
    // --- Ajoutées le 25/09/2026 (Zuno TV : « toutes les langues courantes ») ---
    Locale('de'), // Deutsch
    Locale('it'), // Italiano
    Locale('pt'), // Português
    Locale('nl'), // Nederlands
    Locale('tr'), // Türkçe
    Locale('ru'), // Русский
    Locale('zh'), // 中文 (simplifié)
    Locale('hi'), // हिन्दी
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
    'de': 'Deutsch',
    'it': 'Italiano',
    'pt': 'Português',
    'nl': 'Nederlands',
    'tr': 'Türkçe',
    'ru': 'Русский',
    'zh': '中文',
    'hi': 'हिन्दी',
  };

  /// Choisit la langue de l'app à partir de celle(s) de l'OS / de la TV.
  ///
  /// Flutter ne fait par défaut qu'une correspondance simple sur la 1re
  /// locale système ; ici on parcourt TOUTES les langues préférées de la TV
  /// (ex. « pt-BR, es, en ») et on prend la première dont le CODE LANGUE est
  /// supporté (« pt-BR » → `pt`, « zh-Hant-TW » → `zh`, « nb-NO » → `nb`,
  /// « no » → `nb`). Rien ne correspond → anglais (langue la plus comprise),
  /// jamais le français par accident.
  static Locale resolve(List<Locale>? system, Iterable<Locale> supported) {
    final List<Locale> choices = supported.toList();
    assert(choices.isNotEmpty);
    for (final Locale l in system ?? const <Locale>[]) {
      final String code = _languageCode(l.languageCode);
      for (final Locale choice in choices) {
        if (choice.languageCode == code) return choice;
      }
    }
    return choices.firstWhere(
      (l) => l.languageCode == 'en',
      orElse: () => choices.first,
    );
  }

  /// Accepte aussi les anciennes valeurs « sv_SE » et « pt-BR ».
  static String _languageCode(String value) {
    final String code = value.trim().toLowerCase().split(RegExp('[-_]')).first;
    return switch (code) {
      'no' || 'nn' => 'nb',
      'iw' => 'he',
      'in' => 'id',
      _ => code,
    };
  }

  static Locale? _supportedChoice(String? value) {
    if (value == null) return null;
    final String code = _languageCode(value);
    for (final Locale choice in supportedLocales) {
      if (choice.languageCode == code) return choice;
    }
    return null; // une valeur obsolète reprend la langue de la télévision
  }

  Locale? _locale; // null = suit l'OS
  Locale? get locale => _locale;
  bool _observing = false;

  Locale get effectiveLocale =>
      _locale ??
      resolve(
        WidgetsBinding.instance.platformDispatcher.locales,
        supportedLocales,
      );

  Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_kKey);
    _locale = _supportedChoice(stored);
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = _supportedChoice(locale?.languageCode);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (_locale == null) {
      await prefs.setString(_kKey, 'system');
    } else {
      await prefs.setString(_kKey, _locale!.languageCode);
    }
    notifyListeners();
  }

  /// Flutter reconstruit les écrans ; on prévient aussi les services qui
  /// choisissent la langue du prochain programme, sans rouvrir le flux.
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_locale == null) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _locale == null)
      notifyListeners();
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
