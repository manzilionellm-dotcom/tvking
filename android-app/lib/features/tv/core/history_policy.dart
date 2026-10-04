// =========================================================
//  history_policy.dart — Quand une chaîne compte comme « regardée »
// =========================================================
//  Avant (4 octobre 2026) : chaque ouverture écrivait l'historique
//  (« Reprendre », dernière chaîne au démarrage, « À cette heure »)
//  immédiatement. Vingt chaînes survolées en zappant = vingt entrées,
//  et la rangée « Reprendre » ne reprenait rien d'utile.
//
//  Règle : une chaîne compte quand une image a été vue ET qu'on y est
//  resté [dwell], ou quand on quitte le lecteur dessus avec une image
//  vue (celle qu'on laisse à l'écran est, de fait, celle qu'on regarde).
//  Repli `zuno.history.on_open` : écriture immédiate, comme avant.
//  Décision pure, testée sans écran.
// =========================================================

abstract final class HistoryPolicy {
  /// Temps sur la chaîne avant de l'inscrire à l'historique.
  static const Duration dwell = Duration(seconds: 20);

  /// Le minuteur de [dwell] vient d'expirer.
  static bool recordAfterDwell({
    required bool frameShown,
    required bool sameChannel,
    required bool immediate,
  }) {
    if (immediate) return false; // déjà écrit à l'ouverture
    return frameShown && sameChannel;
  }

  /// On quitte le lecteur (Retour) sur cette chaîne.
  static bool recordOnExit({
    required bool frameShown,
    required bool alreadyRecorded,
    required bool immediate,
  }) {
    if (immediate || alreadyRecorded) return false;
    return frameShown;
  }
}
