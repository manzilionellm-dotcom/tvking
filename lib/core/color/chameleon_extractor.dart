// =========================================================
//  chameleon_extractor.dart — Extraction de la couleur d'un contenu
// =========================================================
//  Le « moteur de caméléon » du blueprint 20/08 : à partir des pixels
//  d'une affiche (ou d'un logo de chaîne), trouver LA couleur qui
//  représente le contenu — puis la DOMESTIQUER (le Gouverneur) avant
//  qu'elle ne touche l'interface.
//
//  MÉTHODE : K-means (semis k-means++) en OKLab — clusteriser en RVB
//  donne des centroïdes boueux, la distance RVB n'étant pas perceptuelle.
//  Chaque pixel est PONDÉRÉ par sa chroma (le gris pèse peu) et par sa
//  centralité (le sujet vit au centre de l'affiche, le fond aux bords).
//
//  BUDGET : la grille d'échantillonnage est bornée (48×27 = 1 296 points,
//  8 itérations, k = 5) quelle que soit la taille de l'image → < 8 ms sur
//  une petite box, à exécuter 1 fois par ouverture de fiche, jamais par
//  frame. DÉTERMINISTE : graine fixe → même affiche, même couleur, et des
//  tests reproductibles.
//
//  Dart PUR (dart:typed_data) : le décodage de l'image reste à la charge
//  de l'appelant Flutter (dart:ui) — ce fichier ne voit que des octets.
// =========================================================
import 'dart:math' as math;
import 'dart:typed_data';

import 'oklab.dart';

/// Bornes du GOUVERNEUR : la couleur extraite propose, ces bornes disposent.
/// Sans elles, une affiche fluo repeint l'app en enseigne de casino et un
/// film noir l'éteint complètement.
abstract final class ChameleonGovernor {
  /// Chroma : sous ce plancher, autant rester neutre (l'ambiance maison).
  static const double minChroma = 0.04;

  /// Chroma : au-dessus de ce plafond, l'interface crierait.
  static const double maxChroma = 0.115;

  /// Clarté de l'accent : assez claire pour vivre sur noir. Le texte, lui,
  /// est résolu par APCA — ces bornes ne concernent que l'AMBIANCE.
  static const double minL = 0.62;
  static const double maxL = 0.82;

  /// Seuil anti-scintillement : deux extractions plus proches que ce ΔE
  /// OKLab sont la MÊME ambiance — aucune mutation d'interface.
  static const double stabilityDeltaE = 0.03;

  /// Applique les bornes. Renvoie null si la couleur est trop terne pour
  /// mériter une ambiance (chroma < [minChroma]) : l'appelant garde alors
  /// l'ambiance neutre de l'univers, plutôt qu'un gris teinté douteux.
  static Oklch? govern(Oklch raw) {
    if (raw.c < minChroma) return null;
    return clampChroma(Oklch(
      raw.l.clamp(minL, maxL).toDouble(),
      math.min(raw.c, maxChroma),
      raw.h,
    ));
  }
}

/// Résultat d'une extraction : la couleur DOMINANTE brute (avant gouverneur)
/// et la version gouvernée prête pour l'interface (null = contenu trop
/// terne, garder l'ambiance neutre).
class ChameleonExtraction {
  const ChameleonExtraction({required this.dominant, required this.governed});
  final Oklch dominant;
  final Oklch? governed;
}

/// Extrait la couleur dominante d'une image RGBA ([bytes] = w×h×4 octets,
/// ordre R,G,B,A — le format `rawRgba` de dart:ui).
///
/// [sampleWidth]/[sampleHeight] bornent la grille d'échantillonnage : le
/// coût est CONSTANT quelle que soit la résolution de l'affiche.
ChameleonExtraction extractDominantColor(
  Uint8List bytes,
  int width,
  int height, {
  int sampleWidth = 48,
  int sampleHeight = 27,
}) {
  assert(bytes.length >= width * height * 4,
      'octets RGBA incomplets pour $width×$height');
  final int gw = math.min(sampleWidth, width);
  final int gh = math.min(sampleHeight, height);

  // ---- 1. Échantillonnage en grille + pondération ----
  final List<Oklab> pts = <Oklab>[];
  final List<double> weights = <double>[];
  for (int gy = 0; gy < gh; gy++) {
    for (int gx = 0; gx < gw; gx++) {
      final int px = (gx * (width - 1) / math.max(1, gw - 1)).round();
      final int py = (gy * (height - 1) / math.max(1, gh - 1)).round();
      final int i = (py * width + px) * 4;
      if (bytes[i + 3] < 32) continue; // pixel quasi transparent : ignoré
      final Oklab lab = srgbToOklab(bytes[i], bytes[i + 1], bytes[i + 2]);
      // Centralité : gaussienne centrée — le sujet de l'affiche vit au
      // centre, le fond (souvent noir ou blanc) aux bords.
      final double nx = gx / math.max(1, gw - 1) - 0.5;
      final double ny = gy / math.max(1, gh - 1) - 0.5;
      final double centrality = math.exp(-(nx * nx + ny * ny) * 4);
      final double chroma = math.sqrt(lab.a * lab.a + lab.b * lab.b);
      pts.add(lab);
      weights.add((0.15 + chroma * 3) * centrality); // le gris pèse peu
    }
  }
  if (pts.isEmpty) {
    // Image vide/transparente : neutre assumé (le gouverneur renverra null).
    const Oklch neutral = Oklch(0.5, 0, 0);
    return const ChameleonExtraction(dominant: neutral, governed: null);
  }

  // ---- 2. K-means++ (graine FIXE : déterminisme + tests reproductibles) --
  final math.Random rng = math.Random(7);
  const int k = 5, iterations = 8;
  final List<Oklab> centroids = _kmeansPlusPlusSeeds(pts, weights, k, rng);
  final List<int> assignment = List<int>.filled(pts.length, 0);
  for (int iter = 0; iter < iterations; iter++) {
    // Affectation au centroïde le plus proche (distance OKLab = perçue).
    for (int p = 0; p < pts.length; p++) {
      double best = double.infinity;
      for (int c = 0; c < centroids.length; c++) {
        final double d = _dist2(pts[p], centroids[c]);
        if (d < best) {
          best = d;
          assignment[p] = c;
        }
      }
    }
    // Recentrage pondéré.
    final List<double> sl = List<double>.filled(k, 0),
        sa = List<double>.filled(k, 0),
        sb = List<double>.filled(k, 0),
        sw = List<double>.filled(k, 0);
    for (int p = 0; p < pts.length; p++) {
      final int c = assignment[p];
      final double w = weights[p];
      sl[c] += pts[p].l * w;
      sa[c] += pts[p].a * w;
      sb[c] += pts[p].b * w;
      sw[c] += w;
    }
    for (int c = 0; c < k; c++) {
      if (sw[c] > 0) {
        centroids[c] = Oklab(sl[c] / sw[c], sa[c] / sw[c], sb[c] / sw[c]);
      }
    }
  }

  // ---- 3. Score des clusters : masse pondérée × vivacité ----
  //  Le cluster « sujet » gagne — pas le fond gris, même majoritaire.
  final List<double> mass = List<double>.filled(k, 0);
  for (int p = 0; p < pts.length; p++) {
    mass[assignment[p]] += weights[p];
  }
  int winner = 0;
  double bestScore = -1;
  for (int c = 0; c < k; c++) {
    final Oklch ch = centroids[c].toOklch();
    final double score = mass[c] * (0.25 + ch.c);
    if (score > bestScore) {
      bestScore = score;
      winner = c;
    }
  }
  final Oklch dominant = centroids[winner].toOklch();
  return ChameleonExtraction(
    dominant: dominant,
    governed: ChameleonGovernor.govern(dominant),
  );
}

/// Semis k-means++ : le 1er centroïde est le point de plus fort poids, les
/// suivants sont tirés proportionnellement à leur distance² au plus proche
/// centroïde existant — des graines écartées, une convergence stable.
List<Oklab> _kmeansPlusPlusSeeds(
  List<Oklab> pts,
  List<double> weights,
  int k,
  math.Random rng,
) {
  final List<Oklab> seeds = <Oklab>[];
  int first = 0;
  for (int p = 1; p < pts.length; p++) {
    if (weights[p] > weights[first]) first = p;
  }
  seeds.add(pts[first]);
  while (seeds.length < k) {
    double total = 0;
    final List<double> d2 = List<double>.filled(pts.length, 0);
    for (int p = 0; p < pts.length; p++) {
      double best = double.infinity;
      for (final Oklab s in seeds) {
        final double d = _dist2(pts[p], s);
        if (d < best) best = d;
      }
      d2[p] = best * weights[p];
      total += d2[p];
    }
    if (total <= 0) {
      seeds.add(pts[rng.nextInt(pts.length)]);
      continue;
    }
    double target = rng.nextDouble() * total;
    int chosen = pts.length - 1;
    for (int p = 0; p < pts.length; p++) {
      target -= d2[p];
      if (target <= 0) {
        chosen = p;
        break;
      }
    }
    seeds.add(pts[chosen]);
  }
  return seeds;
}

double _dist2(Oklab x, Oklab y) {
  final double dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b;
  return dl * dl + da * da + db * db;
}
