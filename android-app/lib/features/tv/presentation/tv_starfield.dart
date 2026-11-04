// =========================================================
//  tv_starfield.dart — Ciel d'étoiles, très clairsemé
// =========================================================
//  Rolls-Royce décrit une constellation, pas une pluie
//  (designboom, 2021). Ici : 36 points, très pâles.
//
//  Au-dessus de 2 Go (BoxMemoryBudget.roomy, même seuil que
//  la PR fluidité) chaque point varie lentement. À 2 Go et
//  moins, les points sont fixes : pas de ticker.
//
//  Le widget ignore le pointeur et ne se pose jamais sur
//  l'image : seulement derrière l'interface.
// =========================================================
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/tv_ghost.dart';

class GhostStarfield extends StatelessWidget {
  const GhostStarfield({super.key, required this.animate});

  /// Faux sur les box ≤ 2 Go : ciel immobile.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: animate ? const _Twinkling() : const _Still(),
    );
  }
}

class _Still extends StatelessWidget {
  const _Still();
  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _StarPainter(0));
  }
}

class _Twinkling extends StatefulWidget {
  const _Twinkling();
  @override
  State<_Twinkling> createState() => _TwinklingState();
}

class _TwinklingState extends State<_Twinkling>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      builder: (BuildContext context, _) {
        return CustomPaint(painter: _StarPainter(_clock.value));
      },
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Paint paint = Paint();
    for (int i = 0; i < TvGhost.starCount; i++) {
      final _Star star = _Star.at(i);
      final double wave = t == 0
          ? 0.55
          : 0.35 + 0.65 * (0.5 + 0.5 * math.sin((t + star.phase) * math.pi * 2));
      paint.color = const Color(0xFFF4F6F8).withValues(alpha: 0.05 + 0.16 * wave);
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) => old.t != t;
}

class _Star {
  const _Star(this.x, this.y, this.r, this.phase);
  final double x;
  final double y;
  final double r;
  final double phase;

  /// Positions stables (pas de Random) : le ciel ne saute pas
  /// quand l'écran se reconstruit.
  static _Star at(int i) {
    int n = (i + 1) * 1103515245 + 12345;
    double next() {
      n = (n * 1664525 + 1013904223) & 0x7fffffff;
      return n / 0x7fffffff;
    }

    return _Star(next(), next(), 0.6 + next() * 0.9, next());
  }
}
