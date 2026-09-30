// =========================================================
//  voice_remote_assist.dart — Aide vocale DISTANTE (option)
// =========================================================
//  DÉSACTIVÉE PAR DÉFAUT. Aucune clé n'est écrite dans l'application :
//  si on l'active, l'appel passe par le service déjà en place
//  (AiSearchService), qui garde le secret côté serveur. S'il ne répond
//  pas, la recherche locale prend le relais — l'écran ne reste pas
//  bloqué.
//
//  « Qu'est-ce qu'il y a ce soir ? » n'utilise JAMAIS ce réglage :
//  la réponse vient du guide déjà sur la box.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class VoiceRemoteAssist {
  static const String _kEnabled = 'zuno.voice.remote_ai.v1';

  /// Valeur sûre tant qu'on n'a pas lu la mémoire : désactivé.
  static bool enabled = false;

  static bool _loaded = false;

  /// `null` en mémoire → désactivé. Utilisé par les tests, sans
  /// SharedPreferences.
  static bool enabledFromStored(bool? stored) => stored ?? false;

  static Future<bool> load() async {
    if (_loaded) return enabled;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      enabled = enabledFromStored(prefs.getBool(_kEnabled));
    } catch (e) {
      enabled = false;
      if (kDebugMode) debugPrint('[Voix] réglage illisible : $e');
    }
    _loaded = true;
    return enabled;
  }

  static Future<void> setEnabled(bool value) async {
    enabled = value;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } catch (e) {
      if (kDebugMode) debugPrint('[Voix] réglage non sauvé : $e');
    }
  }
}
