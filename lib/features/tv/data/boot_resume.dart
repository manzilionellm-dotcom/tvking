// =========================================================
//  boot_resume.dart — Reprise au démarrage (n°2)
// =========================================================
//  Réglage TV « Reprise au démarrage » : quand il est ACTIVÉ, l'app
//  rouvre directement le lecteur sur la DERNIÈRE chaîne regardée dès
//  l'ouverture (une box de salon se comporte alors comme une vraie TV :
//  on l'allume, la chaîne d'hier est déjà là). DÉSACTIVÉ par défaut :
//  l'accueil reste le comportement historique — c'est un choix,
//  jamais une surprise.
//
//  Le déclenchement (une seule fois par démarrage, après le TvGate et
//  le choix de profil, chaînes chargées) vit dans tv_app.dart ; ici on
//  ne garde que l'état persisté, sur le modèle de DisplaySettings.
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BootResume extends ChangeNotifier {
  BootResume._();
  static final BootResume instance = BootResume._();

  static const String _kKey = 'tv.boot_resume.v1';

  bool _enabled = false;
  bool _loaded = false;

  bool get enabled => _enabled;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kKey) ?? false;
      notifyListeners();
    } catch (_) {
      // best-effort : prefs illisibles → réglage par défaut (désactivé).
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kKey, value);
    } catch (_) {
      // best-effort
    }
  }
}
