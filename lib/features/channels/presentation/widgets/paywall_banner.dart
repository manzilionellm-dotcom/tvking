// =========================================================
//  paywall_banner.dart — Bandeau "App payante" (accueil)
// =========================================================
//  Demande utilisateur 2026-06-01 : avertir clairement, sur
//  l'accueil, que l'app est payante.
//
//  Tarifs (validés par l'utilisateur) :
//    - Essai gratuit : 7 jours
//    - 5 €/an
//
//  Le bandeau est tappable : il ouvre la feuille "Ma source"
//  (ajouter ses codes / activer l'app) — l'utilisateur choisit le
//  même chemin que le bouton "+". Style accentEmber (accent éditorial
//  non-critique) pour informer sans agresser comme une alerte rouge.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'source_choice_sheet.dart';

class PaywallBanner extends StatelessWidget {
  const PaywallBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Material(
        color: AppColors.editorialCreamSurface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => showSourceChoiceSheet(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.editorialCream.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: AppColors.editorialCream,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Essai gratuit 7 jours',
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Application payante · puis 5 €/an ou 9,90 € à vie',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Activer',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.editorialCreamDeep,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.editorialCreamDeep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
