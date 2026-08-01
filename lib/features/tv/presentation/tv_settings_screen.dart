// =========================================================
//  tv_settings_screen.dart — Réglages (MAC à activer + statut)
// =========================================================
//  ESSENTIEL : affiche en GROS la MAC de cette TV (à donner au revendeur
//  pour l'activer) + l'état de l'abonnement (lu sur le MÊME worker que le
//  panel). Un bouton focusable rafraîchit le statut.
// =========================================================
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../../device/data/device_identity.dart';
import '../data/boot_resume.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../../../core/update/update_prompt.dart';
import 'tv_about_screen.dart';
import 'tv_black_box_screen.dart';
import 'tv_city_screen.dart';
import 'tv_diagnostics_screen.dart';
import 'tv_collections_screen.dart';
import 'tv_display_settings_screen.dart';
import 'tv_family_screen.dart';
import 'tv_home_template_screen.dart';
import 'tv_hue_screen.dart';
import 'tv_invite_screen.dart';
import 'tv_legal_screen.dart';
import 'tv_sleep_timer_screen.dart';
import 'tv_parental_screen.dart';
import 'tv_profiles_screen.dart';
import 'tv_shell.dart';
import 'tv_downloads_screen.dart';
import 'tv_sources_screen.dart';
import 'tv_stats_screen.dart';
import 'tv_theme_screen.dart';

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
    // Code NU (sans « MK: ») : évite le doublon quand le revendeur le colle
    // dans un panel qui préfixe déjà « MK ».
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(m));
    });
    // Reprise au démarrage : charge l'état persisté (la ligne se met à
    // jour toute seule via son ListenableBuilder).
    unawaited(BootResume.instance.load());
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await SubscriptionState.instance.syncWithBackend();
    if (mounted) setState(() => _busy = false);
  }

  /// Formate un nombre de jours avec séparateur de milliers (« 36 500 »).
  String _fmtDaysGrouped(int d) {
    final String str = d.toString();
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(' ');
      buf.write(str[i]);
    }
    return buf.toString();
  }

  ({String label, Color color}) _statusOf(BuildContext context) {
    switch (SubscriptionState.instance.status) {
      case SubscriptionStatus.paid:
        // Montre les JOURS restants (à vie → ~100 ans) — concret et rassurant.
        final int? left = SubscriptionState.instance.subscriptionDaysLeft;
        final String paidLabel = left != null
            ? context.l10n.subDaysRemaining(_fmtDaysGrouped(left))
            : context.l10n.tvStatusPaid;
        return (label: paidLabel, color: const Color(0xFF3FBE7C));
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
    // Material (transparent) au SOMMET : ce Réglages est parfois poussé sans
    // ancêtre Material (rail d'icônes des templates Rails / TiviMate) → Flutter
    // dessinait des DOUBLES SOULIGNEMENTS JAUNES sous chaque texte. En
    // s'enveloppant lui-même, l'écran reste NET partout (réglages « haut de
    // gamme », pas de lignes jaunes).
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
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
                    Text(context.l10n.tvSettingsSources,
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
          // ----- Reprise au démarrage (n°2) : rouvrir la dernière chaîne
          //  à l'ouverture de l'app (comportement « vraie TV »). Bascule
          //  simple, DÉSACTIVÉE par défaut — état lisible sur la ligne.
          ListenableBuilder(
            listenable: BootResume.instance,
            builder: (BuildContext context, Widget? _) {
              final bool on = BootResume.instance.enabled;
              return TvFocusBuilder(
                scale: TvFocusScale.large,
                onSelect: () =>
                    unawaited(BootResume.instance.setEnabled(!on)),
                builder: (BuildContext context, bool focused) {
                  final Color bg = focused ? TvTokens.gold : TvTokens.sel;
                  final Color fg = focused
                      ? const Color(0xFF1A1206)
                      : TvTokens.goldBright;
                  return Container(
                    width: 760,
                    decoration: BoxDecoration(
                        color: bg,
                        borderRadius:
                            BorderRadius.circular(TvDimens.cardRadius)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 16),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.play_circle_outline_rounded,
                            color: fg, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(context.l10n.tvBootResume,
                                  style: TextStyle(
                                      fontSize: TvDimens.title,
                                      fontWeight: FontWeight.w700,
                                      color: fg)),
                              const SizedBox(height: 2),
                              Text(context.l10n.tvBootResumeHelp,
                                  style: TextStyle(
                                      fontSize: TvDimens.body,
                                      color: focused
                                          ? fg.withValues(alpha: 0.75)
                                          : TvTokens.muted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          on
                              ? Icons.toggle_on_rounded
                              : Icons.toggle_off_rounded,
                          color: on
                              ? (focused ? fg : TvTokens.goldBright)
                              : (focused ? fg : TvTokens.muted),
                          size: 40,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Changer les templates d'accueil (Classique / IBO / TiviMate)
          //  Point d'entrée UNIVERSEL : depuis le Classique (défaut) on n'a
          //  aucun bouton « templates » sur l'accueil → on le met ici pour que
          //  tout le monde puisse changer de disposition. TvHomeTemplateScreen
          //  s'enveloppe déjà dans TvShell → push direct (sans TvShell).
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvHomeTemplateScreen(),
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
                    Icon(Icons.dashboard_customize_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Changer les templates',
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
          // ----- Mes téléchargements (films hors-ligne) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvDownloadsScreen()),
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
                    Icon(Icons.download_for_offline_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsDownloads,
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
          // ----- Mes statistiques (temps d'écran, top chaînes — local) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvStatsScreen()),
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
                    Icon(Icons.query_stats_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsStats,
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
          // ----- Lumières Philips Hue (mode salle de cinéma) -----
          //  Ambiance rouge braise pilotée par le Cinéma : découverte du
          //  pont, association, activation et test — cf. tv_hue_screen.
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvHueScreen(),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.ember : TvTokens.sel;
              final Color fg =
                  focused ? TvTokens.onEmber : TvTokens.emberBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.lightbulb_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvHueTitle,
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
          // ----- Boîte noire (diagnostic & compte rendu) -----
          //  LE guichet visible du support : pourquoi une chaîne ne s'ouvre
          //  pas (point par point), compte rendu général (versions, santé),
          //  journal de vol. L'accès caché HAUT-HAUT-BAS-BAS reste inchangé.
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvBlackBoxScreen()),
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
                    Icon(Icons.shield_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsBlackBox,
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
                    Text(context.l10n.tvSettingsParental,
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
                    Text(context.l10n.tvSettingsLegal,
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
          // ----- Abonnement Famille (partager avec 4 proches) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvFamilyScreen()),
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
                    Icon(Icons.family_restroom_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsFamily,
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
          // ----- Pass Partage (« regarder ensemble ») : inviter un ami 2 jours
          //  OU activer un code reçu. TvInviteScreen ne s'enveloppe pas → TvShell.
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvInviteScreen()),
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
                    Icon(Icons.card_giftcard_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Pass Partage — inviter un ami',
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
                    Text(context.l10n.tvSettingsProfiles,
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
                    Text(context.l10n.tvSettingsCollections,
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
                    Text(context.l10n.tvSettingsSleep,
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
                    Text(context.l10n.tvSettingsDisplay,
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
          // ----- Thème (119 couleurs premium + mode immersif) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvThemeScreen()),
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
                    Icon(Icons.palette_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text(context.l10n.themeChooseTitle,
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
          // ----- Ma ville (météo exacte, plus jamais la ville voisine) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvCityScreen()),
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
                    Icon(Icons.place_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsWeather,
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
          // ----- Vérifier les mises à jour (manuel) : propose l'install
          //       directe, ou confirme « déjà la dernière version ». -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => checkForUpdatesInteractive(context),
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
                    Icon(Icons.system_update_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text(context.l10n.aboutCheckUpdates,
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
                    Text(context.l10n.tvSettingsAbout,
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
          const SizedBox(height: 12),
          // ----- Boîte noire (diagnostic) : accès DIRECT depuis les
          //       réglages (avant elle était cachée dans À propos → Version).
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvDiagnosticsScreen()),
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
                    Icon(Icons.bug_report_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsDiagnostics,
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
              context.l10n.tvSettingsPlayerDisclaimer,
              style: TextStyle(
                  fontSize: TvDimens.label,
                  height: 1.45,
                  color: TvTokens.mutedDim),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
      ),
    );
  }
}
