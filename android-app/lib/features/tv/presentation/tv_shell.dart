// =========================================================
//  tv_shell.dart — Conteneur racine 10-foot (safe area + fond Maison Noir)
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/app/zuno_edition.dart';
import '../../cast/data/cast_platform.dart';
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
    final bool touch = CastPlatform.zunoEdition == ZunoEdition.touch;
    final Widget content;
    if (!applySafeArea) {
      content = child;
    } else if (touch) {
      // Comme un Scaffold redimensionnable : le formulaire garde une vraie
      // zone défilable au-dessus du clavier. Retirer ensuite cet inset évite
      // qu'un écran enfant le soustraie une seconde fois.
      content = Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TvDimens.touchSafeH,
                vertical: TvDimens.touchSafeV,
              ),
              child: child,
            ),
          ),
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TvDimens.safeH,
          vertical: TvDimens.safeV,
        ),
        child: child,
      );
    }
    return DecoratedBox(
      // Fond FULL-BLEED : radial or très sombre sur noir profond.
      decoration: const BoxDecoration(
          color: TvTokens.bg, gradient: TvTokens.bgGradient),
      // Material TRANSPARENT obligatoire : sans un Material ancêtre, Flutter
      // dessine chaque Text avec un double soulignement jaune (debug). On le
      // met en transparence pour laisser voir le dégradé Maison Noir.
      child: Material(
        type: MaterialType.transparency,
        child: content,
      ),
    );
  }
}
