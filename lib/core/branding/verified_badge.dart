// =========================================================
//  verified_badge.dart — Badge "Compte vérifié" style Instagram
// =========================================================
//  Petit cercle bleu Instagram avec une coche blanche, à afficher
//  à côté du nom "The Few" pour signifier que c'est l'app
//  officielle / authentifiée.
//
//  Le user a explicitement demandé : "tu mets un titre qui est
//  vérifié, comme sur Instagram ou WhatsApp".
//
//  3 tailles standardisées pour matcher les 3 tailles de BrandLogo.
// =========================================================

import 'package:flutter/material.dart';

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({
    super.key,
    this.size = VerifiedBadgeSize.medium,
  });

  /// Petit (12 dp) — pour les sous-titres et lignes compactes.
  const VerifiedBadge.small({super.key}) : size = VerifiedBadgeSize.small;

  /// Moyen (16 dp) — par défaut, à côté d'un titre de page.
  const VerifiedBadge.medium({super.key}) : size = VerifiedBadgeSize.medium;

  /// Grand (22 dp) — pour les hero / splash.
  const VerifiedBadge.large({super.key}) : size = VerifiedBadgeSize.large;

  final VerifiedBadgeSize size;

  /// Bleu officiel Instagram / Twitter pre-X.
  static const Color _instagramBlue = Color(0xFF1DA1F2);

  double get _dp {
    switch (size) {
      case VerifiedBadgeSize.small:
        return 12;
      case VerifiedBadgeSize.medium:
        return 16;
      case VerifiedBadgeSize.large:
        return 22;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _dp,
      height: _dp,
      decoration: const BoxDecoration(
        color: _instagramBlue,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.check_rounded,
          color: Colors.white,
          size: _dp * 0.75,
          weight: 900,
        ),
      ),
    );
  }
}

enum VerifiedBadgeSize { small, medium, large }
