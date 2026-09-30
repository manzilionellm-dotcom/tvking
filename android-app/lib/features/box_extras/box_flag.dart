// =========================================================
//  box_flag.dart — Interrupteur local d'une fonction en plus
// =========================================================
//  Chaque fonction (téléphone, voix, famille, guide « raté »,
//  suggestions d'heure, sous-titres) a SON interrupteur.
//  Défaut : allumé, pour qu'on puisse l'essayer sur la box.
//  Éteint : la fonction ne démarre pas. Elle ne touche jamais
//  au lecteur toute seule. Une préférence illisible = allumé,
//  comme si on n'avait rien changé.
// =========================================================

import 'package:shared_preferences/shared_preferences.dart';

class BoxFlag {
  BoxFlag(this.key);

  /// Clé SharedPreferences. Une par fonction.
  final String key;

  bool _value = true;
  bool _loaded = false;

  /// Valeur connue. Avant [load], c'est « allumé ».
  bool get value => _value;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _value = prefs.getBool(key) ?? true;
    } catch (_) {
      _value = true;
    }
    _loaded = true;
  }

  Future<void> set(bool value) async {
    _value = value;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // On garde la valeur en mémoire : l'écran reste cohérent
      // même si le disque refuse l'écriture.
    }
  }
}
