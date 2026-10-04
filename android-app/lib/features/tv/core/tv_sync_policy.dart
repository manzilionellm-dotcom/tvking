// =========================================================
//  tv_sync_policy.dart — Quand l'écran Direct a le droit de re-synchroniser
// =========================================================
//  L'écran Direct reste monté SOUS le lecteur plein écran. Sa re-vérification
//  lente du panel (toutes les ~5 min) peut déclencher un téléchargement et
//  un ré-import complet de la source (des dizaines de milliers de chaînes)
//  pendant que l'image joue : pic mémoire et fil UI saturé au pire moment
//  (box à 1 Go). Décision pure, testée sans écran.
// =========================================================

abstract final class TvSyncPolicy {
  /// Vrai = la re-vérification lente peut partir maintenant.
  ///
  /// [playerOpen] : un lecteur plein écran est ouvert au-dessus du Direct.
  /// [allowDuringPlayback] : interrupteur de repli (ancien comportement).
  static bool allowSlowSync({
    required bool playerOpen,
    required bool allowDuringPlayback,
  }) {
    if (allowDuringPlayback) return true;
    return !playerOpen;
  }
}
