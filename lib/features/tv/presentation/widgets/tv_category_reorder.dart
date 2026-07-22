// =========================================================
//  tv_category_reorder.dart — Briques PARTAGÉES de réorganisation
// =========================================================
//  Réordonner les catégories (monter / descendre) doit se faire de la MÊME
//  façon premium dans TOUS les templates TV (rail « DIRECT » du Modèle A,
//  « Groupes » du tivimate, « CATÉGORIES » de l'écran chaînes…). Plutôt que
//  de recopier l'animation et les chevrons dans chaque écran, on centralise
//  ici les DEUX briques réutilisables :
//
//    • [TvReorderBounce] : enveloppe qui fait « rebondir » (ressort) son
//      enfant au moment où la ligne est SAISIE — le signal visuel « je suis
//      prêt à monter/descendre » ;
//    • [TvReorderChevrons] : les chevrons dorés ▲ ▼ (+ ✓ terminé), cliquables
//      au doigt, grisés quand l'action est impossible (déjà tout en haut/bas).
//
//  La LOGIQUE d'ordre elle-même reste dans `CategoryOrderStore` (partagé
//  téléphone + TV) ; chaque écran n'a qu'à appeler `applyOrder` + brancher ces
//  deux widgets sur ses lignes.
// =========================================================
import 'package:flutter/material.dart';

import '../../core/tv_tokens.dart';

/// Enveloppe qui fait « rebondir » (petit ressort) son [child] quand [active]
/// passe à `true` — retour visuel premium « ligne saisie, prête à bouger ».
/// Coût nul quand inactive (retourne l'enfant tel quel, sans AnimatedBuilder).
class TvReorderBounce extends StatefulWidget {
  const TvReorderBounce({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<TvReorderBounce> createState() => _TvReorderBounceState();
}

class _TvReorderBounceState extends State<TvReorderBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  // Séquence de rebond : petit dépassement puis retour amorti (spring).
  late final Animation<double> _s =
      TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.12)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 28),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.12, end: 0.97)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 26),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.97, end: 1.04)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 24),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.04, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 22),
  ]).animate(_c);

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant TvReorderBounce old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _s,
      builder: (BuildContext context, Widget? child) =>
          Transform.scale(scale: _s.value, child: child),
      child: widget.child,
    );
  }
}

/// Chevrons DORÉS ▲ ▼ (+ ✓ terminé) affichés à droite d'une catégorie en mode
/// réorganisation. Cliquables au doigt ; grisés quand l'action est impossible.
class TvReorderChevrons extends StatelessWidget {
  const TvReorderChevrons({
    super.key,
    required this.canUp,
    required this.canDown,
    required this.onUp,
    required this.onDown,
    required this.onDone,
  });

  final bool canUp;
  final bool canDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _btn(Icons.keyboard_arrow_up_rounded, canUp, onUp),
        _btn(Icons.keyboard_arrow_down_rounded, canDown, onDown),
        _btn(Icons.check_rounded, true, onDone),
      ],
    );
  }

  Widget _btn(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          icon,
          size: 26,
          color:
              enabled ? TvTokens.gold : TvTokens.gold.withValues(alpha: 0.28),
        ),
      ),
    );
  }
}
