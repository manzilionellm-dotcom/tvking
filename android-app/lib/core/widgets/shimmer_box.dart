// =========================================================
//  shimmer_box.dart — Primitive de squelette shimmer réutilisable
// =========================================================
//  Brief design : remplacer les spinners par des squelettes
//  cinématiques (loading state premium, façon Apple TV+ / Disney+).
//
//  Architecture (perf) :
//    - `Shimmer` : UN seul AnimationController pour tout un écran
//      de placeholders. Il diffuse la phase courante via un
//      InheritedWidget (`_ShimmerScope`). Créer un controller par
//      box coûterait cher (CPU + batterie) sur une grille de 12.
//    - `ShimmerBox` : un rectangle qui peint un gradient mouvant
//      en lisant la phase de l'ancêtre `Shimmer`. Sans ancêtre,
//      il se rend en statique (graceful, jamais de crash).
//
//  Context-aware : couleurs via `LumiereColors.of(context)` → marche
//  en Cinema Mode ET Daylight Mode, et pour les deux flavors.
//  Accessibilité : respecte « Réduire les animations » du système
//  (MediaQuery.disableAnimationsOf) → phase figée, pas de mouvement.
// =========================================================

import 'package:flutter/material.dart';

import '../theme/cinematic_spacing.dart';
import '../theme/lumiere_tokens.dart';

/// Pilote d'animation partagé pour un groupe de [ShimmerBox].
class Shimmer extends StatefulWidget {
  const Shimmer({
    required this.child,
    this.period = const Duration(milliseconds: 1300),
    super.key,
  });

  final Widget child;

  /// Durée d'un cycle complet du balayage shimmer.
  final Duration period;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _ctrl,
      // L'enfant est construit UNE fois puis réutilisé ; ce sont les
      // ShimmerBox descendants qui se reconstruisent à chaque frame
      // car ils dépendent du `_ShimmerScope` recréé ici.
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        return _ShimmerScope(
          phase: reduceMotion ? 0.5 : _ctrl.value,
          child: child!,
        );
      },
    );
  }
}

/// Diffuse la phase courante du shimmer aux [ShimmerBox] descendants.
class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.phase, required super.child});

  final double phase;

  static _ShimmerScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>();

  @override
  bool updateShouldNotify(_ShimmerScope old) => old.phase != phase;
}

/// Placeholder shimmer. À placer sous un [Shimmer] ancêtre pour
/// l'animation ; sinon rendu statique.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    this.width,
    this.height,
    this.borderRadius,
    this.margin,
    super.key,
  });

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final LumiereColors c = LumiereColors.of(context);
    final double t = _ShimmerScope.maybeOf(context)?.phase ?? 0.5;
    final BorderRadius radius =
        borderRadius ?? BorderRadius.circular(CinematicSpacing.radiusM);

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        // Balayage diagonal : on déplace les alignements du gradient
        // de gauche à droite selon la phase `t` ∈ [0,1].
        gradient: LinearGradient(
          begin: Alignment(-1.0 + t * 2, -0.3),
          end: Alignment(0.0 + t * 2, 0.3),
          colors: <Color>[c.elevated, c.glass, c.elevated],
          stops: const <double>[0.0, 0.5, 1.0],
        ),
        border: Border.all(color: c.border),
      ),
    );
  }
}
