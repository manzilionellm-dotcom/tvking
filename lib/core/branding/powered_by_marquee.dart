// =========================================================
//  powered_by_marquee.dart — Bandeau défilant signature
// =========================================================
//  Petit bandeau ember qui défile horizontalement de droite
//  à gauche avec la signature "POWERED BY 7 — THE FEW · NOT
//  FOR EVERYONE". Sert de marque de la maison sur :
//
//    - Le splash (juste sous le logo, discret)
//    - Le pied de l'écran d'accueil (au-dessus du bottom nav)
//
//  Implémentation pure Flutter sans dépendance — un
//  `AnimatedBuilder` + `Transform.translate` qui boucle.
//  Respecte `MediaQuery.disableAnimationsOf` (s'arrête en
//  reduced-motion et affiche le texte statique).
// =========================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class PoweredByMarquee extends StatefulWidget {
  const PoweredByMarquee({
    super.key,
    this.text = 'POWERED BY 7 — THE FEW · NOT FOR EVERYONE',
    this.duration = const Duration(seconds: 18),
    this.height = 30,
    this.tinted = true,
  });

  /// Si `true`, ajoute un fond très légèrement teinté ember pour
  /// que la bande soit visible même sur fond ultra-sombre.
  final bool tinted;

  /// Le texte qui défile. Sera répété autant de fois que
  /// nécessaire pour remplir la largeur.
  final String text;

  /// Durée d'une boucle complète (le texte traverse l'écran
  /// de droite à gauche en `duration`).
  final Duration duration;

  /// Hauteur de la bande.
  final double height;

  @override
  State<PoweredByMarquee> createState() => _PoweredByMarqueeState();
}

class _PoweredByMarqueeState extends State<PoweredByMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
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
    final TextStyle style = AppTextStyles.labelSmall.copyWith(
      color: AppColors.accent,
      fontSize: 11,
      letterSpacing: 2.6,
      fontWeight: FontWeight.w700,
    );

    return Container(
      height: widget.height,
      decoration: widget.tinted
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  AppColors.accent.withValues(alpha: 0.0),
                  AppColors.accent.withValues(alpha: 0.08),
                  AppColors.accent.withValues(alpha: 0.0),
                ],
              ),
              border: Border(
                top: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  width: 0.5,
                ),
                bottom: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  width: 0.5,
                ),
              ),
            )
          : null,
      child: ClipRect(
        child: reduceMotion
            ? _staticBand(style)
            : LayoutBuilder(
                builder: (BuildContext _, BoxConstraints cons) {
                  // On répète le texte avec un séparateur pour
                  // remplir au moins 2x la largeur de l'écran,
                  // sinon une boucle ne se voit pas si le texte
                  // est plus court que l'écran.
                  return AnimatedBuilder(
                    animation: _ctrl,
                    builder: (BuildContext context, Widget? child) {
                      final TextPainter tp = TextPainter(
                        text: TextSpan(
                          text: '${widget.text}    ',
                          style: style,
                        ),
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                      )..layout();
                      final double unit = tp.width;
                      final int repeats =
                          ((cons.maxWidth / unit).ceil() + 2).clamp(2, 20);
                      final String full =
                          List<String>.generate(repeats, (_) => widget.text)
                              .join('    ');
                      final double dx =
                          -_ctrl.value * (unit * (repeats / 2));

                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: <Widget>[
                          Transform.translate(
                            offset: Offset(dx, 0),
                            child: Text(
                              full,
                              maxLines: 1,
                              softWrap: false,
                              style: style,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _staticBand(TextStyle style) {
    return Center(
      child: Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
