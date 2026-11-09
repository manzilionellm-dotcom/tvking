// =========================================================
//  tv_glass.dart — Verre dépoli, seulement si la box peut
// =========================================================
//  Le flou (BackdropFilter) relit les pixels derrière la carte.
//  Sur une box à 1 ou 2 Go, ça se voit en saccades. On ne le
//  demande que si la RAM dépasse 2 Go ET que le système n'a pas
//  marqué l'appareil « low RAM ». Sinon : le même verre, en aplat
//  translucide, sans filtre.
//
//  Inconnu (PC, plugin absent, 0 Mo) → pas de flou. Le défaut
//  prudent est le même que le cache d'images du boot.
// =========================================================
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app/box_memory_budget.dart';
import '../../../core/theme/app_colors.dart';
import '../core/tv_app_tokens.dart';
import '../core/tv_ghost.dart';
import '../core/tv_tokens.dart';

const MethodChannel _glassDevice =
    MethodChannel('com.manzilionellm.tvking/device');

/// Vrai seulement au-dessus de 2 Go, et jamais si Android dit low RAM.
bool tvGlassBlurAllowed({required int totalMb, required bool lowRam}) {
  if (lowRam) return false;
  if (totalMb <= 2048) return false;
  return true;
}

/// Décision lue une fois. Les cartes écoutent [blur].
abstract final class TvGlass {
  static final ValueNotifier<bool> blur = ValueNotifier<bool>(false);
  static bool _asked = false;

  static Future<void> detect() async {
    if (_asked) return;
    _asked = true;
    try {
      final Object? raw =
          await _glassDevice.invokeMethod<Object?>('getMemoryInfo');
      if (raw is! Map) return;
      final int totalMb = (raw['totalMb'] as num?)?.toInt() ?? 0;
      final bool lowRam = raw['lowRam'] == true;
      blur.value = tvGlassBlurAllowed(totalMb: totalMb, lowRam: lowRam);
    } catch (_) {
      blur.value = false;
    }
  }

  /// Tests : repartir du défaut prudent.
  @visibleForTesting
  static void debugReset({bool enabled = false}) {
    _asked = false;
    blur.value = enabled;
  }
}

/// Panneau verre. [blur] faux = aplat plus couvrant, même rayon,
/// même liseré cuivre. Pas de deuxième flou à l'intérieur.
class TvGlassPanel extends StatelessWidget {
  const TvGlassPanel({
    super.key,
    required this.child,
    required this.blur,
    this.radius = 22,
    this.padding = const EdgeInsets.all(16),
    this.focused = false,
  });

  final Widget child;
  final bool blur;
  final double radius;
  final EdgeInsets padding;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final bool phantom = TvAppTokens.of(context).ghost;
    final Color edge = phantom
        ? TvGhost.platinum.withValues(alpha: focused ? 0.92 : 0.42)
        : TvTokens.accent.withValues(alpha: focused ? 0.72 : 0.26);
    // Aplat : le flou a besoin de transparence. Sans flou, on
    // couvre plus pour que le texte reste lisible sur l'obsidienne.
    final Color fill = phantom
        ? AppColors.stealthGlass
        : TvTokens.bg.withValues(alpha: blur ? 0.42 : 0.86);
    final Widget sheet = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edge, width: phantom ? 1 : (focused ? 1.5 : 1)),
        boxShadow: phantom && focused && BoxMemoryBudget.paintFocusGlow
            ? <BoxShadow>[
                BoxShadow(
                  color: TvGhost.ice.withValues(alpha: 0.22),
                  blurRadius: 14,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blur && !MediaQuery.disableAnimationsOf(context)
          ? BackdropFilter(
              // Sigma court : un voile, pas un brouillard. Deux panneaux
              // au plus sur l'accueil (héros + colonne).
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: sheet,
            )
          : sheet,
    );
  }
}
