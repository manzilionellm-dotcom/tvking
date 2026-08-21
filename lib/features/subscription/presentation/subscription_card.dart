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
        final bool isPaid = status == SubscriptionStatus.paid;
        // Jours restants À AFFICHER (à vie → ~100 ans) — argument concret et
        // rassurant. `null` pour les états sans compte à rebours.
        final int? daysLeft = s.subscriptionDaysLeft;
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
              // Jours restants BIEN VISIBLES (essai OU payant OU à vie). Pour
              // « à vie » on montre ~100 ans (36 500 jours) : un grand nombre
              // rassure le client tout de suite.
              if (daysLeft != null) ...<Widget>[
                const SizedBox(height: 12),
                _daysBadge(context, daysLeft, s.isLifetime),
              ],
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
              // Déjà payé/à vie → AUCUN bouton d'achat ni « offres » (l'essai
              // et l'incitation à activer DISPARAISSENT) : juste la confirmation
              // « abonnement actif ». Sinon (essai / expiré) → le CTA d'achat.
              if (isPaid)
                _activeConfirm(context)
              else ...<Widget>[
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

  /// Formate un nombre de jours avec séparateur de milliers (« 36 500 »).
  String _fmtDays(int d) {
    final String str = d.toString();
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(' '); // fine space
      buf.write(str[i]);
    }
    return buf.toString();
  }

  /// Badge « X jours restants » — bien lisible. Pour « à vie », on ajoute la
  /// mention ~100 ans pour que le grand nombre soit compris.
  Widget _daysBadge(BuildContext context, int days, bool lifetime) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accentSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.event_available_rounded,
              size: 20, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  // Durée HUMAINE (retour client : « 36 500 jours, c'est pas
                  // sexy ») : au-delà de 2 ans → années (« ≈ 100 ans »).
                  days >= 730
                      ? context.l10n.tvYearsRemaining((days / 365).round())
                      : context.l10n.subDaysRemaining(_fmtDays(days)),
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
                if (lifetime)
                  Text(
                    context.l10n.subLifetimeApprox,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Confirmation « abonnement actif » (remplace le bouton d'achat une fois
  /// payé) : plus aucune incitation à activer/acheter.
  Widget _activeConfirm(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.check_circle_rounded,
              size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Text(
            context.l10n.subActiveBadge,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
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
