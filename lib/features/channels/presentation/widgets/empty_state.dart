// =========================================================
//  empty_state.dart — Écran "Ajoute ton abonnement"
// =========================================================
//  Refonte (demande user 2026-06-01) :
//
//    On retire l'ancien écran de connexion revendeur
//    (Identifiant + Code secret + "Activation à distance" par MAC).
//    Nouveau modèle : CHAQUE CLIENT ajoute SON PROPRE code IPTV
//    (Xtream Codes ou M3U) communiqué par son fournisseur.
//
//    Cet écran ne fait donc plus qu'une chose, simple et claire :
//    un gros bouton "Ajouter mes codes" qui ouvre AddPlaylistScreen
//    (onglets Xtream / M3U / M3U en lot). Plus de formulaire de
//    login, plus de bloc MAC.
//
//    On conserve la mention payante (essai 7 j · 13 €/an) car c'est
//    le premier écran que voit un nouvel utilisateur.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/branding/brand_logo.dart';
import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.onAddPlaylist,
    super.key,
  });

  /// Ouvre l'écran d'ajout de codes (Xtream / M3U). Fourni par le
  /// HomeScreen — c'est le seul chemin proposé désormais.
  final VoidCallback onAddPlaylist;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BrandLogo.splash(),
                const SizedBox(height: 26),

                Text(
                  context.l10n.activateSubTitle,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineLarge.copyWith(fontSize: 23),
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.activateSubDesc,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),

                // ----- Mention payante (essai 7 j · 13 €/an) -----
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.editorialCreamSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.editorialCream.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: AppColors.editorialCream,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          context.l10n.freeTrialBadge,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ----- CTA unique : activer / vérifier -----
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: onAddPlaylist,
                    icon: const Icon(Icons.support_agent_rounded, size: 22),
                    label: Text(
                      context.l10n.activateMySub,
                      style: AppTextStyles.button.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.voidSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.remoteActivationByReseller,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
