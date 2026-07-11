// =========================================================
//  legal_disclaimer.dart — Mention légale The Few
// =========================================================
//  Bandeau réutilisable à afficher PARTOUT où l'utilisateur
//  pourrait s'interroger sur la légalité de l'app et confondre
//  "The Few" avec un fournisseur IPTV :
//
//    - À propos (en haut, avant Aide VIP)
//    - Onboarding (1er lancement, avant choix appareil)
//    - Ajout d'une playlist (avant le formulaire URL)
//    - Aide VIP (FAQ "Où trouver un fournisseur ?")
//
//  Message TiViMate-style : on vend l'APP (le lecteur), pas
//  les flux. Le client doit apporter sa propre URL IPTV
//  (M3U / Xtream) auprès du fournisseur de son choix.
//
//  Deux variantes :
//    - LegalDisclaimer.compact : 1 ligne discrète (onboarding,
//      add playlist)
//    - LegalDisclaimer.full : encart complet avec icône + 3 paragraphes
//      (À propos, Aide)
// =========================================================

import 'package:flutter/material.dart';

import '../i18n/l10n_extension.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class LegalDisclaimer extends StatelessWidget {
  /// Affichage condensé — 1 ligne d'info discrète pour les
  /// surfaces où l'espace est rare (onboarding, add playlist).
  const LegalDisclaimer.compact({super.key}) : _full = false;

  /// Affichage complet — encart visible avec icône bouclier,
  /// titre clair, paragraphes structurés. Pour les surfaces
  /// "informatives" (À propos, Aide).
  const LegalDisclaimer.full({super.key}) : _full = true;

  final bool _full;

  @override
  Widget build(BuildContext context) {
    if (!_full) return _buildCompact(context);
    return _buildFull(context);
  }

  Widget _buildCompact(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            color: AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.legalDisclaimerCompactBody,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFull(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.verified_user_outlined,
                color: AppColors.accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.legalDisclaimerTitle,
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.legalDisclaimerFullPara1,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.legalDisclaimerFullPara2,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.legalDisclaimerFullPara3,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
