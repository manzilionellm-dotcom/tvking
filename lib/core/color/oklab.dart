// =========================================================
//  oklab.dart — Espace couleur OKLab / OKLCH (Dart pur, zéro Flutter)
// =========================================================
//  FONDATION du « Caméléon 7 MOTION » (blueprint du 20/08) : toutes les
//  couleurs dynamiques de l'app (ambiance de fond, extraction d'affiche,
//  vecteur circadien) se calculent ICI, dans un espace PERCEPTUEL, puis
//  seulement à la fin sont converties en sRGB pour l'écran.
//
//  POURQUOI PAS Color.lerp ? Il interpole en sRGB : entre deux teintes
//  éloignées, la trajectoire traverse le centre du cube RVB — un gris
//  boueux, et une luminosité qui plonge au milieu (la « zone morte »).
//  OKLab est construit pour que la distance euclidienne approxime la
//  différence PERÇUE : une interpolation y garde une clarté stable.
//
//  Constantes : Björn Ottosson (l'espace de référence de CSS Color 4).
//  Les tests (test/core/color/oklab_test.dart) vérifient ces matrices
//  contre des vecteurs générés par une implémentation INDÉPENDANTE —
//  rouge sRGB → L=0.627955, la valeur publiée par l'auteur.
// =========================================================
import 'dart:math' as math;

/// Couleur en OKLab (cartésien). [l] ∈ [0,1] ; [a]/[b] ≈ [-0.4, 0.4].
class Oklab {
  const Oklab(this.l, this.a, this.b);
  final double l;
  final double a;
  final double b;

  /// Vue polaire : chroma (saturation perceptuelle) et teinte en degrés.
  Oklch toOklch() {
    final double c = math.sqrt(a * a + b * b);
    final double h = (math.atan2(b, a) * 180 / math.pi + 360) % 360;
    return Oklch(l, c, h);
  }

  /// Interpolation CARTÉSIENNE — le cœur du Caméléon : entre un bleu et un
  /// ambre, la trajectoire plonge doucement vers le neutre puis remonte,
  /// au lieu de balayer le vert (ce que ferait une interpolation de teinte).
  static Oklab lerp(Oklab x, Oklab y, double t) => Oklab(
        x.l + (y.l - x.l) * t,
        x.a + (y.a - x.a) * t,
        x.b + (y.b - x.b) * t,
      );

  /// Distance perceptuelle (ΔE OKLab). Sert de seuil anti-scintillement :
  /// deux extractions plus proches que ~0.03 = même ambiance, zéro rebuild.
  double deltaE(Oklab other) {
    final double dl = l - other.l, da = a - other.a, db = b - other.b;
    return math.sqrt(dl * dl + da * da + db * db);
  }
}

/// Couleur en OKLCH (polaire). [h] en degrés [0,360).
class Oklch {
  const Oklch(this.l, this.c, this.h);
  final double l;
  final double c;
  final double h;

  Oklab toOklab() {
    final double rad = h * math.pi / 180;
    return Oklab(l, c * math.cos(rad), c * math.sin(rad));
  }
}

/// Un triplet sRGB 8 bits (0-255) — le format de l'écran.
class Rgb8 {
  const Rgb8(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;

  /// Valeur ARGB 32 bits (alpha plein) — prête pour `Color(value)` côté
  /// Flutter sans que ce fichier dépende de Flutter.
  int get argb => 0xFF000000 | (r << 16) | (g << 8) | b;
}

// ---- Gamma sRGB -----------------------------------------------------------

double _linearize(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _delinearize(double c) => c <= 0.0031308
    ? 12.92 * c
    : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

// ---- Conversions ----------------------------------------------------------

/// sRGB 8 bits → OKLab.
Oklab srgbToOklab(int r8, int g8, int b8) {
  final double r = _linearize(r8 / 255);
  final double g = _linearize(g8 / 255);
  final double b = _linearize(b8 / 255);
  // 1. Cône LMS.
  final double l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
  final double m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
  final double s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
  // 2. Racine cubique — c'est ELLE qui rend l'espace perceptuel.
  final double l_ = _cbrt(l), m_ = _cbrt(m), s_ = _cbrt(s);
  // 3. Projection Lab.
  return Oklab(
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
  );
}

/// OKLab → sRGB 8 bits (canaux bornés : une couleur hors gamut est ÉCRÊTÉE —
/// pour un écrêtage PROPRE qui préserve teinte et clarté, cf. [clampChroma]).
Rgb8 oklabToSrgb(Oklab lab) {
  final double l_ = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
  final double m_ = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
  final double s_ = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b;
  final double l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
  final double r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  final double g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  final double b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
  // NB : num.clamp renvoie `num` — les .toDouble()/.toInt() sont exigés
  // par le typage fort de Dart, pas des fioritures.
  int to8(double v) => (255 * _delinearize(v.clamp(0.0, 1.0).toDouble()))
      .round()
      .clamp(0, 255)
      .toInt();
  return Rgb8(to8(r), to8(g), to8(b));
}

/// La couleur OKLab retombe-t-elle dans le cube sRGB sans écrêtage ?
bool isInSrgbGamut(Oklab lab) {
  final double l_ = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
  final double m_ = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
  final double s_ = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b;
  final double l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
  final double r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  final double g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  final double b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
  const double eps = 1e-6; // tolérance d'arrondi flottant
  return r >= -eps && r <= 1 + eps &&
      g >= -eps && g <= 1 + eps &&
      b >= -eps && b <= 1 + eps;
}

/// Écrêtage de gamut CORRECT (politique CSS Color 4) : on réduit la CHROMA
/// à clarté et teinte constantes, par dichotomie, jusqu'à rentrer dans le
/// cube sRGB. Réduire L changerait la hiérarchie lumineuse ; tourner H
/// changerait l'identité de la couleur — seule la saturation se négocie.
Oklch clampChroma(Oklch color) {
  if (isInSrgbGamut(color.toOklab())) return color;
  double lo = 0, hi = color.c;
  for (int i = 0; i < 14; i++) {
    final double mid = (lo + hi) / 2;
    if (isInSrgbGamut(Oklch(color.l, mid, color.h).toOklab())) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return Oklch(color.l, lo, color.h);
}

/// Racine cubique sûre (les canaux LMS sont ≥ 0 en pratique ; le garde
/// négatif protège des poussières d'arrondi).
double _cbrt(double v) =>
    v <= 0 ? 0 : math.pow(v, 1 / 3).toDouble();
