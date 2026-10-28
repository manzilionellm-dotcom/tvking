import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/gold_trial_backend.dart';
import '../data/gold_trial_controller.dart';

/// Même texte public sur téléphone et box ; jamais une exception fournisseur.
String? goldTrialPublicMessage(GoldTrialResult result) => result.message ?? switch (result.outcome) {
            GoldTrialOutcome.activated => 'Essai activé ✔',
            GoldTrialOutcome.alreadyUsed =>
              'Vous avez déjà utilisé votre essai gratuit',
            GoldTrialOutcome.inProgress =>
              'Activation en cours, patiente quelques secondes.',
            GoldTrialOutcome.disabled => 'Les essais sont fermés pour le moment.',
            GoldTrialOutcome.dailyCap =>
              "Plus d'essais disponibles aujourd'hui, reviens demain.",
            GoldTrialOutcome.rateLimited =>
              'Trop de demandes. Patientez une minute avant de réessayer.',
            GoldTrialOutcome.error => 'Erreur, réessaie.',
            _ => null,
          };

/// Affiche le message public du Worker ; les détails techniques restent
/// dans le serveur. Les textes locaux couvrent les pannes et anciens serveurs.
class GoldTrialCard extends StatelessWidget {
  const GoldTrialCard({super.key, required this.controller});
  final GoldTrialController controller;

  static final Uri whatsapp = Uri.parse('https://wa.me/447307410512');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, _) {
          if (!controller.visible && !controller.showConfirmation) {
            return const SizedBox.shrink();
          }
          final colors = AppColors.lumiere(context);
          final GoldTrialOutcome outcome = controller.result.outcome;
          final String? message = goldTrialPublicMessage(controller.result);
          final bool showWhatsApp = outcome == GoldTrialOutcome.alreadyUsed ||
              outcome == GoldTrialOutcome.disabled || outcome == GoldTrialOutcome.dailyCap;
          final DateTime? expire = controller.result.expire;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (outcome != GoldTrialOutcome.activated &&
                    outcome != GoldTrialOutcome.alreadyUsed)
                  FilledButton.icon(
                    key: const ValueKey<String>('gold-trial-button'),
                    onPressed: controller.canRequest ? controller.request : null,
                    icon: controller.busy
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: colors.textPrimary),
                          )
                        : const Icon(Icons.play_circle_outline),
                    label: Text(controller.busy
                        ? 'Activation de votre essai…' : 'Je teste'),
                  ),
                if (message != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(message, textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium.copyWith(color: colors.textPrimary)),
                  ),
                ],
                if (expire != null) Text(
                  'Expiration : ${DateFormat('dd/MM/yyyy à HH:mm').format(expire.toLocal())}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(color: colors.textSecondary),
                ),
                if (controller.waitingForSource || controller.importing) ...<Widget>[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
                if (controller.sourceFailed) ...<Widget>[
                  Text('Erreur, réessaie.', textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(color: colors.textPrimary)),
                  OutlinedButton(
                    onPressed: controller.busy ? null : controller.retrySource,
                    child: const Text('Réessayer le chargement'),
                  ),
                ],
                if (showWhatsApp) OutlinedButton.icon(
                  onPressed: () => _openWhatsApp(context),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('S’abonner sur WhatsApp'),
                ),
              ],
            ),
          );
        },
      );

  Future<void> _openWhatsApp(BuildContext context) async {
    try {
      if (await launchUrl(whatsapp, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Même message fermé si WhatsApp/le navigateur n'est pas disponible.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Erreur, réessaie.')),
    );
  }
}
