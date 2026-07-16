// =========================================================
//  tv_cine_route.dart — Transition « cinéma » entre écrans VOD
// =========================================================
//  Le MaterialPageRoute par défaut (zoom Android) est pensé pour le
//  tactile ; à 3 mètres sur une TV il paraît brusque. Cette route fait un
//  FONDU + léger glissement vertical (220 ms aller, 180 ms retour) — la
//  grammaire des plateformes de cinéma (Netflix/Disney+), douce sans être
//  lente. Utilisée pour les navigations du Cinéma : catalogue → fiche →
//  lecteur. Le reste de l'app garde ses transitions habituelles.
//
//  PERF : fondu + translation = composition GPU pure (aucun relayout par
//  frame), moins coûteux que le zoom Material sur les box modestes.
// =========================================================

import 'package:flutter/widgets.dart';

class TvCineRoute<T> extends PageRouteBuilder<T> {
  TvCineRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (BuildContext context, Animation<double> anim,
                  Animation<double> secondary) =>
              builder(context),
          transitionsBuilder: (BuildContext context, Animation<double> anim,
              Animation<double> secondary, Widget child) {
            final CurvedAnimation curved = CurvedAnimation(
                parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                // 2 % de hauteur : le mouvement se SENT sans se voir.
                position: Tween<Offset>(
                        begin: const Offset(0, 0.02), end: Offset.zero)
                    .animate(curved),
                child: child,
              ),
            );
          },
        );
}
