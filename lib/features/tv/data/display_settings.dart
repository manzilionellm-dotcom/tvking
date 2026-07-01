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

class DisplaySettings extends ChangeNotifier {
  DisplaySettings._();
  static final DisplaySettings instance = DisplaySettings._();

  static const String _kOverscan = 'tv_overscan_pct';
  static const String _kBigText = 'tv_big_text';
  static const int maxOverscan = 8;

  int _overscanPct = 0; // 0..8
  bool _bigText = false;

  int get overscanPct => _overscanPct;
  bool get bigText => _bigText;

  /// Fraction de marge à appliquer de chaque côté (0.0 → 0.08).
  double get overscanFraction => _overscanPct.clamp(0, maxOverscan) / 100.0;

  /// Facteur de taille du texte (1.0 = normal, 1.08 = grand).
  double get textScale => _bigText ? 1.08 : 1.0;

  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _overscanPct = (prefs.getInt(_kOverscan) ?? 0).clamp(0, maxOverscan);
    _bigText = prefs.getBool(_kBigText) ?? false;
    notifyListeners();
  }

  Future<void> setOverscan(int pct) async {
    _overscanPct = pct.clamp(0, maxOverscan);
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kOverscan, _overscanPct);
  }

  Future<void> setBigText(bool value) async {
    _bigText = value;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBigText, value);
  }
}
