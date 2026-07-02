// =========================================================
//  tv_settings_screen.dart — Réglages (MAC à activer + statut)
// =========================================================
//  ESSENTIEL : affiche en GROS la MAC de cette TV (à donner au revendeur
//  pour l'activer) + l'état de l'abonnement (lu sur le MÊME worker que le
//  panel). Un bouton focusable rafraîchit le statut.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_about_screen.dart';
import 'tv_collections_screen.dart';
import 'tv_display_settings_screen.dart';
import 'tv_legal_screen.dart';
import 'tv_sleep_timer_screen.dart';
import 'tv_parental_screen.dart';
import 'tv_profiles_screen.dart';
import 'tv_shell.dart';
import 'tv_sources_screen.dart';

class TvSettingsScreen extends StatefulWidget {
  const TvSettingsScreen({super.key});

  @override
  State<TvSettingsScreen> createState() => _TvSettingsScreenState();
}

class _TvSettingsScreenState extends State<TvSettingsScreen> {
  String _mac = '…';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await SubscriptionState.instance.syncWithBackend();
    if (mounted) setState(() => _busy = false);
  }

  ({String label, Color color}) _statusOf(BuildContext context) {
    switch (SubscriptionState.instance.status) {
      case SubscriptionStatus.paid:
        return (label: context.l10n.tvStatusPaid, color: const Color(0xFF3FBE7C));
      case SubscriptionStatus.trialActive:
        final int d = SubscriptionState.instance.trialDaysRemaining;
        return (label: context.l10n.tvStatusTrial(d), color: const Color(0xFF5AA0E8));
      case SubscriptionStatus.trialExpired:
        return (label: context.l10n.tvStatusTrialExpired, color: const Color(0xFFE8B23A));
      case SubscriptionStatus.frozen:
        return (label: context.l10n.tvStatusFrozen, color: const Color(0xFFE8B23A));
      case SubscriptionStatus.banned:
        return (label: context.l10n.tvStatusBanned, color: const Color(0xFFFF5A4A));
      case SubscriptionStatus.unknown:
        return (label: context.l10n.tvStatusUnknown, color: TvTokens.mutedDim);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({String label, Color color}) st = _statusOf(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.l10n.tvNavSettings,
              style: TextStyle(
                  fontSize: TvDimens.displayM,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.text)),
          const SizedBox(height: 24),

          // ----- Carte MAC -----
          Container(
            width: 760,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: TvTokens.card,
              borderRadius: BorderRadius.circular(TvDimens.panelRadius),
              border: Border.all(color: TvTokens.lineSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(context.l10n.tvDeviceAddress,
                    style: TextStyle(
                        fontSize: TvDimens.label,
                        color: TvTokens.mutedDim)),
                const SizedBox(height: 10),
                SelectableText(
                  _mac,
                  style: TextStyle(
                    fontSize: TvDimens.displayS,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    color: TvTokens.text,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.tvDeviceAddressHelp,
                  style: TextStyle(
                      fontSize: TvDimens.body, color: TvTokens.muted),
                ),
                const SizedBox(height: 22),

                // ----- Statut -----
                Row(
                  children: <Widget>[
                    Text('${context.l10n.tvStatus} : ',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            color: TvTokens.muted)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: st.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(st.label,
                          style: TextStyle(
                              fontSize: TvDimens.titleS,
                              fontWeight: FontWeight.w700,
                              color: st.color)),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // ----- Bouton rafraîchir -----
                TvFocusBuilder(
                  autofocus: true,
                  scale: TvFocusScale.large,
                  onSelect: _busy ? null : _refresh,
                  builder: (BuildContext context, bool focused) {
                    final Color bg = focused ? TvTokens.gold : TvTokens.sel;
                    final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
                    return Container(
                      decoration: BoxDecoration(
                          color: bg,
                          borderRadius:
                              BorderRadius.circular(TvDimens.cardRadius)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.refresh_rounded, color: fg, size: 24),
                          const SizedBox(width: 10),
                          Text(_busy ? context.l10n.tvChecking : context.l10n.tvRefreshStatus,
                              style: TextStyle(
                                  fontSize: TvDimens.title,
                                  fontWeight: FontWeight.w700,
                                  color: fg)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          // ----- Gérer mes sources (M3U / Xtream) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvSourcesScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : TvTokens.sel;
              final Color fg =
                  focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.playlist_play_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Mes sources (ajouter / activer / supprimer)',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 26),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Contrôle parental & Mode Enfants -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvParentalScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : TvTokens.sel;
              final Color fg =
                  focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.child_care_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Contrôle parental (Mode Enfants + code PIN)',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 26),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Mentions légales & Conditions (positionnement « lecteur ») -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvLegalScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : TvTokens.sel;
              final Color fg =
                  focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.gavel_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Mentions légales & Conditions d\'utilisation',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 26),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Profils famille (chacun son univers) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvProfilesScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : TvTokens.sel;
              final Color fg =
                  focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.people_alt_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Profils (chacun son univers)',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 26),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Mes collections (favoris rangés par thème) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvCollectionsScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : TvTokens.sel;
              final Color fg =
                  focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.collections_bookmark_rounded,
                        color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Mes collections (favoris par thème)',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 26),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Minuterie de veille (éteindre après X min) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvSleepTimerScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : TvTokens.sel;
              final Color fg =
                  focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.bedtime_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Minuterie de veille (éteindre après X min)',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 26),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Affichage (overscan + taille du texte) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvDisplaySettingsScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : TvTokens.sel;
              final Color fg =
                  focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.tv_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Affichage (marge écran + taille du texte)',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 26),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- À propos (version, appareil, mémoire, vider le cache) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvAboutScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : TvTokens.sel;
              final Color fg =
                  focused ? const Color(0xFF1A1206) : TvTokens.goldBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('À propos (version, appareil, vider le cache)',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 26),
                  ],
                ),
              );
            },
          ),
          // ----- Avertissement « lecteur » toujours visible (bas de page) -----
          const SizedBox(height: 22),
          Container(
            width: 760,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TvTokens.card,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              border: Border.all(color: TvTokens.lineSoft),
            ),
            child: Text(
              'Cette application est un LECTEUR multimédia. Elle ne vend, ne '
              'fournit et n\'héberge aucune chaîne, aucun flux ni aucun lien '
              'M3U. Le contenu est fourni par l\'utilisateur, seul responsable '
              'de sa licéité.',
              style: TextStyle(
                  fontSize: TvDimens.label,
                  height: 1.45,
                  color: TvTokens.mutedDim),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
