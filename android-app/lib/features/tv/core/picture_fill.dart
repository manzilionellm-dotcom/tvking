// =========================================================
//  picture_fill.dart — Remplir l'écran d'un téléphone
// =========================================================
//  Les téléphones récents sont plus allongés (19,5:9, 20:9) qu'une
//  image de télévision (16:9). En paysage, l'image laisse donc deux
//  bandes noires sur les côtés. Le bouton « Remplir » agrandit l'image
//  jusqu'à couvrir tout l'écran : on perd un peu de haut et de bas, on
//  gagne une image plus grande. « Image entière » revient à l'image
//  complète.
//
//  On ne déforme JAMAIS l'image : le rapport 16:9 est gardé, seul le
//  cadre grandit et ce qui dépasse est coupé.
//
//  Pur : pas de Flutter, facile à tester.
// =========================================================

/// Rapport d'une image de télévision.
const double kPictureAspect = 16 / 9;

/// Au-delà, on couperait trop d'image (plus d'un quart) : on plafonne.
const double kMaxFillZoom = 1.34;

/// Taille du cadre vidéo pour un écran de [width] × [height].
///
/// [fill] faux : la plus grande image 16:9 qui tient en entier.
/// [fill] vrai : la plus petite image 16:9 qui couvre tout l'écran,
/// sans dépasser [kMaxFillZoom] fois l'image entière.
({double width, double height}) pictureBox({
  required double width,
  required double height,
  required bool fill,
}) {
  if (width <= 0 || height <= 0) return (width: 0, height: 0);
  final bool wide = width / height >= kPictureAspect;
  // Image entière : limitée par la hauteur si l'écran est plus large.
  final double fitW = wide ? height * kPictureAspect : width;
  final double fitH = wide ? height : width / kPictureAspect;
  if (!fill) return (width: fitW, height: fitH);
  final double coverW = wide ? width : height * kPictureAspect;
  final double zoom = (coverW / fitW).clamp(1.0, kMaxFillZoom);
  return (width: fitW * zoom, height: fitH * zoom);
}

/// Vrai si « Remplir » changerait quelque chose sur cet écran. Sur un
/// écran 16:9 (ou en portrait), le bouton n'a pas lieu d'être.
bool pictureFillUseful({required double width, required double height}) {
  if (width <= 0 || height <= 0) return false;
  return width / height > kPictureAspect * 1.04;
}
