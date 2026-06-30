// =========================================================
//  tv_dimens.dart — Tokens 10-foot (canvas, safe area, grille,
//  focus, typo). Tout en dp, base 960×540 (cf. spec TV §1-6).
// =========================================================
//  Règle d'or : JAMAIS de px en dur dans les écrans → on passe par
//  ces constantes. Le système met à l'échelle de 720p à 4K tout seul.
// =========================================================
import 'package:flutter/widgets.dart';

class TvDimens {
  TvDimens._();

  // --- §2 Safe area / overscan (5% de 960×540) ---
  static const double safeH = 48; // marges gauche/droite
  static const double safeV = 24; // marges haut/bas

  // --- §3 Grille 12 colonnes ---
  static const int gridColumns = 12;
  static const double columnWidth = 52;
  static const double gutter = 20; // entre colonnes
  static const double contentMargin = 58;
  static const double rowGap = 4;

  // --- §4 Focus (multi-signaux) ---
  //  RÈGLE PREMIUM (réf. Apple TV+) : scale RETENU — au-delà de ~1.06 ça
  //  « gonfle » et fait cheap. La profondeur vient de l'OMBRE PORTÉE + de la
  //  lueur champagne, pas d'un gros zoom. Carte = 1.06, ligne = 1.04, bloc = 1.03.
  static const double focusScaleSmall = 1.08;
  static const double focusScaleMedium = 1.06;
  static const double focusScaleLarge = 1.06;
  // Court + DÉCÉLÉRÉ : l'élément arrive vite puis se pose en douceur. 150 ms =
  // ressenti « instantané » à la navigation D-pad (Apple TV+ / Google TV sont
  // à ~150 ms) sans perdre le fondu. Au-delà de ~200 ms ça paraît mou.
  static const Duration focusAnim = Duration(milliseconds: 150);
  static const Curve focusCurve = Curves.easeOutCubic;
  static const double focusGlowBlur = 34; // lueur champagne (0 0 32px)
  static const double focusGlowSpread = 2;
  static const double focusOutline = 2; // contour or
  static const double focusInset = 3; // espace élément ↔ contour
  // Ombre portée d'élévation au focus (réf. Apple TV+) : c'est ELLE, pas la
  // bordure, qui « soulève » l'élément. 0 12px 40px noir 60 %.
  static const double focusElevBlur = 40;
  static const double focusElevDy = 12;

  // --- §6 Typo : nettement plus grand que mobile (lisible à 3 m) ---
  static const double displayL = 48;
  static const double displayM = 40;
  static const double displayS = 34;
  static const double headline = 30;
  static const double title = 22;
  static const double titleS = 19;
  static const double body = 18;
  static const double label = 16;
  static const double caption = 14;

  // --- Rayons / élévations ---
  static const double cardRadius = 14;
  static const double panelRadius = 16;

  // --- Rangées / cartes de référence ---
  static const double channelLogo = 56;   // logo dans une rangée
  static const double posterW = 132;       // affiche Film 2:3
  static const double posterH = 198;       // 132 × 3/2
  static const double railCardW = 220;     // carte large (live/cluster)
  static const double railCardH = 124;     // ~16:9
}
