// =========================================================
//  glass_card.dart — Effet "glassmorphism" réutilisable
// =========================================================
//  Le glassmorphism = un panneau semi-transparent qui floute
//  ce qu'il y a derrière. Composant central de notre charte VIP.
//
//  Comment ça marche techniquement :
//    1. On utilise `BackdropFilter` qui applique un filtre
//       d'image (ici un flou gaussien) sur ce qu'il y a derrière.
//    2. Par-dessus, on superpose une couleur semi-transparente.
//    3. Et un border subtil pour donner la sensation "verre".
// =========================================================

import 'dart:ui'; // pour ImageFilter

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.borderRadius = 20,
    this.blurSigma = 18,
    this.tint,
    this.borderColor,
    super.key,
  });

  /// Contenu à afficher dans la carte.
  final Widget child;

  /// Rayon des coins arrondis.
  final double borderRadius;

  /// Intensité du flou (plus c'est haut, plus c'est flouté).
  final double blurSigma;

  /// Teinte appliquée par-dessus le flou. Null = on prend la
  /// couleur de surface avec 30 % d'opacité.
  final Color? tint;

  /// Couleur du bord (par défaut blanc à 10 %).
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      // ClipRRect est ESSENTIEL : sinon le flou déborde des coins.
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: tint ?? AppColors.surface.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
