// =========================================================
//  followed_lead.dart — Combien de minutes avant le bandeau
// =========================================================
//  Réglage de la BOX, pas d'un profil : tout le monde devant
//  la télé voit le même délai. 2, 5, 10 ou 15 minutes.
//  Une valeur illisible redevient 5.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/show_clock.dart';

class FollowedLead {
  FollowedLead._();

  static const String key = 'zuno.followed.lead_min';

  static int _value = kLeadDefault;
  static bool _loaded = false;

  /// Valeur connue. Avant [load], c'est 5 minutes.
  static int get value => _value;

  static Future<int> load() async {
    if (_loaded) return _value;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _value = normalizeLead(prefs.getInt(key));
    } catch (_) {
      _value = kLeadDefault;
    }
    _loaded = true;
    return _value;
  }

  static Future<void> set(int minutes) async {
    _value = normalizeLead(minutes);
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, _value);
    } catch (e) {
      if (kDebugMode) debugPrint('[Suivi] délai : $e');
    }
  }
}
