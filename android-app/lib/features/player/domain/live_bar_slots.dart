// =========================================================
//  live_bar_slots.dart — place des boutons du direct
// =========================================================
//  L'ordre est fixe pour que la télécommande ne saute pas :
//    0 Guide, 1 REC, 2 Favori,
//    puis « Pause » si le fournisseur a un timeshift,
//    puis « Suivre » si le guide a un titre,
//    puis « Début » s'il y a du rattrapage,
//    puis les sous-titres s'il y en a,
//    puis le moteur d'image, toujours en dernier.
//  Le moteur est en dernier pour ne pas décaler les boutons
//  déjà appris (Guide / REC / Favori). Pause et Suivre sont
//  optionnels : sans eux, les index restent ceux d'avant.
// =========================================================

class LiveBarSlots {
  const LiveBarSlots._();

  /// Guide, enregistrement, favori. Ils ne bougent pas.
  static const int base = 3;

  /// Après Favori. Absent si la chaîne ne déclare pas de timeshift :
  /// Guide / REC / Favori ne bougent pas.
  static int? pause(bool show) => show ? base : null;

  static int? follow(bool show, {bool showPause = false}) {
    if (!show) return null;
    return base + (showPause ? 1 : 0);
  }

  static int? start(
    bool show, {
    bool showFollow = false,
    bool showPause = false,
  }) {
    if (!show) return null;
    return _shift(showPause: showPause, showFollow: showFollow);
  }

  static int? subs({
    required bool showStart,
    required bool showSubs,
    bool showFollow = false,
    bool showPause = false,
  }) {
    if (!showSubs) return null;
    return _shift(
      showPause: showPause,
      showFollow: showFollow,
      showStart: showStart,
    );
  }

  static int engine({
    required bool showStart,
    required bool showSubs,
    bool showFollow = false,
    bool showPause = false,
  }) {
    return _shift(
      showPause: showPause,
      showFollow: showFollow,
      showStart: showStart,
      showSubs: showSubs,
    );
  }

  static int count({
    required bool showStart,
    required bool showSubs,
    bool showFollow = false,
    bool showPause = false,
  }) =>
      engine(
        showStart: showStart,
        showSubs: showSubs,
        showFollow: showFollow,
        showPause: showPause,
      ) +
      1;

  static int _shift({
    required bool showPause,
    required bool showFollow,
    bool showStart = false,
    bool showSubs = false,
  }) {
    var i = base;
    if (showPause) i++;
    if (showFollow) i++;
    if (showStart) i++;
    if (showSubs) i++;
    return i;
  }
}
