// =========================================================
//  tv_look.dart — Confort ou Ghost, au choix
// =========================================================
//  Deux apparences. Confort reste le défaut (palette du soir,
//  PR confort). Ghost est le noir Black Badge. Le choix est
//  local : rien n'est envoyé au panel. L'image de la chaîne
//  n'utilise pas cette bascule.
// =========================================================
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TvLookChoice { comfort, ghost }

class TvLook extends ChangeNotifier {
  TvLook._();
  static final TvLook instance = TvLook._();

  static const String prefKey = 'zuno.tv.look.v1';

  TvLookChoice _choice = TvLookChoice.comfort;

  TvLookChoice get choice => _choice;
  bool get ghost => _choice == TvLookChoice.ghost;

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefKey);
      final TvLookChoice next = TvLookChoice.values.firstWhere(
        (TvLookChoice c) => c.name == raw,
        orElse: () => TvLookChoice.comfort,
      );
      if (next != _choice) {
        _choice = next;
        notifyListeners();
      }
    } catch (_) {
      // On reste sur Confort. Le démarrage ne bloque pas.
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
