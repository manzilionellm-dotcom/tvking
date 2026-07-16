// =========================================================
//  ambient_debug_overlay.dart — HUD de debug du moteur ambiant
// =========================================================
//  Activé UNIQUEMENT par `--dart-define=AMBIENT_DEBUG=true` : la constante
//  est évaluée à la compilation, donc en build normal tout ce fichier est
//  ÉLIMINÉ par le tree-shaking (zéro coût en production).
//
//  Affiche en bas à gauche, par-dessus tout :
//    • les 4 pastilles de la palette courante (primary / glow / scrim /
//      accent) avec leur code hexadécimal ;
//    • la source et la durée de la dernière extraction (« logo 12 ms »),
//      et si elle a été RETENUE par le débounce/ΔE (« retenue » = calculée
//      mais non émise — comportement anti-pompage attendu).
// =========================================================
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'ambient_engine.dart';

/// Drapeau compile-time du mode debug ambiant.
class AmbientDebug {
  const AmbientDebug._();
  static const bool enabled = bool.fromEnvironment('AMBIENT_DEBUG');
}

class AmbientDebugOverlay extends StatelessWidget {
  const AmbientDebugOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // IgnorePointer : le HUD ne doit JAMAIS intercepter le D-pad / touch.
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ValueListenableBuilder<AmbientPalette>(
            valueListenable: AmbientEngine.instance.palette,
            builder: (BuildContext context, AmbientPalette p, _) {
              return ValueListenableBuilder<AmbientDebugStats?>(
                valueListenable: AmbientEngine.instance.debugStats,
                builder: (BuildContext context, AmbientDebugStats? s, __) {
                  final double? lum =
                      AmbientEngine.instance.videoLuminance.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.voidSurface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _Swatch('primary', p.primary),
                              _Swatch('glow', p.glow),
                              _Swatch('scrim', p.scrim),
                              _Swatch('accent', p.accent),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            <String>[
                              if (s != null)
                                '${s.source} · ${s.elapsedMs} ms'
                                    '${s.emitted ? '' : ' · retenue'}',
                              if (lum != null)
                                'lum ${(lum * 100).round()} %',
                              if (s == null) 'en attente d\'une source…',
                            ].join('  ·  '),
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 28,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.border),
            ),
          ),
          Text('$label\n$hex',
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
