// =========================================================
//  tv_light_intro.dart — Intro très courte au premier écran
// =========================================================
//  Un fondu du logo déjà dans l'application, moins d'une seconde,
//  puis il disparaît de l'arbre. Pas de nouvelle image, pas de
//  police à charger, pas de scale : sur une box lente, animer
//  la taille relance la mise en page. L'opacité, elle, ne fait
//  que repeindre.
//
//  L'accueil se construit dessous pendant ce temps : on ne
//  retarde pas le chargement des chaînes. Une touche, un appui,
//  ou « réduire les animations » dans le système saute l'intro.
//  Elle ne se rejoue pas tant que le process vit.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_app_tokens.dart';
import '../core/tv_dimens.dart';
import 'tv_components.dart';

class TvLightIntro extends StatefulWidget {
  const TvLightIntro({super.key, required this.child});

  final Widget child;

  static bool _seen = false;

  /// Les tests repartent d'un process « froid ».
  @visibleForTesting
  static void debugReset() => _seen = false;

  @override
  State<TvLightIntro> createState() => _TvLightIntroState();
}

class _TvLightIntroState extends State<TvLightIntro>
    with SingleTickerProviderStateMixin {
  /// Apparition du logo, tenue, puis fondu du voile.
  static const Duration _length = Duration(milliseconds: 780);

  late final AnimationController _controller;
  bool _done = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _done = TvLightIntro._seen;
    _controller = AnimationController(vsync: this, duration: _length);
    _controller.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _finish();
      return;
    }
    TvLightIntro._seen = true;
    _controller.forward();
  }

  void _finish() {
    TvLightIntro._seen = true;
    if (_done || !mounted) return;
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0 → 1 sur le premier quart, puis plein jusqu'au fondu final.
  double _logoOpacity(double t) {
    const double rise = 0.28;
    if (t <= 0) return 0;
    if (t < rise) return t / rise;
    return 1;
  }

  /// Le voile reste opaque, puis s'efface sur la fin.
  double _coverOpacity(double t) {
    const double fadeAt = 0.62;
    if (t < fadeAt) return 1;
    final double left = (1 - t) / (1 - fadeAt);
    if (left < 0) return 0;
    if (left > 1) return 1;
    return left;
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                ignoring: t > 0.95,
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (FocusNode node, KeyEvent event) {
                    if (event is KeyDownEvent) {
                      _finish();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                    onTap: _finish,
                    child: Opacity(
                      opacity: _coverOpacity(t),
                      child: ColoredBox(
                        color: TvAppTokens.of(context).bg,
                        child: Center(
                          child: Opacity(
                            opacity: _logoOpacity(t),
                            child: const TvLogo(width: TvDimens.railCardW),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
