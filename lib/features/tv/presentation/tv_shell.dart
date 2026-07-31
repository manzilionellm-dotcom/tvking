// =========================================================
//  tv_shell.dart — Conteneur racine 10-foot (safe area + fond Maison Noir)
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// RETOUR UNIVERSEL (audit télécommandes 2026-07-31, D6/D7) : Android ne
  /// transforme en « back » que KEYCODE_BACK. Les box génériques, claviers
  /// HID, air-mouses et manettes émettent Échap / browserBack / exit /
  /// bouton B — qui ne déclenchent JAMAIS popRoute tout seuls : le retour
  /// était MORT sur ce matériel. Ce handler non-focusable, posé ici dans le
  /// shell, couvre tous les écrans TV d'un coup. Il laisse passer tout le
  /// reste (le lecteur, qui gère déjà ces touches, consomme avant nous).
  static KeyEventResult _onBackKeys(BuildContext context, KeyEvent event) {
    final LogicalKeyboardKey k = event.logicalKey;
    final bool isBack = k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.exit ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.gameButtonB;
    if (!isBack) return KeyEventResult.ignored;
    // Pop UNE fois au vrai enfoncement ; répétitions et key-UP consommés
    // (le key-UP relâché vers Android provoquerait un 2e pop).
    if (event is KeyDownEvent) {
      Navigator.of(context).maybePop();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Material TRANSPARENT obligatoire : sans un Material ancêtre, Flutter
    // dessine chaque Text avec un double soulignement jaune (debug). On le
    // met en transparence pour laisser voir le dégradé Maison Noir.
    final Widget content = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (FocusNode node, KeyEvent event) =>
          _onBackKeys(context, event),
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
