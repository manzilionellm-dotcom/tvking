// =========================================================
//  celebration_overlay.dart — Moment de célébration (paliers de streak)
// =========================================================
//  Récompense variable (Hook) : quand un palier de streak tombe, on
//  offre un vrai MOMENT — burst de particules + carte « X jours d'affilée ».
//
//  ZÉRO dépendance externe : les particules sont dessinées au CustomPaint
//  (pas de package confetti). Respecte `reduce-motion` : si les animations
//  système sont coupées, on montre simplement la carte, sans burst.
//
//  Marque « Maison Noir » respectée : or royal + ember + crème éditoriale
//  sur surface sombre.
// =========================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../haptics/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Affiche la célébration d'un palier de [days] jours consécutifs.
Future<void> showStreakCelebration(BuildContext context, int days) {
  Haptics.success();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (BuildContext _) => _CelebrationDialog(days: days),
  );
}

class _CelebrationDialog extends StatefulWidget {
  const _CelebrationDialog({required this.days});
  final int days;

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.disableAnimationsOf(context);
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (!reduce)
            AnimatedBuilder(
              animation: _c,
              builder: (BuildContext _, Widget? __) => CustomPaint(
                size: const Size(320, 320),
                painter: _BurstPainter(_c.value),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(28),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.royalGold.withValues(alpha: 0.5),
              ),
              boxShadow: AppColors.emberGlowShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('🔥', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(
                  '${widget.days} jours d\'affilée',
                  style: AppTextStyles.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Tu fais partie des habitués. Continue !',
                  style: AppTextStyles.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continuer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Burst de particules radial qui s'estompe (t : 0→1).
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final List<Color> palette = <Color>[
      AppColors.royalGold,
      AppColors.accent,
      AppColors.editorialCream,
    ];
    final double eased = Curves.easeOut.transform(t);
    final double fade = (1.0 - t).clamp(0.0, 1.0);
    for (int i = 0; i < 24; i++) {
      final double a = (i / 24) * 2 * math.pi;
      final double r = eased * 150;
      final Offset p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      final Paint paint = Paint()
        ..color = palette[i % palette.length].withValues(alpha: fade);
      canvas.drawCircle(p, 4 * fade + 1, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
