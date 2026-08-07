// =========================================================
//  pricing_banner.dart — Bloc « Nos offres » (prix lisibles)
// =========================================================
//  Carte compacte et premium affichant les tarifs en € dès l'ouverture
//  de l'app (demande client : le prix doit être lisible tout de suite) :
//    [ À vie  9,9 € ]   [ 1 an  4,9 € ]
//    Essai gratuit 7 jours
//    + un message promo/bonus si le panel l'a activé.
//
//  100 % piloté par le panel via PricingRepository (réactif). Couleurs et
//  tailles uniquement via AppColors / AppTextStyles. Aucun lien au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/update/build_flags.dart';
import '../data/pricing_repository.dart';

class PricingBanner extends StatelessWidget {
  const PricingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // BUILD GOOGLE PLAY : ce bloc n'existe pas. Afficher des tarifs en €
    // payables HORS Google Play Billing viole la règle Paiements du Play
    // Store (motif de refus classique des lecteurs IPTV). Le build Play est
    // un simple lecteur ; l'APK sideload GitHub, lui, garde les offres.
    // Auto-gardé ICI pour que TOUS les points d'usage (activation, écran
    // bloquant, feuilles) disparaissent d'un coup, sans oubli possible.
    if (kIsPlayBuild) return const SizedBox.shrink();
    return ValueListenableBuilder<PricingConfig>(
      valueListenable: PricingRepository.notifier,
      builder: (BuildContext context, PricingConfig p, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                context.l10n.pricingOffersTitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 11,
                  letterSpacing: 1.6,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 12),
              // Les deux offres côte à côte (à vie mise en avant à gauche).
              Row(
                children: <Widget>[
                  Expanded(
                    child: _OfferTile(
                      label: context.l10n.pricingLifetime,
                      price: p.lifetimeLabel,
                      highlight: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OfferTile(
                      label: context.l10n.pricingYearly,
                      price: p.yearlyLabel,
                      highlight: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Essai gratuit (durée pilotée par le panel).
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.card_giftcard_rounded,
                      size: 16, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.pricingTrialDays(p.trialDays),
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              // Message promo / bonus (seulement si activé au panel).
              if (p.promoEnabled && p.promoMessage.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accentSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.local_offer_rounded,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.promoMessage,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 12.5,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Une offre (À vie / 1 an) : libellé + prix bien gros et lisible.
class _OfferTile extends StatelessWidget {
  const _OfferTile({
    required this.label,
    required this.price,
    required this.highlight,
  });

  final String label;
  final String price;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: highlight ? AppColors.accentSurface : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? AppColors.accent.withValues(alpha: 0.6)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 11,
              letterSpacing: 0.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            price,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headlineLarge.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: highlight ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
