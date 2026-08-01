// =========================================================
//  low_connection_mode.dart — Mode connexion faible (n°37)
// =========================================================
//  Réglage TV opt-in pour les foyers à petit débit : quand il est ACTIVÉ,
//  le lecteur choisit d'office la déclinaison la plus LÉGÈRE de chaque
//  chaîne (« TF1 SD » plutôt que « TF1 UHD ») quand le panel en publie
//  plusieurs — au lieu d'attendre que la connexion craque et que l'ABR
//  maison rétrograde en cours de lecture. DÉSACTIVÉ par défaut.
//
//  La correspondance entre déclinaisons vit dans QualityLadder
//  (lowestQualitySibling, pur + testé) ; le branchement dans _open()
//  du lecteur TV. Ici : seulement l'état persisté (modèle BootResume).
// =========================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LowConnectionMode extends ChangeNotifier {
  LowConnectionMode._();
  static final LowConnectionMode instance = LowConnectionMode._();

  static const String _kKey = 'tv.low_connection.v1';

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
