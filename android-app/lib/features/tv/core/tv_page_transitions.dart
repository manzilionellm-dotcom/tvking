// =========================================================
//  tv_page_transitions.dart — Changement d'écran SANS flash
// =========================================================
//  BUG (01/10/2026) : au RETOUR (touche Retour), l'écran « flashait »
//  comme un flash d'appareil photo.
//
//  CAUSE : l'animation par défaut de Flutter sur Android (zoom Material)
//  fait une CAPTURE de l'écran (« snapshot ») pendant l'animation. Sur les
//  puces graphiques des box bon marché, cette capture est parfois dessinée
//  vide ou blanche pendant une image → flash. En plus, la vidéo (surface
//  Android native) ne suit pas le zoom : elle disparaît d'un coup au milieu
//  d'une image zoomée → autre éclair.
//
//  CORRECTIF : un fondu simple et court, SANS capture ni zoom. Le fond de
//  l'app (TvTokens.bg, sombre) reste toujours dessiné dessous : aucune image
//  blanche possible. C'est aussi le comportement des apps Android TV (fondu
//  discret), plus calme pour l'œil.
// =========================================================
import 'package:flutter/material.dart';

/// Fondu de 150 ms environ (la route dure 300 ms, la courbe finit à mi-course).
class TvFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const TvFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
        reverseCurve: const Interval(0, 0.5, curve: Curves.easeIn),
      ),
      child: child,
    );
  }
}

/// Même transition sur toutes les plateformes (box Android, PC Windows).
const PageTransitionsTheme kTvPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: TvFadePageTransitionsBuilder(),
    TargetPlatform.windows: TvFadePageTransitionsBuilder(),
    TargetPlatform.linux: TvFadePageTransitionsBuilder(),
    TargetPlatform.macOS: TvFadePageTransitionsBuilder(),
    TargetPlatform.iOS: TvFadePageTransitionsBuilder(),
    TargetPlatform.fuchsia: TvFadePageTransitionsBuilder(),
  },
);
