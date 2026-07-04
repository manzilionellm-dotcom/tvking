// =========================================================
//  tv_shell.dart — Conteneur racine 10-foot (safe area + fond Maison Noir)
// =========================================================
import 'package:flutter/material.dart';

import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';

class TvShell extends StatelessWidget {
  const TvShell({
    super.key,
    required this.child,
    this.applySafeArea = true,
  });

  final Widget child;
  final bool applySafeArea;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Fond FULL-BLEED : radial « cathédrale » sur noir profond, +
      // VIGNETTAGE cinéma par-dessus le contenu (bords très légèrement
      // assombris → regard guidé au centre, moins d'éblouissement le soir).
      decoration: const BoxDecoration(color: TvTokens.bg, gradient: TvTokens.bgGradient),
      foregroundDecoration: const BoxDecoration(gradient: TvTokens.vignette),
      // Material TRANSPARENT obligatoire : sans un Material ancêtre, Flutter
      // dessine chaque Text avec un double soulignement jaune (debug). On le
      // met en transparence pour laisser voir le dégradé Maison Noir.
      child: Material(
        type: MaterialType.transparency,
        child: applySafeArea
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TvDimens.safeH,
                  vertical: TvDimens.safeV,
                ),
                child: child,
              )
            : child,
      ),
    );
  }
}
