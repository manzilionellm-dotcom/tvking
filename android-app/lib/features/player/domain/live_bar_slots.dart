// =========================================================
//  live_bar_slots.dart — place des boutons du direct
// =========================================================
//  L'ordre est fixe pour que la télécommande ne saute pas :
//    0 Guide, 1 REC, 2 Favori,
//    puis « Suivre » si le guide a un titre,
//    puis « Début » s'il y a du rattrapage,
//    puis les sous-titres s'il y en a,
//    puis le moteur d'image, toujours en dernier.
//  Le moteur est en dernier pour ne pas décaler les boutons
//  déjà appris (Guide / REC / Favori). « Suivre » est optionnel :
//  sans lui, les index restent ceux d'avant (les tests d'image).
// =========================================================

class LiveBarSlots {
  const LiveBarSlots._();

  /// Guide, enregistrement, favori. Ils ne bougent pas.
  static const int base = 3;

  static int? follow(bool show) => show ? base : null;

  static int? start(bool show, {bool showFollow = false}) {
    if (!show) return null;
    return base + (showFollow ? 1 : 0);
  }

  static int? subs({
    required bool showStart,
    required bool showSubs,
    bool showFollow = false,
  }) {
    if (!showSubs) return null;
    var i = base;
    if (showFollow) i++;
    if (showStart) i++;
    return i;
  }

  static int engine({
    required bool showStart,
    required bool showSubs,
    bool showFollow = false,
  }) {
    var i = base;
    if (showFollow) i++;
    if (showStart) i++;
    if (showSubs) i++;
    return i;
  }

  static int count({
    required bool showStart,
    required bool showSubs,
    bool showFollow = false,
  }) =>
      engine(
        showStart: showStart,
        showSubs: showSubs,
        showFollow: showFollow,
      ) +
      1;
}
