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
    return DecoratedBox(
      // Fond FULL-BLEED : radial or très sombre sur noir profond.
      decoration: const BoxDecoration(color: TvTokens.bg, gradient: TvTokens.bgGradient),
      child: applySafeArea
          ? Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TvDimens.safeH,
                vertical: TvDimens.safeV,
              ),
              child: child,
            )
          : child,
    );
  }
}
