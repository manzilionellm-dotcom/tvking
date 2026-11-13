// =========================================================
//  tv_glass.dart — Verre du modèle, sans flou sur les box lentes
// =========================================================
//  Le modèle montre des panneaux givrés. Le givre « vrai »
//  (`BackdropFilter`) coûte cher sur les box d'entrée de gamme :
//  c'est le même coût que le halo de focus qu'on coupe déjà quand
//  la box demande moins d'animations.
//
//  Chemin par défaut : un voile translucide + un filet cuivré.
//  Le halo du fond passe au travers. Aucun flou.
//
//  Le flou ne s'allume que si la box a plus de 2 Go ET n'est pas
//  marquée low-RAM, ET que les animations système ne sont pas
//  coupées. Sinon on reste sur l'aplat. `sigma` reste petit (8),
//  jamais le 20–36 du téléphone.
// =========================================================

import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tv_app_tokens.dart';
import 'tv_tokens.dart';

/// Décision « cette box peut flouter un panneau ». Faux tant qu'on
/// n'a pas lu la RAM : le doute profite à la fluidité.
abstract final class TvGlassPolicy {
  static bool _capable = false;
  static bool get capable => _capable;

  static const MethodChannel _device =
      MethodChannel('com.manzilionellm.tvking/device');

  /// Même canal que le réglage du cache d'images. Best-effort.
  static Future<void> load() async {
    try {
      final Object? raw = await _device.invokeMethod<Object?>('getMemoryInfo');
      if (raw is! Map) return;
      final int totalMb = (raw['totalMb'] as num?)?.toInt() ?? 0;
      final bool lowRam = raw['lowRam'] == true;
      _capable = !lowRam && totalMb > 2048;
    } catch (_) {
      _capable = false;
    }
  }

  static bool allowsBlur(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return false;
    return _capable;
  }

  /// Tests : force la décision sans canal natif.
  static void debugSetCapable(bool value) => _capable = value;
}

/// Panneau de verre. [blur] null = la politique (coupée sur box lente).
class TvGlass extends StatelessWidget {
  const TvGlass({
    super.key,
    required this.child,
    this.focused = false,
    this.radius,
    this.blur,
    this.padding,
  });

  final Widget child;
  final bool focused;
  final BorderRadius? radius;
  final bool? blur;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final TvAppTokens palette = TvAppTokens.of(context);
    final BorderRadius boxRadius =
        radius ?? BorderRadius.circular(TvTokens.rCard);
    final bool frost = blur ?? TvGlassPolicy.allowsBlur(context);
    final Widget pane = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.glassFill,
        borderRadius: boxRadius,
        border: Border.all(
          color: focused ? palette.accentBright : palette.glassEdge,
          width: focused ? 1.5 : 1,
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (!frost) return pane;
    return ClipRRect(
      borderRadius: boxRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: pane,
      ),
    );
  }
}
