// =========================================================
//  tv_shell.dart — Conteneur racine 10-foot (safe area + fond Maison Noir)
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/tv_ambient.dart';
import '../core/tv_ambient_director.dart';
import '../core/tv_comfort.dart';
import '../core/tv_dimens.dart';
import '../core/tv_app_tokens.dart';
import 'tv_starfield.dart';

class TvShell extends StatefulWidget {
  const TvShell({super.key, required this.child, this.applySafeArea = true});

  final Widget child;
  final bool applySafeArea;

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> with SingleTickerProviderStateMixin {
  late final AnimationController _blend = AnimationController(
    vsync: this,
    duration: TvAmbientDirector.blend,
  );
  TvAmbientLook? _from;
  TvAmbientLook? _to;
  bool _ambientScheduled = false;

  @override
  void initState() {
    super.initState();
    TvAmbientDirector.instance.addListener(_onAmbient);
    _to = TvAmbientDirector.instance.look;
    _blend.value = 1;
  }

  void _onAmbient() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // L'initState du lecteur peut changer l'ambiance pendant le build de
      // sa route. Le shell encore derrière ne doit pas notifier son animation
      // au milieu de ce build. Coalescer, puis relire la toute dernière valeur.
      if (!_ambientScheduled) {
        _ambientScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ambientScheduled = false;
          if (mounted) _onAmbient();
        });
      }
      return;
    }
    final TvAmbientLook? next = TvAmbientDirector.instance.look;
    _from = _to;
    _to = next;
    _blend.duration = TvAmbientDirector.instance.animates
        ? TvAmbientDirector.blend
        : Duration.zero;
    _blend.forward(from: 0);
  }

  Gradient _gradient(TvAppTokens palette, double t) {
    // Le halo est calculé sur le soir confort ; Phantom Black garde
    // son propre fond, sans l'or du soir.
    if (palette.light || palette.ghost) return palette.bgGradient;
    final TvAmbientLook evening = TvAmbientLook(
      peak: TvComfortPalette.of(palette.period).ambientPeak,
      bg: palette.bg,
    );
    final TvAmbientLook a = _from ?? evening;
    final TvAmbientLook b = _to ?? evening;
    return TvAmbientLook.lerp(a, b, t).gradient;
  }

  @override
  void dispose() {
    TvAmbientDirector.instance.removeListener(_onAmbient);
    _blend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TvAppTokens palette = TvAppTokens.of(context);
    return AnimatedBuilder(
      animation: _blend,
      builder: (BuildContext context, Widget? child) {
        return DecoratedBox(
          // Fond FULL-BLEED. Le halo de contenu, s'il y en a un,
          // remplace le dégradé du soir. Pas de filtre sur l'image.
          // Material transparent : sans ancêtre Material, Flutter
          // souligne le texte en jaune (debug).
          decoration: BoxDecoration(
            color: palette.bg,
            gradient: _gradient(palette, _blend.value),
          ),
          child: child,
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (palette.ghost) const Positioned.fill(child: PhantomWeave()),
          Material(
            type: MaterialType.transparency,
            child: widget.applySafeArea
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TvDimens.safeH,
                      vertical: TvDimens.safeV,
                    ),
                    child: widget.child,
                  )
                : widget.child,
          ),
        ],
      ),
    );
  }
}
