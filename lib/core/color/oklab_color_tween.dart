// =========================================================
//  oklab_color_tween.dart — Interpolation de Color en OKLab (Flutter)
// =========================================================
//  Remplaçant de ColorTween / Color.lerp pour les transitions d'AMBIANCE :
//  Color.lerp interpole en sRGB, où la trajectoire entre deux teintes
//  éloignées traverse le centre du cube RVB — un gris boueux et une
//  luminosité qui plonge au milieu (la « zone morte »). En OKLab
//  (cartésien), la clarté perçue reste stable et les teintes éloignées
//  transitent par le neutre, jamais par des couleurs étrangères.
//  C'est le contrat du blueprint Caméléon (module 1).
// =========================================================
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'oklab.dart';

/// Interpole deux [Color] par le chemin PERCEPTUEL (OKLab cartésien).
/// L'alpha, lui, s'interpole linéairement (c'est une couverture, pas une
/// couleur). null = transparent de même teinte que l'autre borne, comme
/// Color.lerp.
Color? oklabLerpColor(Color? a, Color? b, double t) {
  if (a == null && b == null) return null;
  if (a == null) return oklabLerpColor(b!.withValues(alpha: 0), b, t);
  if (b == null) return oklabLerpColor(a, a.withValues(alpha: 0), t);
  final Oklab la = srgbToOklab(
      (a.r * 255).round(), (a.g * 255).round(), (a.b * 255).round());
  final Oklab lb = srgbToOklab(
      (b.r * 255).round(), (b.g * 255).round(), (b.b * 255).round());
  final Rgb8 mixed = oklabToSrgb(Oklab.lerp(la, lb, t));
  final double alpha = a.a + (b.a - a.a) * t;
  return Color(mixed.argb).withValues(alpha: alpha);
}

/// Tween prêt pour TweenAnimationBuilder / AnimationController.
class OklabColorTween extends Tween<Color?> {
  OklabColorTween({super.begin, super.end});

  @override
  Color? lerp(double t) => oklabLerpColor(begin, end, t);
}
