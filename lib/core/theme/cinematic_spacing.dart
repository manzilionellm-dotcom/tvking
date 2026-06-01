// =========================================================
//  cinematic_spacing.dart — Tokens de rythme cinéma 7 MOTION
// =========================================================
//  Le brief design Phase 1 demande "cinematic spacing : the
//  current app is too dense, use larger breathing spaces,
//  rhythm consistency, premium vertical spacing".
//
//  Au lieu de saupoudrer des `SizedBox(height: 24)` au hasard
//  dans 100 fichiers, on centralise un système d'espacement
//  qui suit une progression géométrique douce — pas un Material
//  4 px grid bête, mais une cadence qui respire comme une
//  page de magazine ou un storyboard de film.
//
//  Échelle : 4, 8, 12, 16, 24, 32, 48, 64, 96.
//  Les sauts s'élargissent à mesure qu'on monte → plus on
//  s'éloigne du détail, plus on respire.
//
//  Conventions d'usage :
//    - micro / xs : à l'intérieur d'un chip ou d'une icône
//    - s / m      : padding interne de cards et boutons
//    - l / xl     : marges entre sections de rails
//    - xxl / hero : respiration au-dessus d'un hero edge-to-edge
//                   ou entre un header et son premier contenu
// =========================================================

abstract final class CinematicSpacing {
  /// 4 px — micro spacing (gap intra-chip).
  static const double micro = 4.0;

  /// 8 px — extra-small (gap entre une icône et son label).
  static const double xs = 8.0;

  /// 12 px — small (séparation entre éléments d'une même ligne).
  static const double s = 12.0;

  /// 16 px — medium (padding de card par défaut).
  static const double m = 16.0;

  /// 24 px — large (padding horizontal d'écran).
  static const double l = 24.0;

  /// 32 px — extra-large (espacement entre deux rails).
  static const double xl = 32.0;

  /// 48 px — XXL (respiration entre une section et la suivante).
  static const double xxl = 48.0;

  /// 64 px — héroïque (espace au-dessus / sous un hero edge-to-edge).
  static const double hero = 64.0;

  /// 96 px — théâtre (transitions de section majeures, fin d'écran
  /// avant la zone de la bottom-nav flottante).
  static const double theater = 96.0;

  // -------------------------------------------------------
  //  RAYONS DE COIN
  // -------------------------------------------------------
  //  Apple TV+, HBO, Criterion : on évite à la fois le carré
  //  brut (techno) et le pill exagéré (pop). On reste dans
  //  une gamme de coins "doux mais affirmés".

  /// 8 px — chips, mini-boutons.
  static const double radiusS = 8.0;

  /// 12 px — boutons CTA standard.
  static const double radiusM = 12.0;

  /// 16 px — cards posters.
  static const double radiusL = 16.0;

  /// 22 px — cards hero, sheets glissants.
  static const double radiusXL = 22.0;

  /// 28 px — dock flottant glass.
  static const double radiusDock = 28.0;
}
