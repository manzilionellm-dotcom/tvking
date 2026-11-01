import 'package:flutter/material.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'tv_localized_format.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../subscription/data/gold_trial_backend.dart';
import '../../subscription/data/gold_trial_controller.dart';
import '../../subscription/presentation/gold_trial_card.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

/// Offre lisible à distance, pilotée par le même contrôleur que le téléphone.
/// Pas d'animation permanente au repos : seuls le focus et l'attente bougent.
/// Le QR WhatsApp fonctionne aussi sur une box sans navigateur ni application.
class TvGoldTrialCard extends StatelessWidget {
  const TvGoldTrialCard({
    super.key,
    required this.controller,
    this.autofocus = false,
  });

  final GoldTrialController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.visible && !controller.showConfirmation) {
            return const SizedBox.shrink();
          }
          final GoldTrialOutcome outcome = controller.result.outcome;
          final bool activated = outcome == GoldTrialOutcome.activated;
          final bool used = outcome == GoldTrialOutcome.alreadyUsed;
          final bool contact = used ||
              outcome == GoldTrialOutcome.disabled ||
              outcome == GoldTrialOutcome.dailyCap;
          final l10n = context.l10n;
          final String? message = controller.comingSoon
              ? l10n.trialComingSoon
              : localizedTrialMessage(l10n, outcome);
          final DateTime? expire = controller.result.expire;
          final bool busy = controller.busy;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: TvTokens.card,
                borderRadius: BorderRadius.circular(TvTokens.rCard),
                border:
                    Border.all(color: TvTokens.accent.withValues(alpha: 0.55)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                            activated
                                ? Icons.check_circle_outline_rounded
                                : Icons.auto_awesome_rounded,
                            size: TvDimens.icon,
                            color: activated
                                ? TvTokens.success
                                : TvTokens.accentBright),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(l10n.trialTitle,
                                style: TvTokens.ui(TvDimens.body,
                                    weight: FontWeight.w600))),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: TvTokens.badgeBg,
                              borderRadius:
                                  BorderRadius.circular(TvTokens.rSmall)),
                          child: Text(l10n.trialDurationBadge,
                              style: TvTokens.ui(TvDimens.label,
                                  weight: FontWeight.w700,
                                  color: TvTokens.accentBright)),
                        ),
                      ],
                    ),
                    if (message != null || busy) ...<Widget>[
                      const SizedBox(height: 12),
                      // Le loader annonce l'attente ; le message serveur attend
                      // l'issue du chargement pour éviter deux annonces simultanées.
                      Semantics(
                        liveRegion: true,
                        child: Text(busy ? l10n.trialActivating : message!,
                            style: TvTokens.ui(TvDimens.label,
                                color: TvTokens.text)),
                      ),
                    ] else ...<Widget>[
                      const SizedBox(height: 8),
                      Text(l10n.trialDiscover,
                          style: TvTokens.ui(TvDimens.label,
                              color: TvTokens.muted)),
                    ],
                    if (expire != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                          l10n.trialExpires(
                              tvDateTime(context, expire.toLocal())),
                          style: TvTokens.ui(TvDimens.label,
                              color: TvTokens.accentBright)),
                    ],
                    if (!activated && !used) ...<Widget>[
                      const SizedBox(height: 16),
                      _TrialAction(
                        key: const ValueKey<String>('tv-gold-trial-button'),
                        label: busy ? l10n.subLoading : l10n.trialStart,
                        icon: Icons.play_arrow_rounded,
                        busy: busy,
                        autofocus: autofocus,
                        primary: true,
                        onSelect:
                            controller.canRequest ? controller.request : null,
                      ),
                    ],
                    if (busy) ...<Widget>[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(
                          color: TvTokens.accentBright,
                          backgroundColor: TvTokens.line),
                    ],
                    if (controller.sourceFailed) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(l10n.trialInterrupted,
                          style: TvTokens.ui(TvDimens.label,
                              color: TvTokens.muted)),
                      const SizedBox(height: 10),
                      _TrialAction(
                        label: l10n.trialRetryLoading,
                        icon: Icons.refresh_rounded,
                        onSelect: busy ? null : controller.retrySource,
                      ),
                    ],
                    if (contact) ...<Widget>[
                      const SizedBox(height: 14),
                      _TrialAction(
                        label: context.l10n.trialSubscribe,
                        icon: Icons.qr_code_rounded,
                        autofocus: autofocus,
                        onSelect: () => _showWhatsApp(context),
                      ),
                    ],
                    if (!busy && !activated && !used && !contact) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(l10n.trialAutomatic,
                          textAlign: TextAlign.center,
                          style: TvTokens.ui(TvDimens.caption,
                              color: TvTokens.muted)),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );

  void _showWhatsApp(BuildContext context) {
    showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              backgroundColor: TvTokens.card,
              title: Text(context.l10n.trialSubscribe,
                  style: TvTokens.ui(TvDimens.body, weight: FontWeight.w600)),
              content: SizedBox(
                width: 340,
                child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(context.l10n.trialScanHelp,
                        textAlign: TextAlign.center,
                        style:
                            TvTokens.ui(TvDimens.label, color: TvTokens.muted)),
                    const SizedBox(height: 16),
                    ColoredBox(
                      color: TvTokens.text,
                      child: QrImageView(
                        key: const ValueKey<String>('tv-trial-whatsapp-qr'),
                        data: GoldTrialCard.whatsapp.toString(),
                        size: 240,
                        padding: const EdgeInsets.all(16),
                        eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: TvTokens.onAccent),
                        dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: TvTokens.onAccent),
                      ),
                    ),
                  ],
                )),
              ),
              actions: <Widget>[
                _TrialAction(
                    label: context.l10n.tvClose,
                    icon: Icons.close_rounded,
                    autofocus: true,
                    onSelect: () => Navigator.of(dialogContext).pop()),
              ],
            ));
  }
}

class _TrialAction extends StatelessWidget {
  const _TrialAction(
      {super.key,
      required this.label,
      required this.icon,
      required this.onSelect,
      this.autofocus = false,
      this.primary = false,
      this.busy = false});

  final String label;
  final IconData icon;
  final VoidCallback? onSelect;
  final bool autofocus;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onSelect != null,
        onTap: onSelect,
        child: TvFocusBuilder(
          autofocus: autofocus,
          // Le focus reste stable pendant le POST, sans autoriser un second appel.
          scale: TvFocusScale.small,
          onSelect: onSelect,
          builder: (context, focused) => AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : TvDimens.focusAnim,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: primary ? TvTokens.ctaGradient : null,
              color: primary ? null : TvTokens.sel,
              borderRadius: BorderRadius.circular(TvTokens.rButton),
              // Largeur constante : se déplacer au D-pad ne décale pas le texte.
              border: Border.all(
                  width: 2,
                  color: focused
                      ? TvTokens.text
                      : (primary ? TvTokens.accent : TvTokens.line)),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (busy)
                    SizedBox.square(
                        dimension: TvDimens.icon,
                        child: const CircularProgressIndicator(
                            strokeWidth: 2, color: TvTokens.onAccent))
                  else
                    Icon(icon,
                        size: TvDimens.icon,
                        color: primary
                            ? TvTokens.onAccent
                            : TvTokens.accentBright),
                  const SizedBox(width: 12),
                  Flexible(
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: TvTokens.ui(TvDimens.body,
                              weight: FontWeight.w700,
                              color: primary
                                  ? TvTokens.onAccent
                                  : TvTokens.text))),
                ]),
          ),
        ),
      );
}

/// Le statut serveur est stable ; son ancien message français n'impose pas
/// sa langue à la personne. Aucune erreur brute fournisseur n'est affichée.
String? localizedTrialMessage(
        AppLocalizations l10n, GoldTrialOutcome outcome) =>
    switch (outcome) {
      GoldTrialOutcome.activated => l10n.trialActivated,
      GoldTrialOutcome.alreadyUsed => l10n.trialAlreadyUsed,
      GoldTrialOutcome.inProgress => l10n.trialInProgress,
      GoldTrialOutcome.disabled => l10n.trialComingSoon,
      GoldTrialOutcome.dailyCap => l10n.trialDailyCap,
      GoldTrialOutcome.rateLimited => l10n.trialRateLimited,
      GoldTrialOutcome.error => l10n.trialError,
      _ => null,
    };
