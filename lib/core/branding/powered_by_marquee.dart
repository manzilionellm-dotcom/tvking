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

/// Signature discrète "THE FEW · NOT FOR EVERYONE" — version "shimmer
/// luxe" : le texte reste gris ténu en permanence (textMuted), et toutes
/// les 6 secondes une ligne ember TRAVERSE les lettres de gauche à droite
/// en 1.5s avant de disparaître. Genre signature lumineuse Apple /
/// monogramme Hermès qui s'illumine doucement — pas de défilement,
/// pas d'effet ticker.
///
/// Implémentation :
///   - ShaderMask + LinearGradient avec stops glissants
///   - blendMode srcIn : le shader REMPLACE la couleur du texte
///   - 25% du cycle = shimmer en mouvement, 75% = repos invisible
///   - Respect de MediaQuery.disableAnimationsOf — sans animation,
///     on retombe sur un Text statique en textMuted (aucun cost CPU)
class BrandSignature extends StatefulWidget {
  const BrandSignature({
    super.key,
    this.text = 'THE FEW · NOT FOR EVERYONE',
  });

  final String text;

  @override
  State<BrandSignature> createState() => _BrandSignatureState();
}

class _BrandSignatureState extends State<BrandSignature>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const TextStyle _baseStyle = TextStyle(
    fontSize: 8,
    color: Colors.white, // remplacé par le shader, juste fallback
    letterSpacing: 2.4,
    fontWeight: FontWeight.w600,
    height: 1.0,
  );

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final TextStyle style = AppTextStyles.labelSmall.merge(_baseStyle);

    if (reduceMotion) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: AppColors.textMuted),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, _) {
        // Cycle : 25% premier = shimmer traverse de gauche à droite,
        // 75% restant = invisible à droite (texte purement gris ténu).
        final double t = _ctrl.value;
        final double shimmerX = t < 0.25 ? -0.3 + (t / 0.25) * 1.6 : 2.0;

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) {
            // 3 stops glissants : gris → ember bright → gris.
            // Largeur du highlight = 0.3 (assez court pour rester discret).
            final double s0 = (shimmerX - 0.2).clamp(0.0, 1.0);
            final double s1 = shimmerX.clamp(0.0, 1.0);
            final double s2 = (shimmerX + 0.2).clamp(0.0, 1.0);
            // Garantit stops strictement croissants (LinearGradient l'exige)
            final List<double> stops = <double>[
              s0,
              s1 <= s0 ? s0 + 0.0001 : s1,
              s2 <= s1 ? s1 + 0.0001 : s2,
            ];
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                AppColors.textMuted,
                AppColors.accentBright,
                AppColors.textMuted,
              ],
              stops: stops,
            ).createShader(bounds);
          },
          child: Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        );
      },
    );
  }
}
