// =========================================================
//  tv_settings_screen.dart — Réglages (MAC à activer + statut)
// =========================================================
//  ESSENTIEL : affiche en GROS la MAC de cette TV (à donner au revendeur
//  pour l'activer) + l'état de l'abonnement (lu sur le MÊME worker que le
//  panel). Un bouton focusable rafraîchit le statut.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_ambience.dart';
import '../core/tv_tokens.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_developer_mode.dart';
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
import 'tv_language_screen.dart';
import 'tv_legal_screen.dart';
import 'tv_sleep_timer_screen.dart';
import 'tv_parental_screen.dart';
import 'tv_profiles_screen.dart';
import 'tv_shell.dart';
import 'tv_downloads_screen.dart';
import 'tv_help_screen.dart';
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

  /// Univers d'ambiance à restaurer en sortant (Caméléon adaptatif : entrer
  /// dans les Réglages teinte l'atmosphère en améthyste discrète, en
  /// ressortir la rend TENDREMENT à l'univers quitté — le fondu 1,6 s de
  /// TvShell fait la transition).
  TvAmbienceKind _prevAmbience = TvAmbienceKind.maison;

  @override
  void initState() {
    super.initState();
    _prevAmbience = TvAmbience.instance.kind;
    TvAmbience.instance.set(TvAmbienceKind.reglage);
    // Code NU (sans « MK: ») : évite le doublon quand le revendeur le colle
    // dans un panel qui préfixe déjà « MK ».
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = DeviceIdentity.stripPrefix(m));
    });
  }

  @override
  void dispose() {
    TvAmbience.instance.set(_prevAmbience);
    super.dispose();
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
        // Durée HUMAINE (retour client : « 36 500 jours, c'est pas sexy ») :
        // au-delà de 2 ans on parle en ANNÉES (« ≈ 100 ans restants » pour
        // un à-vie) ; en dessous, les jours restent le repère concret.
        final int? left = SubscriptionState.instance.subscriptionDaysLeft;
        final String paidLabel = left == null
            ? context.l10n.tvStatusPaid
            : left >= 730
                ? context.l10n.tvYearsRemaining((left / 365).round())
                : context.l10n.subDaysRemaining(_fmtDaysGrouped(left));
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
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: TvTokens.text)),
          const SizedBox(height: 24),

          // ----- Carte MAC -----
          Container(
            width: 640,
            padding: const EdgeInsets.all(18),
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
                        fontSize: 12,
                        color: TvTokens.mutedDim)),
                const SizedBox(height: 10),
                SelectableText(
                  _mac,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: TvTokens.text,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.tvDeviceAddressHelp,
                  style: TextStyle(
                      fontSize: 14, color: TvTokens.muted),
                ),
                const SizedBox(height: 22),

                // ----- Statut -----
                Row(
                  children: <Widget>[
                    Text('${context.l10n.tvStatus} : ',
                        style: TextStyle(
                            fontSize: 16,
                            color: TvTokens.muted)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: st.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(st.label,
                          style: TextStyle(
                              fontSize: 14,
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
                    final Color bg = focused ? TvTokens.gold : Colors.transparent;
                    final Color fg = focused ? TvTokens.onGold : TvTokens.goldBright;
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
                          Icon(Icons.refresh_rounded, color: fg, size: 18),
                          const SizedBox(width: 10),
                          Text(_busy ? context.l10n.tvChecking : context.l10n.tvRefreshStatus,
                              style: TextStyle(
                                  fontSize: 16,
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.playlist_play_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsSources,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Langue de l'application (demande exploitant 19/08) -----
          //  La TV n'avait AUCUN sélecteur : elle suivait la langue système
          //  de la box. Toutes les langues embarquées + « Système »,
          //  application instantanée (TvApp écoute LocaleRepository).
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvLanguageScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.language_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsLanguage,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- « Développeur » (CACHÉ) : le choix des modèles d'accueil
          //  A/B/C/D. Décision propriétaire du 21/08 : l'app ne présente
          //  qu'UN modèle (D, panneau façon TiviMate) — cette entrée
          //  n'apparaît qu'en mode Développeur (appui LONG sur « À propos »
          //  pour basculer), pour les gens qui exigent tout.
          if (TvDeveloperMode.instance.enabled) ...<Widget>[
            TvFocusBuilder(
              scale: TvFocusScale.large,
              onSelect: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TvHomeTemplateScreen(),
                ),
              ),
              builder: (BuildContext context, bool focused) {
                final Color bg = focused ? TvTokens.gold : Colors.transparent;
                final Color fg =
                    focused ? TvTokens.onGold : TvTokens.goldBright;
                return Container(
                  width: 640,
                  decoration: BoxDecoration(
                      color: bg,
                      borderRadius:
                          BorderRadius.circular(TvDimens.cardRadius)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.code_rounded, color: fg, size: 20),
                      const SizedBox(width: 12),
                      Text(context.l10n.tvSettingsDeveloper,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: fg)),
                      const SizedBox(width: 12),
                      // Le sous-texte réutilise la clé existante du sélecteur :
                      // il dit exactement ce qu'on trouve derrière.
                      Expanded(
                        child: Text(context.l10n.tvTemplateChange,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                color: fg.withValues(alpha: 0.7))),
                      ),
                      Icon(Icons.chevron_right_rounded, color: fg, size: 20),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
          ],
          // ----- Mes téléchargements (films hors-ligne) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvDownloadsScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.download_for_offline_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsDownloads,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.query_stats_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsStats,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.lightbulb_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvHueTitle,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.shield_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsBlackBox,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.child_care_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsParental,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.gavel_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsLegal,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.family_restroom_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsFamily,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.card_giftcard_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsInvite,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.people_alt_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsProfiles,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.collections_bookmark_rounded,
                        color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsCollections,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.bedtime_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsSleep,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.tv_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsDisplay,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.palette_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.themeChooseTitle,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.place_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsWeather,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.system_update_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.aboutCheckUpdates,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Aide & contact (21/08) : l'aide pointe sur la MESSAGERIE
          //  du support et sur le site web (QR à scanner au téléphone —
          //  le site, lui, pointe déjà sur la messagerie).
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvHelpScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.support_agent_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsHelp,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // ----- À propos (version, appareil, mémoire, vider le cache) -----
          //  APPUI LONG (geste volontairement caché, décision du 21/08) :
          //  bascule le mode Développeur — fait apparaître/disparaître
          //  l'entrée « Développeur » (choix des modèles d'accueil A/B/C/D)
          //  et, hors de ce mode, l'app force le Modèle D.
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvAboutScreen()),
              ),
            ),
            onLongPress: () async {
              final bool next = !TvDeveloperMode.instance.enabled;
              await TvDeveloperMode.instance.setEnabled(next);
              if (mounted) setState(() {});
            },
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.info_outline_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsAbout,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
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
              final Color bg = focused ? TvTokens.gold : Colors.transparent;
              final Color fg =
                  focused ? TvTokens.onGold : TvTokens.goldBright;
              return Container(
                width: 640,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(
                        color: focused ? TvTokens.gold : TvTokens.lineSoft)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.bug_report_rounded, color: fg, size: 20),
                    const SizedBox(width: 12),
                    Text(context.l10n.tvSettingsDiagnostics,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 20),
                  ],
                ),
              );
            },
          ),
          // ----- Avertissement « lecteur » toujours visible (bas de page) -----
          const SizedBox(height: 22),
          Container(
            width: 640,
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
