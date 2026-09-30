// =========================================================
//  pin_attempt_policy.dart — Règles du code parental (sans stockage)
// =========================================================
//  Le code 0000 n'est plus accepté : c'était le code de tout le
//  monde. Après plusieurs erreurs, on bloque quelques minutes
//  pour qu'un enfant ne puisse pas essayer les 10 000 combinaisons.
// =========================================================

class PinAttemptPolicy {
  const PinAttemptPolicy();

  static const int maxFailures = 5;
  static const int lockMs = 5 * 60 * 1000;

  /// 0000 était le code par défaut, écrit dans l'écran. On le refuse
  /// même si quelqu'un essaie de le réenregistrer.
  bool isForbidden(String pin) => pin == '0000';

  bool isLocked({required int lockedUntilMs, required int nowMs}) {
    return lockedUntilMs > nowMs;
  }

  /// Après un échec : nouveau compteur, et l'instant de déblocage
  /// (0 si on n'a pas encore atteint le plafond).
  ({int failures, int lockedUntilMs}) onFailure({
    required int failures,
    required int nowMs,
  }) {
    final int next = failures + 1;
    if (next >= maxFailures) {
      return (failures: next, lockedUntilMs: nowMs + lockMs);
    }
    return (failures: next, lockedUntilMs: 0);
  }
}
