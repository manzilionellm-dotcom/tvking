// =========================================================
//  mac_activation_view.dart — Activation par code MAC
// =========================================================
//  Deux chemins, sans liste « Serveur 1 / Serveur 2 » :
//    • le code MAC, envoyé au revendeur, qui peut encore pousser
//      une source déjà payée (les abonnés déjà configurés ne
//      ressaisissent rien) ;
//    • la personne ajoute ELLE-MÊME sa source : Xtream, lien M3U
//      ou lien lecteur, chez n'importe quel fournisseur.
//
//  Ce widget est réutilisé à deux endroits :
//    1. l'écran d'accueil VIDE (affiché directement, « ouvert ») ;
//    2. la feuille d'activation (source_choice_sheet).
//
//  Contenu : le code MAC (copiable), un bouton « Copier », un bouton
//  « Envoyer » (WhatsApp / support) et « Vérifier mon abonnement » qui
//  resynchronise sans redémarrer l'app. Aucune dépendance au cast.
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
import '../../../playlists/domain/open_source_input.dart';
import '../../../playlists/presentation/m3u_login_sheet.dart';
import '../../../playlists/presentation/xtream_login_sheet.dart';
import '../../../subscription/data/activation_hint.dart';
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

  /// Affiche le titre + l'explication au-dessus du code.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: DeviceIdentity.instance.mac,
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? mac = snap.data;
        final String macDisplay = mac ?? 'MK:??:??:??:??:??';
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
              const SizedBox(height: 16),
            ],
            // Bloc « Nos offres » — prix lisibles dès l'ouverture (à vie /
            // 1 an / essai + promo), pilotés par le panel « Tarifs ».
            const PricingBanner(),
            const SizedBox(height: 18),
            // Le code MAC, bien lisible et copiable.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
                    onPressed: mac == null
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: mac));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                content: Text(
                                  context.l10n.idCopied(mac),
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
                    onPressed: mac == null
                        ? null
                        : () async {
                            // Envoi direct via WhatsApp (MAC pré-remplie) ;
                            // sinon on ouvre le choix de canaux de support.
                            final bool ok = await VipSupport.openWhatsApp(
                              customMessage:
                                  'Bonjour, voici mon identifiant pour '
                                  'activer mes chaînes :\n\n$mac',
                            );
                            if (!context.mounted) return;
                            if (!ok) {
                              showSupportChoiceSheet(
                                context,
                                customMessage:
                                    'Bonjour, voici mon identifiant pour '
                                    'activer mes chaînes :\n\n$mac',
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
            // « Vérifier mon abonnement » : une fois le code activé à
            // distance, ce bouton refait la synchro (statut + source IPTV
            // poussée) SANS redémarrer l'app.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: mac == null ? null : () => _verify(context),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.l10n.activationCheckButton),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.surfaceHigh,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            // Séparateur « ou » entre l'activation à distance (MAC) et la
            // saisie directe d'un code Xtream.
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    context.l10n.orSeparator,
                    style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                ),
                Expanded(child: Divider(color: AppColors.border)),
              ],
            ),
            const SizedBox(height: 18),
            // La personne écrit sa source. Pas de catalogue caché.
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
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => showM3uLoginSheet(context),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(
                    '${context.l10n.playlistTypeM3u} · ${OpenSourceInput.playerLabel}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Resynchronise immédiatement l'état du device avec le backend :
  ///   1. statut d'abonnement (paid / à vie / 1 an / trial),
  ///   2. source IPTV assignée au code par le revendeur.
  /// Puis informe l'utilisateur. Si des chaînes sont chargées et qu'un
  /// `onActivated` est fourni (feuille), on le déclenche pour fermer.
  Future<void> _verify(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String checking = context.l10n.activationChecking;
    final String success = context.l10n.activationSuccess;
    final String noSource = context.l10n.activationNoSourceYet;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 25),
        content: Text(checking),
      ),
    );
    await SubscriptionState.instance.syncWithBackend();
    await RemoteSourceRepository.sync();

    final bool hasChannels =
        PlaylistRepository.instance.currentChannels.isNotEmpty;
    messenger.clearSnackBars();
    if (hasChannels) {
      onActivated?.call();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text(success),
        ),
      );
    } else {
      final String? hint =
          activationHintFr(SubscriptionState.instance.syncHint);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warning,
          content: Text(hint ?? noSource),
        ),
      );
    }
  }
}
