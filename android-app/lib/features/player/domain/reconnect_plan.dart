// =========================================================
//  reconnect_plan.dart — Quand ré-ouvrir, sans ouvrir de flux
// =========================================================
//  Même règle que ReconnectPlan.kt (lecteur natif). Les deux
//  fichiers doivent garder les MÊMES chiffres : les tests des
//  deux côtés les verrouillent.
//
//  L'écran s'en sert pour :
//    • ne pas lancer un setUrl pendant que le natif attend déjà
//      (deux préparations = deux sons) ;
//    • attendre 1 s, 2 s, 4 s, puis 8 s ;
//    • ne pas couvrir une image déjà vue par un panneau opaque
//      quand on ré-ouvre la MÊME adresse.
//
//  Le tampon de 1 s et les 180 ms de zap ne sont pas un temps
//  réseau. Les allonger a déjà bloqué des chaînes (v99). On ne
//  les change pas. L'objectif « sous 2 s » côté application,
//  c'est leur somme. Le reste se mesure sur une box.
// =========================================================

/// Décisions pures de reconnexion et de budget de démarrage.
abstract final class ReconnectPlan {
  /// Essais silencieux du natif avant de prévenir l'écran.
  static const int maxSilent = 8;

  static const int baseMs = 1000;
  static const int capMs = 8000;

  /// Données minimum avant lecture (LoadControl, inchangé).
  static const int bufferForPlaybackMs = 1000;

  /// On groupe les appuis Haut/Bas, puis on ouvre UN seul flux.
  static const int zapSettleMs = 180;

  /// Objectif d'ouverture / de zap, hors temps réseau.
  static const int startupTargetMs = 2000;

  /// Groupement du zap + tampon de démarrage.
  static int get appSideBudgetMs => zapSettleMs + bufferForPlaybackMs;

  /// 1 s, 2 s, 4 s, puis 8 s. Un numéro d'essai invalide donne 0.
  static int delayMs(int attempt) {
    if (attempt <= 0) return 0;
    final int shift = (attempt - 1) > 3 ? 3 : (attempt - 1);
    final int raw = baseMs << shift;
    return raw > capMs ? capMs : raw;
  }

  /// true = le panneau sombre a le droit de couvrir la vidéo.
  ///
  /// Même adresse ET une image déjà vue : false. On laisse la
  /// dernière image (la copie tenue par le natif). Une autre
  /// adresse, ou jamais d'image : true, sinon on verrait du noir
  /// ou la mauvaise chaîne.
  static bool coverWithLoader({
    required bool hadFrame,
    required bool sameUrl,
  }) {
    if (!hadFrame) return true;
    if (sameUrl) return false;
    return true;
  }

  /// Le natif a déjà programmé son essai : l'écran ne ré-ouvre pas.
  static bool letNativeOwnRetry(bool nativeRetrying) => nativeRetrying;
}

/// Compteur d'essais côté écran (après que le natif a abandonné,
/// ou quand l'image est gelée sans erreur).
class ReconnectGate {
  int attempt = 0;
  bool pending = false;

  /// Zap ou chaîne qui repart vraiment : budget neuf.
  void reset() {
    attempt = 0;
    pending = false;
  }

  /// null = on abandonne (l'écran d'erreur prend le relais).
  /// null aussi si une attente est déjà posée (pas de double ouverture).
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
