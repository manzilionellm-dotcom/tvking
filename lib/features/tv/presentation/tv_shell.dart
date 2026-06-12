// =========================================================
//  tv_shell.dart — Conteneur racine 10-foot (§2 safe area)
// =========================================================
//  • Fond FULL-BLEED : il remplit tout l'écran, jamais rogné.
//  • Contenu confiné dans la SAFE AREA (48 dp H / 24 dp V) : aucun
//    texte/bouton/logo ne touche le bord (overscan TV).
//  • Le fond peut déborder hors safe area (c'est voulu).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../core/tv_dimens.dart';

class TvShell extends StatelessWidget {
  const TvShell({
    super.key,
    required this.child,
    this.background,
    this.applySafeArea = true,
  });

  /// Contenu de l'écran (confiné dans la safe area).
  final Widget child;

  /// Fond optionnel (image/dégradé) rendu FULL-BLEED derrière. À défaut,
  /// fond sombre uni (§7 thème sombre par défaut).
  final Widget? background;

  /// Certains écrans (lecteur plein écran) veulent gérer la safe area
  /// eux-mêmes → `false`.
  final bool applySafeArea;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        children: <Widget>[
          // Fond full-bleed (déborde volontiers hors safe area).
          if (background != null) Positioned.fill(child: background!),
          // Contenu dans la safe area.
          Positioned.fill(
            child: applySafeArea
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TvDimens.safeH,
                      vertical: TvDimens.safeV,
                    ),
                    child: child,
                  )
                : child,
          ),
        ],
      ),
    );
  }
}
