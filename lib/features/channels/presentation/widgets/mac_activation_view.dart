// =========================================================
//  mac_activation_view.dart — Activation (2 blocs distincts)
// =========================================================
//  Écran d'activation client, volontairement séparé en DEUX blocs très
//  distincts (demande explicite : « un en haut, un autre en bas ») :
//
//    ┌───────────────────────────────────────────┐
//    │  ① ACTIVER L'APPLICATION  (bloc du haut)    │
//    │     • 2 offres seulement : À vie / 1 an      │
//    │     • le NUMÉRO de référence (copiable)       │
//    │     • Copier / Envoyer au revendeur           │
//    │     • Vérifier mon abonnement                 │
//    └───────────────────────────────────────────┘
//    ┌───────────────────────────────────────────┐
//    │  ② ACTIVER LES CHAÎNES  (bloc du bas)        │
//    │     • « J'ai un code » → saisie Xtream        │
//    └───────────────────────────────────────────┘
//
//  Le client NE saisit RIEN pour l'app : il voit son NUMÉRO, l'envoie au
//  revendeur, et le revendeur lie ce code à un abonnement côté serveur.
//  L'app récupère ensuite la source automatiquement (activation express +
//  RealtimeSyncService → en quelques secondes). Le bloc « chaînes » reste
//  disponible pour ceux qui possèdent déjà un code d'accès.
//
//  Ce widget est réutilisé à deux endroits :
//    1. l'écran d'accueil VIDE (affiché directement, « ouvert ») ;
//    2. la feuille d'activation (source_choice_sheet).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/support/support_choice_sheet.dart';
import '../../../../core/support/vip_support.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../device/data/device_identity.dart';
import '../../../pricing/presentation/pricing_banner.dart';
import '../../../playlists/data/playlist_repository.dart';
import '../../../playlists/data/remote_source_repository.dart';
import '../../../playlists/presentation/import_progress_screen.dart';
import '../../../playlists/presentation/xtream_login_sheet.dart';
import '../../../subscription/data/subscription_state.dart';

class MacActivationView extends StatelessWidget {
  const MacActivationView({
    super.key,
    this.onActivated,
    this.showHeader = true,
  });

  /// Appelé quand l'activation a RÉUSSI et que des chaînes sont arrivées
  /// (la feuille s'en sert pour se fermer ; l'accueil le laisse `null`
  /// car il se reconstruit tout seul dès que le flux émet la playlist).
  final VoidCallback? onActivated;

  /// Affiche le titre + l'explication au-dessus des blocs.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: DeviceIdentity.instance.mac,
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? mac = snap.data;
        // Code NU (sans « MK: ») : le revendeur le colle dans un panel qui
        // rajoute déjà « MK » → « MK:… » collé le doublerait (« MKMK:… »).
        final String? macNu =
            mac == null ? null : DeviceIdentity.stripPrefix(mac);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (showHeader) ...<Widget>[
              Text(
                context.l10n.activateAtHomeTitle,
                style: AppTextStyles.headlineMedium.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.activateAtHomeDesc,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ============================================================
            //  ① BLOC DU HAUT — ACTIVER L'APPLICATION
            // ============================================================
            _SectionCard(
              step: '1',
              icon: Icons.workspace_premium_rounded,
              title: context.l10n.activateAppSectionTitle,
              subtitle: context.l10n.activateAppSectionDesc,
              children: <Widget>[
                // Les DEUX offres (à vie / 1 an) — pilotées par le panel.
                const PricingBanner(),
                const SizedBox(height: 16),
                _referenceBlock(context, macNu),
              ],
            ),

            const SizedBox(height: 18),

            // ============================================================
            //  ② BLOC DU BAS — ACTIVER LES CHAÎNES
            // ============================================================
            _SectionCard(
              step: '2',
              icon: Icons.playlist_add_check_rounded,
              title: context.l10n.activateChannelsSectionTitle,
              subtitle: context.l10n.activateChannelsSectionDesc,
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => showXtreamLoginSheet(context),
                    icon: const Icon(Icons.vpn_key_rounded, size: 18),
                    label: Text(context.l10n.xtreamHaveCode),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: BorderSide(
                          color: AppColors.accent.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Le NUMÉRO de référence (copiable) + Copier / Envoyer + Vérifier.
  /// Vit dans le bloc « Activer l'application » : c'est ce numéro que le
  /// revendeur lie à l'abonnement app.
  Widget _referenceBlock(BuildContext context, String? macNu) {
    final String macDisplay = macNu ?? '??:??:??:??:??';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Le numéro, bien lisible et copiable.
        Text(
          context.l10n.gateReferenceLabel,
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall.copyWith(
            fontSize: 10.5,
            letterSpacing: 1.4,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: SelectableText(
            macDisplay,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: macNu == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: macNu));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              context.l10n.idCopied(macNu),
                              style: AppTextStyles.bodyMedium,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(context.l10n.buttonCopy),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: macNu == null
                    ? null
                    : () async {
                        // Envoi direct via WhatsApp (code pré-rempli) ;
                        // sinon on ouvre le choix de canaux de support. Le
                        // message pré-rempli est localisé et porte le code
                        // NU (sans « MK: »).
                        final String msg =
                            context.l10n.activationPrefillMessage(macNu);
                        final bool ok = await VipSupport.openWhatsApp(
                          customMessage: msg,
                        );
                        if (!context.mounted) return;
                        if (!ok) {
                          showSupportChoiceSheet(
                            context,
                            customMessage: msg,
                          );
                        }
                      },
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text(context.l10n.buttonSend),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.voidSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // « Vérifier mon abonnement » : une fois le code activé à distance,
        // ce bouton refait la synchro (statut + source poussée) SANS
        // redémarrer l'app.
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: macNu == null ? null : () => _verify(context),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(context.l10n.activationCheckButton),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceHigh,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  /// Resynchronise immédiatement l'état du device avec le backend :
  ///   1. statut d'abonnement (paid / à vie / 1 an / trial),
  ///   2. source IPTV assignée au code par le revendeur.
  /// Puis informe l'utilisateur. Si des chaînes sont chargées et qu'un
  /// `onActivated` est fourni (feuille), on le déclenche pour fermer.
  Future<void> _verify(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // Libellés capturés AVANT les awaits (pas de BuildContext après un
    // trou asynchrone).
    final String checking = context.l10n.activationChecking;
    final String success = context.l10n.activationSuccess;
    final String noSource = context.l10n.activationNoSourceYet;
    final String loadingTitle = context.l10n.activationLoadingTitle;

    // 1) Statut serveur (à vie / payé / essai).
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 20),
        content: Text(checking),
      ),
    );
    await SubscriptionState.instance.syncWithBackend();

    // Déjà des chaînes chargées → activé, rien à réimporter.
    if (PlaylistRepository.instance.currentChannels.isNotEmpty) {
      messenger.clearSnackBars();
      onActivated?.call();
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.success, content: Text(success)),
      );
      return;
    }

    // 2) Le revendeur a-t-il poussé une source ? (sans la charger encore)
    final List<Map<String, dynamic>> sources =
        await RemoteSourceRepository.fetchAssignedSources();
    messenger.clearSnackBars();
    if (!context.mounted) return;

    // Rien d'assigné → le message « patiente un instant » (revendeur pas
    // encore passé).
    if (sources.isEmpty) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.warning, content: Text(noSource)),
      );
      return;
    }

    // 3) IMPORT VIVANT : plein écran qui montre la procédure, les catégories
    //    et les chaînes qui s'ajoutent EN DIRECT + « patiente ». Beaucoup
    //    plus rassurant qu'un petit message en bas.
    await runImportWithProgress<RemoteSyncResult>(
      context,
      title: loadingTitle,
      task: (onProgress) =>
          RemoteSourceRepository.applySources(sources, onProgress: onProgress),
    );
    if (!context.mounted) return;

    final bool hasChannels =
        PlaylistRepository.instance.currentChannels.isNotEmpty;
    if (hasChannels) {
      onActivated?.call();
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.success, content: Text(success)),
      );
    } else {
      // Source reçue mais 0 chaîne / provider KO → message d'attente.
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warning,
          content: Text(noSource),
        ),
      );
    }
  }
}

/// Carte de section — un bloc VISUELLEMENT DISTINCT (numéro d'étape,
/// icône, titre, sous-titre) qui enveloppe son contenu. Sert à séparer
/// nettement « Activer l'application » et « Activer les chaînes ».
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String step;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Pastille d'étape (1 / 2) — repère visuel fort.
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentSurface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.55),
                  ),
                ),
                child: Text(
                  step,
                  style: AppTextStyles.headlineMedium.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(icon, size: 18, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: AppTextStyles.headlineMedium.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
