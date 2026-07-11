// =========================================================
//  subscription_card.dart — Carte état essai/abonnement
// =========================================================
//  Affichée dans Paramètres et À propos. Montre :
//    - Essai actif → "Essai gratuit · 8 jours restants" + bouton
//      "Voir les offres" qui ouvre 7themotion.com
//    - Essai expiré → bandeau rouge "Essai terminé" + bouton
//      "Acheter sur 7themotion.com" en CTA principal
//    - Payé → "Abonnement actif · expire le 27/05/2027"
//
//  Aucun paiement in-app — tout passe par le site marchand.
// =========================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/subscription_state.dart';

class SubscriptionCard extends StatelessWidget {
  const SubscriptionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionState.instance,
      builder: (BuildContext context, _) {
        final SubscriptionState s = SubscriptionState.instance;
        final SubscriptionStatus status = s.status;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: status == SubscriptionStatus.trialExpired
                  ? AppColors.live.withValues(alpha: 0.7)
                  : AppColors.accent.withValues(alpha: 0.45),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    _iconFor(status),
                    color: _colorFor(status),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _titleFor(context, status, s),
                      style: AppTextStyles.headlineMedium.copyWith(
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _subtitleFor(context, status),
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openPurchaseUrl(context),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(
                    status == SubscriptionStatus.trialExpired
                        ? context.l10n.subCardBuyExpired
                        : context.l10n.subCardSeeOffers,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: status == SubscriptionStatus.trialExpired
                        ? AppColors.live
                        : AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.subCardSecurePayment,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPurchaseUrl(BuildContext context) async {
    final Uri uri = Uri.parse(kPurchaseUrl);
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.live,
          content: Text(
            context.l10n.subCantOpenUrl(kPurchaseUrl),
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    }
  }

  IconData _iconFor(SubscriptionStatus s) {
    switch (s) {
      case SubscriptionStatus.paid:
        return Icons.workspace_premium_rounded;
      case SubscriptionStatus.trialExpired:
        return Icons.lock_clock_rounded;
      case SubscriptionStatus.trialActive:
        return Icons.celebration_outlined;
      case SubscriptionStatus.frozen:
        return Icons.ac_unit_rounded;
      case SubscriptionStatus.banned:
        return Icons.block_rounded;
      case SubscriptionStatus.unknown:
        return Icons.hourglass_empty_rounded;
    }
  }

  Color _colorFor(SubscriptionStatus s) {
    switch (s) {
      case SubscriptionStatus.paid:
        return AppColors.accent;
      case SubscriptionStatus.trialExpired:
      case SubscriptionStatus.banned:
        return AppColors.live;
      case SubscriptionStatus.frozen:
        return AppColors.warning;
      case SubscriptionStatus.trialActive:
      case SubscriptionStatus.unknown:
        return AppColors.accent;
    }
  }

  String _titleFor(
      BuildContext context, SubscriptionStatus s, SubscriptionState state) {
    switch (s) {
      case SubscriptionStatus.paid:
        // À vie → libellé dédié (pas de date). Sinon « expire le … »
        // si on a une date, ou « Abonnement actif » à défaut.
        if (state.isLifetime) return context.l10n.subActiveLifetime;
        final DateTime? until = state.paidUntil;
        if (until == null) return context.l10n.subActiveTitle;
        // Date courte localisée (ordre jour/mois/année selon la langue).
        final String d =
            MaterialLocalizations.of(context).formatCompactDate(until);
        return context.l10n.subActiveUntil(d);
      case SubscriptionStatus.trialExpired:
        return context.l10n.subTrialEnded;
      case SubscriptionStatus.trialActive:
        final int n = state.trialDaysRemaining;
        if (n == 1) return context.l10n.subTrialOneDayLeft;
        return context.l10n.subTrialDaysLeft(n);
      case SubscriptionStatus.frozen:
        return context.l10n.subAccountFrozen;
      case SubscriptionStatus.banned:
        return context.l10n.subAccountSuspended;
      case SubscriptionStatus.unknown:
        return context.l10n.subLoading;
    }
  }

  String _subtitleFor(BuildContext context, SubscriptionStatus s) {
    switch (s) {
      case SubscriptionStatus.paid:
        return context.l10n.subCardSubPaid;
      case SubscriptionStatus.trialExpired:
        return context.l10n.subCardSubExpired(kTrialDurationDays);
      case SubscriptionStatus.trialActive:
        return context.l10n.subCardSubTrial;
      case SubscriptionStatus.frozen:
        return context.l10n.subCardSubFrozen;
      case SubscriptionStatus.banned:
        return context.l10n.subCardSubBanned;
      case SubscriptionStatus.unknown:
        return '';
    }
  }
}
