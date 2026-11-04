// =========================================================
//  tv_card_shine.dart — Balayage et onde, courts
// =========================================================
//  Apple TV (Human Interface Guidelines, Focus and selection) :
//  l'élément focalisé s'éclaire, et le choix donne un retour
//  immédiat, bref.
//  https://developer.apple.com/design/human-interface-guidelines/focus-and-selection
//  Android TV (Focus system) : bordure, lueur, couleur, état
//  pressé tant que OK est tenu.
//  https://developer.android.com/design/ui/tv/guides/styles/focus-system
//
//  Ici : un reflet qui traverse la carte en 240 ms, et une onde
//  au centre (la télécommande n'a pas de point de contact) en
//  200 ms. Pas de boucle. Rien de tout ça au-dessus de l'image :
//  le lecteur ne pose pas ce widget sur la surface vidéo.
// =========================================================
import 'package:flutter/material.dart';

import '../core/tv_ghost.dart';

class TvCardShine extends StatelessWidget {
  const TvCardShine({
    super.key,
    required this.sweep,
    required this.pulse,
    required this.radius,
  });

  /// 0 → 1, une fois, à la prise de focus.
  final double sweep;

  /// 0 → 1, une fois, à l'appui OK.
  final double pulse;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    if (sweep <= 0 && pulse <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          painter: _ShinePainter(sweep: sweep, pulse: pulse),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ShinePainter extends CustomPainter {
  const _ShinePainter({required this.sweep, required this.pulse});
  final double sweep;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (sweep > 0 && sweep < 1) {
      final double x = (sweep * 1.4 - 0.2) * size.width;
      final Rect band = Rect.fromLTWH(x - size.width * 0.18, 0, size.width * 0.28, size.height);
      final Paint paint = Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            const Color(0x00F4F6F8),
            const Color(0x55F4F6F8),
            const Color(0x00F4F6F8),
          ],
        ).createShader(band);
      canvas.drawRect(Offset.zero & size, paint);
      final Paint edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = TvGhost.chromeBright.withValues(alpha: 0.55 * (1 - sweep));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
        edge,
      );
    }
    if (pulse > 0 && pulse < 1) {
      final double radius = size.shortestSide * (0.15 + 0.55 * pulse);
      final Paint glow = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            TvGhost.chromeBright.withValues(alpha: 0.28 * (1 - pulse)),
            const Color(0x00F4F6F8),
          ],
        ).createShader(Rect.fromCircle(center: size.center(Offset.zero), radius: radius));
      canvas.drawCircle(size.center(Offset.zero), radius, glow);
    }
  }

  @override
  bool shouldRepaint(covariant _ShinePainter old) =>
      old.sweep != sweep || old.pulse != pulse;
}
