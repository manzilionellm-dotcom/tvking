// =========================================================
//  parental_controls.dart — Contrôle parental & Mode Enfants
// =========================================================
//  Fonctionnalité « premium famille » (comme Netflix Kids / Disney+ Junior) :
//  un MODE ENFANTS qui masque automatiquement tout le contenu Adulte, protégé
//  par le code PIN à 4 chiffres de l'app (AppPinSettings). Un enfant ne peut
//  donc pas le désactiver lui-même.
//
//  Tout est LOCAL (SharedPreferences) — aucune dépendance réseau, aucun impact
//  sur le lecteur vidéo. Par défaut TOUT est désactivé : le comportement de
//  l'app ne change pour personne tant que le parent n'active pas le mode.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParentalControls {
  ParentalControls._();
  static final ParentalControls instance = ParentalControls._();

  static const String _kKidsMode = 'security.kids_mode.v1';

  /// État du Mode Enfants, OBSERVABLE : les écrans (ex. Direct) écoutent ce
  /// notifier pour se re-filtrer instantanément quand le parent bascule.
  /// Défaut : false (rien de masqué).
  final ValueNotifier<bool> kidsMode = ValueNotifier<bool>(false);

  bool _loaded = false;

  /// Charge l'état mémorisé. Idempotent, best-effort (ne plante jamais).
  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      kidsMode.value = prefs.getBool(_kKidsMode) ?? false;
    } catch (_) {
      // best-effort : en cas de souci, on reste sur les défauts (désactivé).
    }
    _loaded = true;
  }

  /// Active / désactive le Mode Enfants et persiste le choix.
  Future<void> setKidsMode(bool value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kKidsMode, value);
    } catch (_) {
      // best-effort
    }
    kidsMode.value = value;
  }
}
