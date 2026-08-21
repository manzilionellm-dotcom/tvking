// =========================================================
//  tv_shell.dart — Conteneur racine 10-foot (safe area + fond Maison Noir)
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/color/oklab_color_tween.dart';
import '../core/tv_ambience.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';

class TvShell extends StatefulWidget {
  const TvShell({
    super.key,
    required this.child,
    this.applySafeArea = true,
  });

  final Widget child;
  final bool applySafeArea;

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  // HORLOGE CIRCADIENNE (retour client du 21/08 : « la nuit, le jour, c'est
  // le même thème ») : `TvAmbience.glow` est évalué paresseusement — sur une
  // box qui reste allumée SANS navigation, rien ne re-déclenchait de rebuild
  // → le fond restait figé à l'heure de la dernière interaction. Ce tic lent
  // (10 min, imperceptible unité par unité) re-lit la couleur du moment ; le
  // TweenAnimationBuilder fond ensuite la transition. Timer d'ÉTAT (annulé
  // au dispose) — jamais de timer singleton (échec des tests widget).
  Timer? _circadianTick;

  @override
  void initState() {
    super.initState();
    _circadianTick = Timer.periodic(const Duration(minutes: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _circadianTick?.cancel();
    super.dispose();
  }

  Widget get child => widget.child;
  bool get applySafeArea => widget.applySafeArea;

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
    // la teinte de l'univers regardé — et vers la couleur RÉELLE du contenu
    // ouvert (Caméléon : affiche extraite + tempérage circadien, cf.
    // TvAmbience). L'interpolation se fait en OKLab (OklabColorTween) : le
    // chemin entre deux teintes éloignées passe par le neutre, jamais par
    // le gris boueux du lerp sRGB ni par des teintes étrangères. L'arrêt du
    // milieu est DÉRIVÉ de la lumière (lerp OKLab vers le noir) → cohérence.
    return ListenableBuilder(
      listenable: TvAmbience.instance,
      builder: (BuildContext context, _) {
        return TweenAnimationBuilder<Color?>(
          tween: OklabColorTween(end: TvAmbience.instance.glow),
          duration: const Duration(milliseconds: 1600),
          curve: Curves.easeInOut,
          builder: (BuildContext context, Color? glow, Widget? inner) {
            final Color g = glow ?? TvAmbience.instance.glow;
            final Color mid = oklabLerpColor(g, TvTokens.bg, 0.72)!;
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
