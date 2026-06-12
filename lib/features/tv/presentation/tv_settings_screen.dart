// =========================================================
//  tv_settings_screen.dart — Réglages (MAC à activer + statut)
// =========================================================
//  ESSENTIEL : affiche en GROS la MAC de cette TV (à donner au revendeur
//  pour l'activer) + l'état de l'abonnement (lu sur le MÊME worker que le
//  panel). Un bouton focusable rafraîchit le statut.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';

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

  ({String label, Color color}) get _status {
    switch (SubscriptionState.instance.status) {
      case SubscriptionStatus.paid:
        return (label: 'Abonnement actif', color: const Color(0xFF3FBE7C));
      case SubscriptionStatus.trialActive:
        final int d = SubscriptionState.instance.trialDaysRemaining;
        return (label: 'Essai — $d jour(s) restants', color: const Color(0xFF5AA0E8));
      case SubscriptionStatus.trialExpired:
        return (label: 'Essai terminé — à activer', color: const Color(0xFFE8B23A));
      case SubscriptionStatus.frozen:
        return (label: 'Compte gelé', color: const Color(0xFFE8B23A));
      case SubscriptionStatus.banned:
        return (label: 'Compte banni', color: const Color(0xFFFF5A4A));
      case SubscriptionStatus.unknown:
        return (label: 'Non activé', color: AppColors.textTertiary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({String label, Color color}) st = _status;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Réglages',
              style: TextStyle(
                  fontSize: TvDimens.displayM,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 24),

          // ----- Carte MAC -----
          Container(
            width: 760,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(TvDimens.panelRadius),
              border: Border.all(color: AppColors.maisonBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Adresse de cet appareil (MAC)',
                    style: TextStyle(
                        fontSize: TvDimens.label,
                        color: AppColors.textTertiary)),
                const SizedBox(height: 10),
                SelectableText(
                  _mac,
                  style: TextStyle(
                    fontSize: TvDimens.displayS,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Donne cette adresse à ton revendeur pour activer DeFew TV.',
                  style: TextStyle(
                      fontSize: TvDimens.body, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 22),

                // ----- Statut -----
                Row(
                  children: <Widget>[
                    Text('Statut : ',
                        style: TextStyle(
                            fontSize: TvDimens.title,
                            color: AppColors.textSecondary)),
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
                    final Color bg =
                        focused ? AppColors.textPrimary : AppColors.surfaceHigh;
                    final Color fg =
                        focused ? AppColors.background : AppColors.textPrimary;
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
                          Text(_busy ? 'Vérification…' : 'Rafraîchir le statut',
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
        ],
      ),
    );
  }
}
