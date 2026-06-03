// =========================================================
//  cinema_lock.dart — Verrou de la zone Cinéma & Séries
// =========================================================
//  La zone Cinéma & Séries (et Adulte) est protégée. Déverrouillage :
//    1. Empreinte / Face ID du téléphone (BiometricAuth) — prioritaire.
//    2. Sinon (pas de capteur, ou échec) : un code PIN.
//
//  Le PIN est MODIFIABLE et stocké localement (SharedPreferences).
//  Défaut : "00000". Le déverrouillage est valable pour la SESSION
//  (jusqu'à fermeture de l'app) une fois réussi.
// =========================================================

import 'package:shared_preferences/shared_preferences.dart';

abstract final class CinemaLock {
  static const String _kPinKey = 'cinema_lock_pin';
  static const String _kDefaultPin = '00000';

  /// Déverrouillé pour la session courante (mémoire seulement).
  static bool unlockedThisSession = false;

  /// Récupère le PIN configuré (défaut "00000").
  static Future<String> getPin() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? pin = prefs.getString(_kPinKey);
      if (pin == null || pin.isEmpty) return _kDefaultPin;
      return pin;
    } catch (_) {
      return _kDefaultPin;
    }
  }

  /// Change le PIN. [pin] = 4 à 8 chiffres.
  static Future<void> setPin(String pin) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinKey, pin);
  }

  /// Vérifie un PIN saisi.
  static Future<bool> verifyPin(String entered) async {
    final String pin = await getPin();
    final bool ok = entered == pin;
    if (ok) unlockedThisSession = true;
    return ok;
  }
}
