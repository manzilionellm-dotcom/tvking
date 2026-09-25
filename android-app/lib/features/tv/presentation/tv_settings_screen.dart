// =========================================================
//  tv_settings_screen.dart — Réglages (MAC à activer + statut)
// =========================================================
//  ESSENTIEL : affiche en GROS la MAC de cette TV (à donner au revendeur
//  pour l'activer) + l'état de l'abonnement (lu sur le MÊME worker que le
//  panel). Un bouton focusable rafraîchit le statut.
// =========================================================
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/update/update_service.dart';
import '../core/tv_tokens.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_black_box_screen.dart';
import 'tv_legal_screen.dart';
import 'tv_parental_screen.dart';
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

  // ----- Mise à jour in-app (bouton « qui fonctionne réellement ») -----
  // Cycle : à l'ouverture des Réglages on VÉRIFIE (silencieux) ; la ligne
  // affiche « À jour (build N) » ou « Nouvelle version N disponible — OK pour
  // installer » ; OK → téléchargement avec pourcentage → installateur
  // Android (mise à jour par-dessus, même signature). Tout est journalisé.
  _UpdState _upd = _UpdState.checking;
  UpdateInfo? _updInfo;
  int _updPct = 0;
  String _current = '';

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String m) {
      if (mounted) setState(() => _mac = m);
    });
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    setState(() => _upd = _UpdState.checking);
    try {
      final PackageInfo p = await PackageInfo.fromPlatform();
      _current = p.buildNumber;
    } catch (_) {}
    final UpdateInfo? u = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() {
      _updInfo = u;
      _upd = u == null ? _UpdState.upToDate : _UpdState.available;
    });
  }

  Future<void> _onUpdatePressed() async {
    switch (_upd) {
      case _UpdState.checking:
      case _UpdState.downloading:
        return; // déjà en cours
      case _UpdState.upToDate:
      case _UpdState.failed:
        await _checkUpdate(); // re-vérifie à la demande
        return;
      case _UpdState.available:
        final UpdateInfo? u = _updInfo;
        if (u == null) return;
        BlackBox.instance.info('MAJ', 'installation demandée → build ${u.versionCode}');
        setState(() {
          _upd = _UpdState.downloading;
          _updPct = 0;
        });
        final bool ok = await UpdateService.instance.downloadAndInstall(
          u,
          onProgress: (double p) {
            final int pct = (p * 100).round();
            if (mounted && pct != _updPct) setState(() => _updPct = pct);
          },
        );
        if (!mounted) return;
        // Si l'installateur s'est ouvert, Android prend la main : l'app sera
        // relancée par le système une fois la mise à jour installée.
        setState(() => _upd = ok ? _UpdState.available : _UpdState.failed);
        return;
    }
  }

  String _updateLabel() {
    switch (_upd) {
      case _UpdState.checking:
        return 'Mise à jour : vérification…';
      case _UpdState.upToDate:
        return 'Mise à jour : à jour${_current.isEmpty ? '' : ' (build $_current)'} — OK pour revérifier';
      case _UpdState.available:
        return 'Nouvelle version ${_updInfo?.versionName ?? ''} (build ${_updInfo?.versionCode}) — OK pour installer';
      case _UpdState.downloading:
        return 'Téléchargement de la mise à jour… $_updPct %';
      case _UpdState.failed:
        return 'Mise à jour : échec (réseau ou installateur) — OK pour réessayer';
    }
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
                    final Color bg = focused ? TvTokens.accent : TvTokens.sel;
                    final Color fg = focused ? TvTokens.onAccent : TvTokens.accentBright;
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
              final Color bg = focused ? TvTokens.accent : TvTokens.sel;
              final Color fg =
                  focused ? TvTokens.onAccent : TvTokens.accentBright;
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
              final Color bg = focused ? TvTokens.accent : TvTokens.sel;
              final Color fg =
                  focused ? TvTokens.onAccent : TvTokens.accentBright;
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
          // ----- Mise à jour in-app (même gabarit que les autres lignes) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: _onUpdatePressed,
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.accent : TvTokens.sel;
              final Color fg =
                  focused ? TvTokens.onAccent : TvTokens.accentBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(
                        _upd == _UpdState.available
                            ? Icons.system_update_rounded
                            : Icons.update_rounded,
                        color: fg,
                        size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_updateLabel(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: TvDimens.title,
                              fontWeight: FontWeight.w700,
                              color: fg)),
                    ),
                    Icon(Icons.chevron_right_rounded, color: fg, size: 26),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          // ----- Boîte noire (journal technique : pourquoi l'app s'est fermée) -----
          TvFocusBuilder(
            scale: TvFocusScale.large,
            onSelect: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TvShell(child: TvBlackBoxScreen()),
              ),
            ),
            builder: (BuildContext context, bool focused) {
              final Color bg = focused ? TvTokens.accent : TvTokens.sel;
              final Color fg =
                  focused ? TvTokens.onAccent : TvTokens.accentBright;
              return Container(
                width: 760,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.flight_takeoff_rounded, color: fg, size: 26),
                    const SizedBox(width: 12),
                    Text('Boîte noire (journal technique)',
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
              final Color bg = focused ? TvTokens.accent : TvTokens.sel;
              final Color fg =
                  focused ? TvTokens.onAccent : TvTokens.accentBright;
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

/// États du bouton de mise à jour des Réglages.
enum _UpdState { checking, upToDate, available, downloading, failed }
