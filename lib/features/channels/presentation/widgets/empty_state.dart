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
import '../../../playlists/data/playlist_repository.dart';
import '../../../playlists/data/remote_source_repository.dart';
import '../../../subscription/data/subscription_state.dart';

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
                const SizedBox(height: 12),
                // ----- « C'est bon, mets à jour » -----
                // Quand le revendeur a dit « c'est activé », le client tape
                // ce bouton : l'app interroge le serveur et récupère TOUT
                // (statut d'abonnement + source IPTV / codes assignés à la
                // MAC), puis charge les chaînes — sans redémarrer l'app.
                // Dès que les chaînes arrivent, l'accueil se remplit seul
                // (le StreamBuilder parent remplace cet écran).
                const _SyncNowButton(),
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

/// Bouton « Vérifier mon abonnement » : re-synchronise avec le serveur
/// (statut d'abonnement + source IPTV assignée à la MAC) et charge les
/// chaînes. Stateful pour afficher un spinner pendant l'appel réseau.
class _SyncNowButton extends StatefulWidget {
  const _SyncNowButton();

  @override
  State<_SyncNowButton> createState() => _SyncNowButtonState();
}

class _SyncNowButtonState extends State<_SyncNowButton> {
  bool _busy = false;

  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 25),
        content: Text(context.l10n.activationChecking),
      ),
    );
    try {
      // 1) Statut d'abonnement (paid / à vie / 1 an / trial).
      await SubscriptionState.instance.syncWithBackend();
      // 2) Source IPTV (codes/playlist) poussée par le revendeur.
      await RemoteSourceRepository.sync();
    } catch (_) {
      // Réseau capricieux : on retombe sur le message « pas encore ».
    }
    final bool hasChannels =
        PlaylistRepository.instance.currentChannels.isNotEmpty;
    if (!mounted) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: hasChannels ? AppColors.success : AppColors.warning,
        content: Text(
          hasChannels
              ? context.l10n.activationSuccess
              : context.l10n.activationNoSourceYet,
        ),
      ),
    );
    setState(() => _busy = false);
    // Si des chaînes sont arrivées, le StreamBuilder de l'accueil
    // remplace automatiquement cet écran — rien d'autre à faire.
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _sync,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 20),
        label: Text(
          _busy ? context.l10n.activationChecking : context.l10n.activationCheckButton,
          style: AppTextStyles.button.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
