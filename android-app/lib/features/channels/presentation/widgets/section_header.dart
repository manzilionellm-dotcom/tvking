// =========================================================
//  section_header.dart — Entête d'une section (titre + lien)
// =========================================================
//  Composant minuscule mais réutilisable : titre à gauche
//  ("Pour vous", "En direct", "Découvertes"...) + lien
//  "Voir tout" à droite.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/tv_focusable.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.onSeeAll,
    super.key,
  });

  final String title;

  /// Si null → on n'affiche pas le bouton "Voir tout".
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            title,
            style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
          ),
          if (onSeeAll != null)
            // Remplace TextButton par TvFocusable : on PERD le ripple
            // Material (cosmétique mineure au tap doigt) mais on GAGNE
            // le focus ring ember cohérent avec le reste de l'app à la
            // télécommande / clavier. Sans ça, le focus système Flutter
            // sur TextButton est un cadre gris quasi-invisible sur fond
            // charbon Cinema Mode → l'utilisateur TV ne sait pas que
            // le bouton est focusé. borderRadius: 8 cohérent avec
            // l'esthétique compacte du lien.
            TvFocusable(
              onTap: onSeeAll!,
              borderRadius: BorderRadius.circular(8),
              showGlow: false,
              semanticsLabel: context.l10n.seeAllOf(title),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      context.l10n.buttonSeeAll,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.accentCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppColors.accentCyan,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
