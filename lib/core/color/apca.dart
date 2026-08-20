// =========================================================
//  apca.dart — Contraste perceptuel APCA (candidat WCAG 3) en Dart pur
// =========================================================
//  POURQUOI PAS WCAG 2 (ratio 4.5:1) ? Il sur-note les paires sombres :
//  un gris moyen sur noir « passe » au ratio alors qu'il est illisible à
//  3 mètres. APCA modélise la perception réelle, AVEC la polarité
//  (texte clair sur fond sombre — notre cas permanent en 10-foot).
//
//  Le contrat du Caméléon : quelle que soit la couleur absorbée par
//  l'interface, le TEXTE ne négocie pas — sa clarté L est RÉSOLUE
//  ([resolveTextL]) pour atteindre le Lc cible, pas choisie à l'œil.
//
//  Constantes : APCA-W3 0.0.98G-4g. Vecteurs de référence des tests
//  générés par une implémentation indépendante (blanc sur noir :
//  Lc = −107.88, la valeur canonique de l'algorithme).
// =========================================================
import 'dart:math' as math;

import 'oklab.dart';

/// Luminance écran au sens APCA (entrées sRGB 0-255).
double apcaLuminance(int r, int g, int b) {
  double f(int c) => math.pow(c / 255, 2.4).toDouble();
  final double y = 0.2126729 * f(r) + 0.7151522 * f(g) + 0.0721750 * f(b);
  // « Soft clamp » des noirs : modélise la diffusion lumineuse dans l'œil
  // (un noir d'écran n'est jamais un noir optique parfait).
  return y < 0.022 ? y + math.pow(0.022 - y, 1.414).toDouble() : y;
}

/// Contraste APCA signé. Positif = texte sombre sur fond clair ;
/// NÉGATIF = texte clair sur fond sombre (notre monde TV).
/// Comparer toujours en valeur absolue aux cibles (90 / 75 / 60 / 45).
double apcaContrast({required double textY, required double backgroundY}) {
  if ((backgroundY - textY).abs() < 0.0005) return 0;
  if (backgroundY > textY) {
    // Polarité normale : texte sombre sur fond clair.
    final double s =
        (math.pow(backgroundY, 0.56) - math.pow(textY, 0.57)).toDouble() *
            1.14;
    return s < 0.1 ? 0 : (s - 0.027) * 100;
  }
  // Polarité inverse : texte clair sur fond sombre.
  final double s =
      (math.pow(backgroundY, 0.65) - math.pow(textY, 0.62)).toDouble() * 1.14;
  return s > -0.1 ? 0 : (s + 0.027) * 100;
}

/// Raccourci : Lc entre deux couleurs sRGB 8 bits.
double apcaContrastRgb({required Rgb8 text, required Rgb8 background}) =>
    apcaContrast(
      textY: apcaLuminance(text.r, text.g, text.b),
      backgroundY: apcaLuminance(background.r, background.g, background.b),
    );

/// LE RÉSOLVEUR : trouve la clarté L minimale d'un texte CLAIR (teinte [h],
/// chroma [c] fixées) atteignant |Lc| ≥ [targetLc] sur [background].
/// À teinte/chroma fixées, L est monotone vis-à-vis du contraste → une
/// dichotomie suffit (14 pas ≈ précision 6·10⁻⁵ sur L). Coût : quelques
/// microsecondes, payé UNE fois par mutation de thème, jamais par frame.
/// Renvoie null si même L=1 (blanc) n'atteint pas la cible — le fond est
/// alors trop clair pour du texte clair : c'est à l'appelant d'assombrir
/// son fond, pas au texte de tricher.
double? resolveTextL({
  required Rgb8 background,
  required double chroma,
  required double hueDeg,
  required double targetLc,
}) {
  final double backgroundY =
      apcaLuminance(background.r, background.g, background.b);
  double lcAt(double l) {
    final Rgb8 c = oklabToSrgb(clampChroma(Oklch(l, chroma, hueDeg)).toOklab());
    return apcaContrast(
      textY: apcaLuminance(c.r, c.g, c.b),
      backgroundY: backgroundY,
    ).abs();
  }

  if (lcAt(1.0) < targetLc) return null; // même le blanc ne suffit pas
  double lo = 0.4, hi = 1.0;
  for (int i = 0; i < 14; i++) {
    final double mid = (lo + hi) / 2;
    if (lcAt(mid) >= targetLc) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return hi; // premier L qui passe — le plus doux possible, jamais moins
}

/// Cibles maison (politique 10-foot du blueprint Caméléon) : à 3 m, un
/// corps de texte est « petit » — on vise la classe APCA la plus stricte.
abstract final class ApcaTargets {
  static const double body = 90; // corps, EPG
  static const double secondary = 75; // sous-titres de cartes, métadonnées
  static const double tertiary = 60; // hints — jamais d'info essentielle
  static const double largeTitle = 60; // ≥ 32 px gras : la taille achète du Lc
  static const double nonText = 45; // anneau de focus D-pad, icônes
}
