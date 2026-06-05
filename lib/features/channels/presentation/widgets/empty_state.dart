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

import 'dart:async';

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
    // Écran ADAPTATIF : on écoute le statut d'abonnement pour afficher la
    // bonne chose selon la situation (pro), au lieu de toujours montrer
    // « Active ton abonnement / essai » même quand le client est déjà
    // premium.
    return ListenableBuilder(
      listenable: SubscriptionState.instance,
      builder: (BuildContext context, _) {
        final SubscriptionState sub = SubscriptionState.instance;
        final bool active = sub.status == SubscriptionStatus.paid;

        // Libellé du plan pour la pastille premium : à vie, ou « expire
        // le JJ/MM/AAAA » (1 an / durée), ou « abonnement actif » à défaut.
        final String planLabel;
        if (sub.isLifetime) {
          planLabel = context.l10n.subActiveLifetime;
        } else if (sub.paidUntil != null) {
          final DateTime d = sub.paidUntil!;
          planLabel =
              context.l10n.subActiveUntil('${d.day}/${d.month}/${d.year}');
        } else {
          planLabel = context.l10n.subActiveTitle;
        }

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
                      active
                          ? context.l10n.emptyPremiumTitle
                          : context.l10n.activateSubTitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headlineLarge.copyWith(fontSize: 23),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      active
                          ? context.l10n.emptyPremiumWaiting
                          : context.l10n.activateSubDesc,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Pastille : plan premium (à vie / expire le …) si actif,
                    // sinon la mention d'essai (7 j · 13 €/an).
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.accentSurface
                            : AppColors.editorialCreamSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? AppColors.accent.withValues(alpha: 0.5)
                              : AppColors.editorialCream.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            active
                                ? Icons.workspace_premium_rounded
                                : Icons.auto_awesome_rounded,
                            size: 16,
                            color: active
                                ? AppColors.accent
                                : AppColors.editorialCream,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              active ? planLabel : context.l10n.freeTrialBadge,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // « Activer mon abonnement » seulement si PAS encore
                    // actif (sinon incohérent).
                    if (!active) ...<Widget>[
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: onAddPlaylist,
                          icon: const Icon(
                            Icons.support_agent_rounded,
                            size: 22,
                          ),
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
                    ],

                    // « Vérifier mon abonnement » + sondage auto (toujours).
                    const _SyncNowButton(),
                    const SizedBox(height: 14),

                    // Actif → bouton discret pour revoir son identifiant.
                    // Inactif → mention « activation à distance ».
                    if (active)
                      TextButton.icon(
                        onPressed: onAddPlaylist,
                        icon: const Icon(Icons.badge_outlined, size: 16),
                        label: Text(context.l10n.simpleMyAccount),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textTertiary,
                        ),
                      )
                    else
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
      },
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
  // Sondage automatique : tant que cet écran (aucune chaîne) est affiché,
  // on interroge le serveur toutes les 6 s. Dès que le revendeur active +
  // pousse une source, les chaînes se chargent TOUTES SEULES (le
  // StreamBuilder de l'accueil remplace alors cet écran et dispose ce
  // widget → le timer s'arrête). Rend l'activation « instantanée » sans
  // que le client ait à toucher au bouton.
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    // 1er sondage rapide (2 s après l'affichage), puis toutes les 6 s.
    Future<void>.delayed(const Duration(seconds: 2), _autoSync);
    _autoTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _autoSync(),
    );
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  /// Sondage SILENCIEUX (sans snackbar ni spinner) lancé par le timer.
  /// Si une source apparaît, l'accueil se remplit automatiquement.
  Future<void> _autoSync() async {
    if (_busy || !mounted) return;
    try {
      await SubscriptionState.instance.syncWithBackend();
      await RemoteSourceRepository.sync();
    } catch (_) {
      // Réseau capricieux → on réessaiera au prochain tick.
    }
  }

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
    RemoteSyncResult srcResult = RemoteSyncResult.noSource;
    try {
      // 1) Statut d'abonnement (paid / à vie / 1 an / trial).
      await SubscriptionState.instance.syncWithBackend();
      // 2) Source IPTV (codes/playlist) poussée par le revendeur.
      srcResult = await RemoteSourceRepository.sync();
    } catch (_) {
      // Réseau capricieux : on retombe sur le message « pas encore ».
    }
    final bool hasChannels =
        PlaylistRepository.instance.currentChannels.isNotEmpty;
    if (!mounted) return;
    messenger.clearSnackBars();
    // Message PRÉCIS selon ce que le serveur sait de cette MAC, pour que
    // le revendeur sache exactement quoi corriger :
    //   - chaînes chargées            → succès
    //   - source reçue mais 0 chaîne  → URL/identifiants provider à vérifier
    //   - abonnement payé mais 0 src  → il manque la Source à l'activation
    //   - appareil connu (essai)      → pas encore activé
    //   - appareil inconnu            → souci de connexion / mauvaise MAC
    final r = SubscriptionState.instance.remote;
    final String msg;
    final Color bg;
    if (hasChannels) {
      msg = context.l10n.activationSuccess;
      bg = AppColors.success;
    } else if (srcResult == RemoteSyncResult.sourceFailed) {
      msg = context.l10n.activationSourceFailed;
      bg = AppColors.live;
    } else if (r.paid) {
      msg = context.l10n.activationActiveNoSource;
      bg = AppColors.warning;
    } else if (r.exists) {
      msg = context.l10n.activationDeviceKnownNoSub;
      bg = AppColors.warning;
    } else {
      msg = context.l10n.activationDeviceUnknown;
      bg = AppColors.live;
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: bg,
        content: Text(msg),
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
