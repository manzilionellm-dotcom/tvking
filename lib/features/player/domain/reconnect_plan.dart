// =========================================================
//  reconnect_plan.dart — Quand ré-ouvrir, sans ouvrir de flux
// =========================================================
//  Même règle que le lecteur TV Zuno (ReconnectPlan, 1 / 2 / 4 / 8 s).
//  Le téléphone joue avec libmpv, pas ExoPlayer : les chiffres restent
//  les mêmes pour que les deux apps se comportent pareil.
//
//  L'écran s'en sert pour :
//    • ne pas lancer une seconde ouverture tant que la première attend ;
//    • attendre 1 s, 2 s, 4 s, puis 8 s ;
//    • ne pas couvrir une image déjà vue par un panneau opaque
//      quand on ré-ouvre la MÊME adresse.
// =========================================================

/// Décisions pures de reconnexion.
abstract final class ReconnectPlan {
  /// Essais silencieux avant l'écran « Réessayer ».
  static const int maxSilent = 8;

  static const int baseMs = 1000;
  static const int capMs = 8000;

  /// 1 s, 2 s, 4 s, puis 8 s. Un numéro d'essai invalide donne 0.
  static int delayMs(int attempt) {
    if (attempt <= 0) return 0;
    final int shift = (attempt - 1) > 3 ? 3 : (attempt - 1);
    final int raw = baseMs << shift;
    return raw > capMs ? capMs : raw;
  }

  /// true = un panneau sombre a le droit de couvrir la vidéo.
  ///
  /// Même adresse ET une image déjà vue : false. On laisse la
  /// dernière image. Une autre adresse, ou jamais d'image : true.
  static bool coverWithLoader({
    required bool hadFrame,
    required bool sameUrl,
  }) {
    if (!hadFrame) return true;
    if (sameUrl) return false;
    return true;
  }
}

/// Compteur d'essais côté écran.
class ReconnectGate {
  int attempt = 0;
  bool pending = false;

  /// Zap ou chaîne qui repart vraiment : budget neuf.
  void reset() {
    attempt = 0;
    pending = false;
  }

  /// null = on abandonne, ou une attente est déjà posée.
  int? arm({required int maxAttempts}) {
    if (pending) return null;
    final int next = attempt + 1;
    if (next > maxAttempts) return null;
    attempt = next;
    pending = true;
    return ReconnectPlan.delayMs(next);
  }

  /// Le délai est fini. true une seule fois.
  bool fire() {
    if (!pending) return false;
    pending = false;
    return true;
  }
}
