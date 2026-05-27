// =========================================================
//  subscription_card.dart — Carte état essai/abonnement
// =========================================================
//  Affichée dans Paramètres et À propos. Montre :
//    - Essai actif → "Essai gratuit · 8 jours restants" + bouton
//      "Voir les offres" qui ouvre 7motion.com
//    - Essai expiré → bandeau rouge "Essai terminé" + bouton
//      "Acheter sur 7motion.com" en CTA principal
//    - Payé → "Abonnement actif · expire le 27/05/2027"
//
//  Aucun paiement in-app — tout passe par le site marchand.
// =========================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
                      _titleFor(status, s),
                      style: AppTextStyles.headlineMedium.copyWith(
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _subtitleFor(status),
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
                        ? 'Acheter sur 7motion.com'
                        : 'Voir les offres sur 7motion.com',
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
                'Paiement sécurisé sur le site officiel — '
                'jamais via Google Play.',
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
            'Impossible d\'ouvrir $kPurchaseUrl',
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
      case SubscriptionStatus.unknown:
        return Icons.hourglass_empty_rounded;
    }
  }

  Color _colorFor(SubscriptionStatus s) {
    switch (s) {
      case SubscriptionStatus.paid:
        return AppColors.accent;
      case SubscriptionStatus.trialExpired:
        return AppColors.live;
      case SubscriptionStatus.trialActive:
      case SubscriptionStatus.unknown:
        return AppColors.accent;
    }
  }

  String _titleFor(SubscriptionStatus s, SubscriptionState state) {
    switch (s) {
      case SubscriptionStatus.paid:
        final DateTime? until = state.paidUntil;
        if (until == null) return 'Abonnement actif';
        final String d = '${until.day}/${until.month}/${until.year}';
        return 'Abonnement actif · expire le $d';
      case SubscriptionStatus.trialExpired:
        return 'Essai gratuit terminé';
      case SubscriptionStatus.trialActive:
        final int n = state.trialDaysRemaining;
        if (n == 1) return 'Essai gratuit · 1 jour restant';
        return 'Essai gratuit · $n jours restants';
      case SubscriptionStatus.unknown:
        return 'Chargement…';
    }
  }

  String _subtitleFor(SubscriptionStatus s) {
    switch (s) {
      case SubscriptionStatus.paid:
        return 'Merci pour ton soutien — toutes les fonctions sont '
            'débloquées sur cet appareil et tes autres installations 7 MOTION.';
      case SubscriptionStatus.trialExpired:
        return 'Ton essai gratuit de $kTrialDurationDays jours est terminé. '
            'Souscris l\'abonnement à 13 €/an sur 7motion.com pour continuer.';
      case SubscriptionStatus.trialActive:
        return 'Profite de toutes les fonctions premium pendant ton essai. '
            'Ensuite 13 €/an sur tous tes appareils.';
      case SubscriptionStatus.unknown:
        return '';
    }
  }
}
