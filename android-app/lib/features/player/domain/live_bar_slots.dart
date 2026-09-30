// =========================================================
//  live_bar_slots.dart — place des boutons du direct
// =========================================================
//  L'ordre est fixe pour que la télécommande ne saute pas :
//    0 Guide, 1 REC, 2 Favori,
//    puis « Début » s'il y a du rattrapage,
//    puis les sous-titres s'il y en a,
//    puis le moteur d'image, toujours en dernier.
//  Le moteur est en dernier pour ne pas décaler les boutons
//  déjà appris (Guide / REC / Favori).
// =========================================================

class LiveBarSlots {
  const LiveBarSlots._();

  /// Guide, enregistrement, favori. Ils ne bougent pas.
  static const int base = 3;

  static int? start(bool show) => show ? base : null;

  static int? subs({required bool showStart, required bool showSubs}) {
    if (!showSubs) return null;
    return base + (showStart ? 1 : 0);
  }

  static int engine({required bool showStart, required bool showSubs}) {
    var i = base;
    if (showStart) i++;
    if (showSubs) i++;
    return i;
  }

  static int count({required bool showStart, required bool showSubs}) =>
      engine(showStart: showStart, showSubs: showSubs) + 1;
}
