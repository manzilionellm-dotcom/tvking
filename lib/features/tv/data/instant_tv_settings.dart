// =========================================================
//  instant_tv_settings.dart — Réglage « Instant TV Mode »
// =========================================================
//  « Instant TV Mode » = au lancement de l'app TV, on relance DIRECTEMENT
//  la dernière chaîne regardée, pour donner la sensation d'une vraie télé
//  (on allume → l'image est là), pas d'une app qu'on doit naviguer.
//
//  Ce réglage rend la fonction CONFIGURABLE (exigence produit) : l'utilisateur
//  peut la couper s'il préfère arriver sur l'accueil. Persisté avec
//  shared_preferences (comme les autres réglages), donc conservé entre les
//  sessions. Défaut : ACTIVÉ (effet « premium » immédiat).
//
//  Singleton ChangeNotifier : l'écran de réglages écoute pour rafraîchir
//  l'interrupteur quand la valeur change.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InstantTvSettings extends ChangeNotifier {
  InstantTvSettings._();
  static final InstantTvSettings instance = InstantTvSettings._();

  static const String _kEnabledKey = 'tv.instant_tv.enabled.v1';

  /// Par défaut ACTIVÉ : on veut l'effet « vraie TV » dès la 1re ouverture.
  bool _enabled = true;
  bool _loaded = false;

  bool get enabled => _enabled;

  /// Charge l'état mémorisé. Idempotent et best-effort (ne plante jamais :
  /// en cas de souci on reste sur le défaut activé).
  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabledKey) ?? true;
    } catch (_) {
      // best-effort : on garde le défaut.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Active / désactive l'Instant TV Mode et persiste le choix.
  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabledKey, value);
    } catch (_) {
      // best-effort
    }
  }
}
