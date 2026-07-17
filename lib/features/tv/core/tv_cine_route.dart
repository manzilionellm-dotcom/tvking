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

// `material.dart` (et pas seulement widgets.dart) : la route pose un
// Material transparent autour de chaque écran (cf. commentaire plus bas).
import 'package:flutter/material.dart';

class TvCineRoute<T> extends PageRouteBuilder<T> {
  TvCineRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          // Material TRANSPARENT obligatoire : les écrans Cinéma n'ont pas
          // tous un Scaffold à eux — sans un Material ancêtre, chaque Text
          // part en « secours » Flutter (jaune souligné, police monospace).
          // C'était le bug des « lignes jaunes » vu sur le terrain
          // (2026-07-17). Le wrap ici couvre TOUTE navigation Cinéma.
          pageBuilder: (BuildContext context, Animation<double> anim,
                  Animation<double> secondary) =>
              Material(
                  type: MaterialType.transparency, child: builder(context)),
          transitionsBuilder: (BuildContext context, Animation<double> anim,
              Animation<double> secondary, Widget child) {
            final CurvedAnimation curved =
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
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
