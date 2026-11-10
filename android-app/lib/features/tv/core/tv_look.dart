// =========================================================
//  tv_look.dart — Confort ou Ghost, au choix
// =========================================================
//  Deux apparences. Noir Fantôme devient le défaut de cette version,
//  y compris après une mise à jour depuis l'ancien thème Confort.
//  Le choix v1 est conservé ; la préférence v2 mémorise ensuite les
//  nouveaux choix, sans réimposer Ghost à chaque démarrage. Le choix
//  reste local et ne modifie jamais l'image de la chaîne.
// =========================================================
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TvLookChoice { comfort, ghost }

class TvLook extends ChangeNotifier {
  TvLook._();
  static final TvLook instance = TvLook._();

  static const String prefKey = 'zuno.tv.look.v2';

  TvLookChoice _choice = TvLookChoice.ghost;

  TvLookChoice get choice => _choice;
  bool get ghost => _choice == TvLookChoice.ghost;

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefKey);
      final TvLookChoice next = TvLookChoice.values.firstWhere(
        (TvLookChoice c) => c.name == raw,
        orElse: () => TvLookChoice.ghost,
      );
      if (next != _choice) {
        _choice = next;
        notifyListeners();
      }
      // La nouvelle clé sert aussi de marqueur de migration. On laisse
      // zuno.tv.look.v1 intacte : aucun ancien choix n'est effacé.
      if (raw == null) await prefs.setString(prefKey, next.name);
    } catch (_) {
      // On garde le choix courant. Le démarrage ne bloque pas.
    }
  }

  Future<void> toggle() => choose(
        _choice == TvLookChoice.ghost
            ? TvLookChoice.comfort
            : TvLookChoice.ghost,
      );

  Future<void> choose(TvLookChoice choice) async {
    if (_choice != choice) {
      _choice = choice;
      notifyListeners();
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, choice.name);
    } catch (_) {}
  }

  void debugChoose(TvLookChoice choice) {
    _choice = choice;
    notifyListeners();
  }
}
