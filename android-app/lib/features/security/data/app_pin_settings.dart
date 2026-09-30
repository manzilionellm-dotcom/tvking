// =========================================================
//  app_pin_settings.dart — Code à 4 chiffres in-app
// =========================================================
//  Pourquoi un PIN in-app en plus de la biometrie ?
//
//  Le retour de l'utilisateur montre que `local_auth` peut
//  laisser l'app inaccessible quand :
//    - le capteur biometrique est dans l'ecran et ne registre pas
//      le doigt correctement,
//    - aucun verrouillage d'ecran systeme (PIN/schema) n'est
//      configure, donc Android n'offre pas de fallback,
//    - le dialog systeme ne s'affiche pas pour une raison X.
//
//  Solution : un PIN à 4 chiffres GERE PAR L'APP elle-meme,
//  totalement independant de l'OS. Il n'y a PLUS de code par
//  défaut : le foyer le choisit la première fois qu'il active
//  le mode enfants. Cinq erreurs de suite bloquent la saisie
//  pendant cinq minutes.
//
//  Il est stocke dans SharedPreferences (cle
//  `security.app_pin_value`).
// =========================================================

import 'package:shared_preferences/shared_preferences.dart';

import 'pin_attempt_policy.dart';

class AppPinSettings {
  AppPinSettings._();
  static final AppPinSettings instance = AppPinSettings._();

  static const String _kPinValue = 'security.app_pin_value';
  static const String _kFailures = 'security.app_pin_failures';
  static const String _kLockedUntil = 'security.app_pin_locked_until';

  static const PinAttemptPolicy policy = PinAttemptPolicy();

  /// Ancien code par défaut. Il n'est plus accepté. Le champ reste
  /// pour les écrans qui l'affichaient : il ne déverrouille plus rien.
  static const String defaultPin = '0000';

  /// `true` tant que le foyer n'a pas choisi son code.
  Future<bool> isUsingDefault() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_kPinValue);
    if (stored == null || stored.isEmpty) return true;
    return policy.isForbidden(stored);
  }

  /// `true` si un code choisi par le foyer est en place.
  Future<bool> hasCustomPin() async {
    return !(await isUsingDefault());
  }

  /// Millisecondes restantes de blocage, ou 0.
  Future<int> lockRemainingMs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int until = prefs.getInt(_kLockedUntil) ?? 0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (!policy.isLocked(lockedUntilMs: until, nowMs: now)) return 0;
    return until - now;
  }

  /// Verifie [pin]. Sans code choisi, rien n'est accepté (y compris
  /// l'ancien 0000). Trop d'erreurs : refus jusqu'au déblocage.
  Future<bool> verify(String pin) async {
    if (pin.isEmpty || policy.isForbidden(pin)) return false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int until = prefs.getInt(_kLockedUntil) ?? 0;
    if (policy.isLocked(lockedUntilMs: until, nowMs: now)) return false;
    final String? stored = prefs.getString(_kPinValue);
    if (stored == null || stored.isEmpty || policy.isForbidden(stored)) {
      return false;
    }
    if (pin == stored) {
      await prefs.setInt(_kFailures, 0);
      await prefs.setInt(_kLockedUntil, 0);
      return true;
    }
    final ({int failures, int lockedUntilMs}) next = policy.onFailure(
      failures: prefs.getInt(_kFailures) ?? 0,
      nowMs: now,
    );
    await prefs.setInt(_kFailures, next.failures);
    await prefs.setInt(_kLockedUntil, next.lockedUntilMs);
    return false;
  }

  /// Change le PIN. [newPin] doit faire entre 4 et 8 chiffres,
  /// et ne pas être l'ancien code par défaut.
  /// Throw [ArgumentError] sinon — c'est l'UI qui doit valider
  /// avant d'appeler cette methode.
  Future<void> setPin(String newPin) async {
    if (newPin.length < 4 || newPin.length > 8) {
      throw ArgumentError('Le PIN doit faire entre 4 et 8 chiffres.');
    }
    if (!RegExp(r'^\d+$').hasMatch(newPin)) {
      throw ArgumentError('Le PIN ne peut contenir que des chiffres.');
    }
    if (policy.isForbidden(newPin)) {
      throw ArgumentError('Choisis un code autre que 0000.');
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinValue, newPin);
    await prefs.setInt(_kFailures, 0);
    await prefs.setInt(_kLockedUntil, 0);
  }

  /// Efface le code. Le foyer devra en choisir un nouveau avant
  /// de pouvoir protéger le mode enfants. On ne revient PAS à 0000.
  Future<void> resetToDefault() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinValue);
    await prefs.setInt(_kFailures, 0);
    await prefs.setInt(_kLockedUntil, 0);
  }
}
