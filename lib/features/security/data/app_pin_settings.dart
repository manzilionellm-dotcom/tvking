// =========================================================
//  app_pin_settings.dart — Code à 4-8 chiffres in-app (durci)
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
//  Solution : un PIN GERE PAR L'APP elle-meme, independant de l'OS.
//  Code par defaut = "0000" (documente pour la premiere ouverture).
//
//  DURCISSEMENT SÉCURITÉ (audit 2026-07-22) — ce PIN garde aussi le
//  Mode Enfants / filtre adulte, donc il DOIT résister :
//    1. STOCKAGE HACHÉ (plus de clair) : on stocke un hachage SALÉ et
//       ITÉRÉ (HMAC-SHA256 × N) du PIN, jamais le PIN. Un accès fichier ne
//       révèle plus le code directement, et l'itération ralentit fortement
//       une attaque hors-ligne (les 4-8 chiffres restent intrinsèquement
//       peu entropiques — d'où le point 2).
//    2. VERROUILLAGE PROGRESSIF : après plusieurs essais ratés, on bloque
//       la vérification pendant une durée qui CROÎT (30 s, 1 min, 2 min…) →
//       le forçage exhaustif en ligne (via l'UI) devient impraticable.
//    Migration transparente : un ancien PIN en clair est re-haché au 1er
//    déverrouillage réussi.
// =========================================================

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPinSettings {
  AppPinSettings._();
  static final AppPinSettings instance = AppPinSettings._();

  // Ancienne clé (PIN EN CLAIR) — lue pour migration, plus jamais écrite.
  static const String _kLegacyPinValue = 'security.app_pin_value';
  // Nouvelles clés : hachage + sel par appareil.
  static const String _kPinHash = 'security.app_pin_hash';
  static const String _kPinSalt = 'security.app_pin_salt';
  // Anti-brute-force : compteur d'échecs + horodatage de fin de blocage.
  static const String _kFailCount = 'security.app_pin_fail_count';
  static const String _kLockUntilMs = 'security.app_pin_lock_until_ms';

  /// PIN par defaut sur une install fraiche ou apres reset.
  static const String defaultPin = '0000';

  /// Nombre d'itérations HMAC (KDF léger) : ralentit le forçage hors-ligne
  /// tout en restant &lt; 100 ms au déverrouillage sur une box modeste.
  static const int _kIterations = 20000;

  /// Nombre d'essais ratés TOLÉRÉS avant le 1er verrouillage.
  static const int _kFreeAttempts = 4;
  static const Duration _kBaseLock = Duration(seconds: 30);
  static const Duration _kMaxLock = Duration(minutes: 15);

  /// Horloge injectable pour les tests (verrouillage temporel).
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// `true` tant que l'utilisateur n'a pas defini son propre PIN.
  Future<bool> isUsingDefault() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return !prefs.containsKey(_kPinHash) &&
        !prefs.containsKey(_kLegacyPinValue);
  }

  /// Durée de blocage RESTANTE (Duration.zero si non verrouillé). L'UI
  /// l'affiche pour dire à l'utilisateur combien de temps patienter.
  Future<Duration> lockoutRemaining() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int untilMs = prefs.getInt(_kLockUntilMs) ?? 0;
    final int nowMs = clock().millisecondsSinceEpoch;
    if (untilMs <= nowMs) return Duration.zero;
    return Duration(milliseconds: untilMs - nowMs);
  }

  /// Verifie [pin]. Applique le verrouillage anti-brute-force : si un blocage
  /// est actif, renvoie `false` SANS tester (l'appelant peut lire
  /// [lockoutRemaining]). Un succès remet compteur et blocage à zéro ; un
  /// échec incrémente le compteur et arme un blocage croissant au-delà du
  /// seuil.
  Future<bool> verify(String pin) async {
    if (pin.isEmpty) return false;
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // Blocage actif → refus immédiat (ne consomme pas d'essai).
    final int untilMs = prefs.getInt(_kLockUntilMs) ?? 0;
    final int nowMs = clock().millisecondsSinceEpoch;
    if (untilMs > nowMs) return false;

    final bool ok = await _matches(prefs, pin);
    if (ok) {
      // Reset anti-brute-force + migration éventuelle du clair vers le haché.
      await prefs.remove(_kFailCount);
      await prefs.remove(_kLockUntilMs);
      if (!prefs.containsKey(_kPinHash) &&
          prefs.containsKey(_kLegacyPinValue)) {
        await _writeHashed(prefs, pin);
        await prefs.remove(_kLegacyPinValue);
      }
      return true;
    }

    // Échec : incrémente et arme un blocage croissant si on dépasse le seuil.
    final int fails = (prefs.getInt(_kFailCount) ?? 0) + 1;
    await prefs.setInt(_kFailCount, fails);
    if (fails > _kFreeAttempts) {
      final int over = fails - _kFreeAttempts; // 1, 2, 3…
      // 30 s, 60 s, 120 s, 240 s… plafonné à 15 min.
      int ms = _kBaseLock.inMilliseconds * (1 << (over - 1));
      if (ms > _kMaxLock.inMilliseconds) ms = _kMaxLock.inMilliseconds;
      await prefs.setInt(_kLockUntilMs, nowMs + ms);
    }
    return false;
  }

  /// Compare [pin] au secret enregistré (haché en priorité, sinon clair
  /// hérité, sinon défaut). Pur vis-à-vis de l'état anti-brute-force.
  Future<bool> _matches(SharedPreferences prefs, String pin) async {
    final String? hash = prefs.getString(_kPinHash);
    final String? salt = prefs.getString(_kPinSalt);
    if (hash != null && salt != null) {
      return _slowEquals(_derive(pin, salt), hash);
    }
    // Pas encore de hachage : clair hérité, ou défaut si rien n'a été défini.
    final String? legacy = prefs.getString(_kLegacyPinValue);
    final String expected = legacy ?? defaultPin;
    return pin == expected;
  }

  /// Change le PIN. [newPin] = 4 à 8 chiffres. Écrit le HACHÉ (jamais le
  /// clair) et remet à zéro l'état anti-brute-force.
  Future<void> setPin(String newPin) async {
    if (newPin.length < 4 || newPin.length > 8) {
      throw ArgumentError('Le PIN doit faire entre 4 et 8 chiffres.');
    }
    if (!RegExp(r'^\d+$').hasMatch(newPin)) {
      throw ArgumentError('Le PIN ne peut contenir que des chiffres.');
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _writeHashed(prefs, newPin);
    await prefs.remove(_kLegacyPinValue);
    await prefs.remove(_kFailCount);
    await prefs.remove(_kLockUntilMs);
  }

  /// Remet le PIN au defaut (0000) et efface tout état.
  Future<void> resetToDefault() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinHash);
    await prefs.remove(_kPinSalt);
    await prefs.remove(_kLegacyPinValue);
    await prefs.remove(_kFailCount);
    await prefs.remove(_kLockUntilMs);
  }

  // ---- Hachage salé itéré (KDF léger, sans dépendance externe) ----

  Future<void> _writeHashed(SharedPreferences prefs, String pin) async {
    final String salt = _newSalt();
    await prefs.setString(_kPinSalt, salt);
    await prefs.setString(_kPinHash, _derive(pin, salt));
  }

  /// HMAC-SHA256(pin) itéré [_kIterations] fois avec le sel comme clé.
  static String _derive(String pin, String salt) {
    final List<int> key = utf8.encode(salt);
    List<int> acc = utf8.encode(pin);
    final Hmac hmac = Hmac(sha256, key);
    for (int i = 0; i < _kIterations; i++) {
      acc = hmac.convert(acc).bytes;
    }
    return base64Url.encode(acc);
  }

  /// Sel aléatoire (128 bits) via le CSPRNG du système (`Random.secure`).
  static String _newSalt() {
    final Random rng = Random.secure();
    final List<int> bytes =
        List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Comparaison à temps ~constant (évite un canal temporel sur le hachage).
  static bool _slowEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
