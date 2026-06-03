// =========================================================
//  subscription_gate.dart — Écran bloquant trial/freeze/ban
// =========================================================
//  Affiché par `_AppEntry` quand `SubscriptionState.shouldBlockUser`
//  est `true`. Trois cas, trois messages distincts :
//
//    - banned        → "Compte suspendu définitivement"
//    - frozen        → "Compte gelé temporairement"
//    - trialExpired  → "Essai gratuit terminé, paye 13 €/an"
//
//  Tous proposent un bouton "Contacter le support" (sheet à 2
//  choix message/appel) et pour le trial-expired, un bouton
//  "Acheter" qui ouvre 7themotion.com.
//
//  Le pull-to-refresh est dispo : utile si l'admin vient juste
//  de marquer le client comme payé, le client tire vers le bas
//  pour re-vérifier sans devoir redémarrer l'app.
// =========================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/support/support_choice_sheet.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/subscription_state.dart';

class SubscriptionGateScreen extends StatelessWidget {
  const SubscriptionGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: SubscriptionState.instance,
          builder: (BuildContext context, _) {
            final SubscriptionStatus status =
                SubscriptionState.instance.status;
            final bool banned = status == SubscriptionStatus.banned;
            final bool frozen = status == SubscriptionStatus.frozen;
            final bool expired = status == SubscriptionStatus.trialExpired;

            final String title = banned
                ? 'Compte suspendu'
                : frozen
                    ? 'Compte temporairement gelé'
                    : 'Débloque tout BLACK7 ROYAL';
            final String message = banned
                ? 'Ton compte a été suspendu par l\'administrateur. '
                    'Si tu penses que c\'est une erreur, contacte-nous.'
                : frozen
                    ? 'Ton compte est en pause. Contacte le support '
                        'pour réactiver l\'accès.'
                    : 'Ton essai gratuit de $kTrialDurationDays jours est '
                        'terminé. Active ton accès et profite de TOUT, '
                        'sans aucune limite :';

            return RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.surface,
              onRefresh: () => SubscriptionState.instance.refreshRemote(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(28, 56, 28, 32),
                children: <Widget>[
                  // ----- Brand discret -----
                  Center(
                    child: Column(
                      children: <Widget>[
                        const BrandLogo.compact(),
                        const SizedBox(height: 14),
                        Text('BLACK7 ROYAL',
                            style: AppTextStyles.headlineLarge.copyWith(
                              fontSize: 22,
                              letterSpacing: 4,
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 44),

                  // ----- Icône d'état (verrou/clepsydre/balance) -----
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(alpha: 0.12),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
                      ),
                      child: Icon(
                        banned
                            ? Icons.block_rounded
                            : frozen
                                ? Icons.ac_unit_rounded
                                : Icons.hourglass_bottom_rounded,
                        color: AppColors.accent,
                        size: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),

                  // ----- Titre + message -----
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineLarge
                        .copyWith(fontSize: 22, height: 1.2),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 13.5,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  // ----- Arguments de vente (uniquement essai terminé) -----
                  if (expired) ...<Widget>[
                    const SizedBox(height: 22),
                    _benefits(),
                  ],
                  const SizedBox(height: 28),

                  // ----- CTA principal — Acheter (uniquement trial) -----
                  if (expired)
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: () => _openPurchase(),
                        icon: const Icon(Icons.shopping_bag_rounded, size: 22),
                        label: const Text('M\'abonner — 13 €/an'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.voidSurface,
                          textStyle: AppTextStyles.button.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  if (expired) const SizedBox(height: 10),

                  // ----- Support / Contact -----
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => showSupportChoiceSheet(context),
                      icon: const Icon(Icons.support_agent_rounded, size: 20),
                      label: const Text('Contacter le support'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: BorderSide(
                          color: AppColors.accent.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ----- Pull-to-refresh hint -----
                  Text(
                    'Tu viens de payer ? Tire vers le bas pour rafraîchir.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPurchase() async {
    final Uri url = Uri.parse(kPurchaseUrl);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Liste d'avantages affichee sur l'ecran "essai termine" — des
  /// arguments concrets pour donner envie de s'abonner.
  Widget _benefits() {
    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: AppColors.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 13.5,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: <Widget>[
          row(Icons.movie_filter_rounded,
              'Des milliers de chaînes, films & séries du monde entier'),
          row(Icons.live_tv_rounded,
              'Tout le sport en direct, en HD / 4K, sans coupure'),
          row(Icons.cast_rounded,
              'Caster sur n\'importe quelle télé (Chromecast & Google TV)'),
          row(Icons.fiber_manual_record_rounded,
              'Enregistrer tes émissions, films et matchs préférés'),
          row(Icons.do_not_disturb_on_rounded,
              'Zéro publicité — lecture fluide, instantanée'),
          row(Icons.devices_rounded,
              'Sur tous tes appareils : téléphone, tablette, TV'),
        ],
      ),
    );
  }
}
