import 'package:flutter/material.dart';

/// Canevas TV mis à l'échelle, avec toutes ses mesures dans la même unité.
///
/// Sur un téléphone de 800 px, le canevas de 1280 px est réduit à 62,5 %.
/// Un clavier de 180 px doit donc occuper 288 unités dans ce canevas, sinon
/// Scaffold ne libère réellement que 112,5 px et le clavier cache la saisie.
/// On convertit aussi les zones sûres et les gestes système pour conserver
/// leurs dimensions réelles après le FittedBox. Le rendu TV reste inchangé.
class TvScaledViewport extends StatelessWidget {
  const TvScaledViewport({
    required this.child,
    this.designWidth = 1280,
    super.key,
  }) : assert(designWidth > 0);

  final Widget child;
  final double designWidth;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData screen = MediaQuery.of(context);
    if (screen.size.width <= 0 || screen.size.height <= 0) return child;

    final double factor = designWidth / screen.size.width;
    final Size logicalSize = Size(
      designWidth,
      screen.size.height * factor,
    );
    return MediaQuery(
      data: screen.copyWith(
        size: logicalSize,
        viewInsets: screen.viewInsets * factor,
        padding: screen.padding * factor,
        viewPadding: screen.viewPadding * factor,
        systemGestureInsets: screen.systemGestureInsets * factor,
        textScaler: TextScaler.noScaling,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: logicalSize.width,
          height: logicalSize.height,
          child: child,
        ),
      ),
    );
  }
}
