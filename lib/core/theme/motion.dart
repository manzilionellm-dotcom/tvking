// =========================================================
//  motion.dart — Tokens de MOUVEMENT partagés
// =========================================================
//  Aujourd'hui chaque widget réinvente ses durées/courbes → le mouvement
//  de l'app manque de rythme commun. On centralise ici un vocabulaire de
//  mouvement (comme `CinematicSpacing` centralise l'espace) : le ressenti
//  « premium » vient surtout de la CONSTANCE du mouvement, pas de son
//  intensité.
//
//  Toujours respecter `MediaQuery.disableAnimationsOf(context)` côté
//  appelant (accessibilité) : ces tokens décrivent le mouvement quand il
//  est activé, ils ne le forcent pas.
// =========================================================

import 'package:flutter/animation.dart';

class Motion {
  Motion._();

  // ----- Durées -----
  static const Duration instant = Duration(milliseconds: 120);
  static const Duration quick = Duration(milliseconds: 220);
  static const Duration base = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 480);

  // ----- Courbes -----
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve spring = Curves.easeOutBack;

  /// Décalage d'entrée en cascade (rangées / cartes d'accueil) :
  /// `delay = index * 60 ms`, plafonné pour ne jamais traîner.
  static Duration stagger(int index) =>
      Duration(milliseconds: 60 * index.clamp(0, 8));
}
