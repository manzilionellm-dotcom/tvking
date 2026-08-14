// =========================================================
//  display_settings.dart — Réglages d'affichage TV (confort)
// =========================================================
//  Deux réglages 100 % « présentation », SANS aucun rapport avec le lecteur
//  vidéo ni le décodage (zéro impact sur la stabilité de l'image) :
//
//    • OVERSCAN : certaines TV (surtout anciennes) « rognent » les bords de
//      l'image. On ajoute une marge réglable (0 à 8 %) tout autour de l'app
//      pour que rien ne soit coupé.
//    • GRAND TEXTE : agrandit légèrement le texte (confort de lecture, utile
//      pour les seniors). Volontairement MODÉRÉ (+8 %) pour ne pas casser les
//      mises en page.
//
//  Ces réglages sont appliqués UNE SEULE FOIS à la racine (MaterialApp.builder)
//  et mémorisés en local (SharedPreferences).
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// « NUIT ROYALE » — filtre de confort nocturne. Un voile CHAUD très léger
/// (moins de lumière bleue) + une pointe de tamisage, appliqué par-dessus
/// toute l'app le soir. Zéro contact avec le décodage vidéo : c'est une
/// simple couche de couleur GPU (IgnorePointer) à la racine.
enum NightComfortMode {
  /// Jamais de filtre.
  off,

  /// Filtre actif automatiquement le soir (21 h → 7 h). Défaut.
  auto,

  /// Filtre actif en permanence.
  always,
}

class DisplaySettings extends ChangeNotifier {
  DisplaySettings._();
  static final DisplaySettings instance = DisplaySettings._();

  static const String _kOverscan = 'tv_overscan_pct';
  static const String _kBigText = 'tv_big_text';
  static const String _kNight = 'tv_night_comfort';
  static const String _kNavSounds = 'tv_nav_sounds';
  static const int maxOverscan = 8;

  int _overscanPct = 0; // 0..8
  bool _bigText = false;
  bool _navSounds = true; // clic discret à chaque cran de D-pad (défaut ON)
  NightComfortMode _night = NightComfortMode.auto;

  int get overscanPct => _overscanPct;
  bool get bigText => _bigText;

  /// Sons de navigation (ancrage sensoriel) : petit clic système à chaque
  /// déplacement du focus D-pad, comme Apple TV / TiviMate. Désactivable.
  bool get navSounds => _navSounds;

  /// « NUIT ROYALE » — filtre de confort nocturne (voir NightComfortMode).
  NightComfortMode get nightComfort => _night;

  /// Fraction de marge à appliquer de chaque côté (0.0 → 0.08).
  double get overscanFraction => _overscanPct.clamp(0, maxOverscan) / 100.0;

  /// Facteur de taille du texte (1.0 = normal, 1.08 = grand).
  double get textScale => _bigText ? 1.08 : 1.0;

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _overscanPct = (prefs.getInt(_kOverscan) ?? 0).clamp(0, maxOverscan);
    _bigText = prefs.getBool(_kBigText) ?? false;
    _navSounds = prefs.getBool(_kNavSounds) ?? true;
    final int n = prefs.getInt(_kNight) ?? NightComfortMode.auto.index;
    _night = NightComfortMode
        .values[n.clamp(0, NightComfortMode.values.length - 1)];
    notifyListeners();
  }

  Future<void> setNightComfort(NightComfortMode mode) async {
    _night = mode;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kNight, mode.index);
  }

  Future<void> setOverscan(int pct) async {
    _overscanPct = pct.clamp(0, maxOverscan);
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kOverscan, _overscanPct);
  }

  Future<void> setNavSounds(bool value) async {
    _navSounds = value;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNavSounds, value);
  }

  Future<void> setBigText(bool value) async {
    _bigText = value;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBigText, value);
  }
}
