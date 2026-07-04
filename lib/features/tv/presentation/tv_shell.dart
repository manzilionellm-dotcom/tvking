// =========================================================
//  tv_shell.dart — Conteneur racine 10-foot (safe area + fond Maison Noir)
// =========================================================
import 'package:flutter/material.dart';

import '../core/tv_ambience.dart';
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
    // Material TRANSPARENT obligatoire : sans un Material ancêtre, Flutter
    // dessine chaque Text avec un double soulignement jaune (debug). On le
    // met en transparence pour laisser voir le dégradé Maison Noir.
    final Widget content = Material(
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
    );
    // AMBIANCES INTELLIGENTES : la « lumière » du fond glisse en ~1,6 s vers
    // la teinte de l'univers regardé (or à l'accueil, ambre au cinéma, indigo
    // en séries, vert stade au sport). Un seul ColorTween ; l'arrêt du milieu
    // est DÉRIVÉ de la lumière (lerp vers le noir) → cohérence garantie.
    return ListenableBuilder(
      listenable: TvAmbience.instance,
      builder: (BuildContext context, _) {
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: TvAmbience.instance.glow),
          duration: const Duration(milliseconds: 1600),
          curve: Curves.easeInOut,
          builder: (BuildContext context, Color? glow, Widget? inner) {
            final Color g = glow ?? TvAmbience.instance.glow;
            final Color mid = Color.lerp(g, TvTokens.bg, 0.72)!;
            return Container(
              // Fond FULL-BLEED : radial « cathédrale » teinté par l'ambiance,
              // + VIGNETTAGE cinéma par-dessus le contenu (bords légèrement
              // assombris → regard guidé au centre, moins d'éblouissement).
              decoration: BoxDecoration(
                color: TvTokens.bg,
                gradient: RadialGradient(
                  center: const Alignment(0.56, -0.40),
                  radius: 1.45,
                  colors: <Color>[g, mid, TvTokens.bg],
                  stops: const <double>[0.0, 0.52, 0.95],
                ),
              ),
              foregroundDecoration:
                  const BoxDecoration(gradient: TvTokens.vignette),
              child: inner,
            );
          },
          child: content,
        );
      },
    );
  }
}
