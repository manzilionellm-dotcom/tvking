// =========================================================
//  clear_voice_flag.dart — voix claire / mode nuit
// =========================================================
//  Coupé par défaut. Allumé : le lecteur natif compresse les pics
//  PCM (AAC, MP2) et déclare le flux « parole » au téléviseur.
//  Le passthrough AC-3 / DTS vers une barre de son n'est pas modifié
//  (Media3 ne compresse pas ce chemin). Une préférence illisible
//  reste coupée : on ne change pas le son tout seul.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClearVoiceFlag {
  ClearVoiceFlag._();

  static const String key = 'zuno.player.clear_voice.v1';

  static bool _value = false;
  static bool _loaded = false;

  /// Faux tant qu'on n'a pas lu le disque, et faux si rien n'est écrit.
  static bool get value => _value;

  static final ValueNotifier<bool> changes = ValueNotifier<bool>(false);

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _value = prefs.getBool(key) ?? false;
    } catch (_) {
      _value = false;
    }
    _loaded = true;
    if (changes.value != _value) changes.value = _value;
  }

  static Future<void> set(bool value) async {
    _value = value;
    _loaded = true;
    if (changes.value != value) changes.value = value;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // On garde la valeur en mémoire : l'écran reste cohérent.
    }
  }
}
