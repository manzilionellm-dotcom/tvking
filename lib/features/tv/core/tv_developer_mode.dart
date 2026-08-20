// =========================================================
//  tv_developer_mode.dart — Mode « Développeur » (caché)
// =========================================================
//  Décision propriétaire (21/08/2026) : l'app TV ne présente plus QU'UN
//  seul modèle d'accueil (le Modèle D, panneau façon TiviMate). Le choix
//  A/B/C/D reste dans le code mais n'est accessible qu'en mode
//  Développeur — pour « les gens qui exigent tout », jamais mis en avant.
//
//  ACTIVATION (volontairement cachée) : appui LONG sur « À propos » dans
//  les Réglages TV. Même geste pour désactiver. Persisté par appareil.
//
//  Quand le mode est INACTIF (défaut), TvHomeTemplateRepository force le
//  Modèle D quel que soit le choix mémorisé — le choix n'est PAS effacé :
//  réactiver le mode le restitue tel quel.
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tv_home_template.dart';

class TvDeveloperMode extends ChangeNotifier {
  TvDeveloperMode._();
  static final TvDeveloperMode instance = TvDeveloperMode._();

  static const String _kKey = 'tv.developer.mode.v1';

  bool _enabled = false;
  bool get enabled => _enabled;

  /// À appeler UNE fois au boot, AVANT TvHomeTemplateRepository.initialize
  /// (le template effectif dépend de ce drapeau).
  Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kKey) ?? false;
    } catch (_) {
      _enabled = false; // défaut SÛR : template unique
    }
    notifyListeners();
  }

  /// Bascule le mode et réaligne la home + l'univers de favoris sur le
  /// template effectif (forcé D quand off, choix mémorisé quand on).
  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kKey, value);
    } catch (_) {
      // Best-effort : le mode reste actif en mémoire même si l'écriture rate.
    }
    // La home et les favoris suivent le template EFFECTIF, qui vient de
    // changer potentiellement (D forcé ↔ choix mémorisé).
    await TvHomeTemplateRepository.instance.onDeveloperModeChanged();
  }
}
