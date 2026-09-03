// =========================================================
//  tv_shield_screen.dart — Mode Bouclier (réglages TV)
// =========================================================
//  Écran de réglage du bouclier vie privée (core/privacy/privacy_shield.dart).
//  Même patron que tv_display_settings_screen : libellé, indice, choix
//  Activé / Désactivé au D-pad. En haut, l'état VPN en temps réel ; en bas,
//  la phrase HONNÊTE sur ce que le fournisseur voit encore. On ne vend
//  jamais au client une protection qu'on n'a pas.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/privacy/privacy_shield.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvShieldScreen extends StatelessWidget {
  const TvShieldScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final PrivacyShield s = PrivacyShield.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: s,
        builder: (BuildContext context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.shield_rounded,
                        color: TvTokens.goldBright, size: 30),
                    const SizedBox(width: 12),
                    Text(
                      context.l10n.tvShieldTitle,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text,
                      ),
                    ),
                    const Spacer(),
                    _vpnBadge(context, s),
                  ],
                ),
                const SizedBox(height: 8),
                _hint(context.l10n.tvShieldIntro),
                const SizedBox(height: 24),

                // ----- Interrupteur principal -----
                _label(context.l10n.tvShieldEnable),
                const SizedBox(height: 4),
                _hint(context.l10n.tvShieldEnableHint),
                const SizedBox(height: 12),
                _onOff(
                  context,
                  value: s.enabled,
                  onChanged: s.setEnabled,
                ),
                const SizedBox(height: 30),

                // ----- Coupe-circuit VPN -----
                _label(context.l10n.tvShieldRequireVpn),
                const SizedBox(height: 4),
                _hint(s.vpnDetectionSupported
                    ? context.l10n.tvShieldRequireVpnHint
                    : context.l10n.tvShieldVpnUnsupported),
                const SizedBox(height: 12),
                _onOff(
                  context,
                  value: s.requireVpn,
                  onChanged: s.setRequireVpn,
                ),
                const SizedBox(height: 30),

                // ----- HTTPS préféré -----
                _label(context.l10n.tvShieldHttps),
                const SizedBox(height: 4),
                _hint(context.l10n.tvShieldHttpsHint),
                const SizedBox(height: 12),
                _onOff(
                  context,
                  value: s.preferHttps,
                  onChanged: s.setPreferHttps,
                ),
                const SizedBox(height: 30),

                // ----- Télémétrie minimale -----
                _label(context.l10n.tvShieldTelemetry),
                const SizedBox(height: 4),
                _hint(context.l10n.tvShieldTelemetryHint),
                const SizedBox(height: 12),
                _onOff(
                  context,
                  value: s.minimalTelemetry,
                  onChanged: s.setMinimalTelemetry,
                ),
                const SizedBox(height: 34),

                // ----- La phrase honnête -----
                Container(
                  width: 760,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: TvTokens.sel,
                    borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                    border: Border.all(color: TvTokens.lineSoft),
                  ),
                  child: Text(
                    context.l10n.tvShieldHonest,
                    style: const TextStyle(
                        fontSize: 15, color: TvTokens.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Pastille d'état VPN : verte si actif, sobre sinon. Sans détection
  /// (Windows, Tizen) on n'affiche rien plutôt qu'un faux « aucun VPN ».
  Widget _vpnBadge(BuildContext context, PrivacyShield s) {
    if (!s.vpnDetectionSupported) return const SizedBox.shrink();
    final bool on = s.vpnActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: on ? TvTokens.badgeBg : TvTokens.sel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: on ? TvTokens.gold : TvTokens.lineSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(on ? Icons.vpn_lock_rounded : Icons.vpn_lock_outlined,
              size: 18, color: on ? TvTokens.goldBright : TvTokens.muted),
          const SizedBox(width: 8),
          Text(
            on ? context.l10n.tvShieldVpnOn : context.l10n.tvShieldVpnOff,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: on ? TvTokens.goldBright : TvTokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(
        t,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: TvTokens.text,
        ),
      );

  Widget _hint(String t) => SizedBox(
        width: 760,
        child: Text(
          t,
          style: const TextStyle(fontSize: 14, color: TvTokens.muted),
        ),
      );

  Widget _onOff(
    BuildContext context, {
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) {
    return Row(
      children: <Widget>[
        _choice(
          label: context.l10n.tvEnabled,
          selected: value,
          onSelect: () => onChanged(true),
        ),
        const SizedBox(width: 12),
        _choice(
          label: context.l10n.tvDisabled,
          selected: !value,
          onSelect: () => onChanged(false),
        ),
      ],
    );
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? TvTokens.gold
            : (selected ? TvTokens.badgeBg : TvTokens.sel);
        final Color fg = focused ? TvTokens.onGold : TvTokens.text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: selected ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.check_rounded, size: 20, color: fg),
                ),
              Text(
                label,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        );
      },
    );
  }
}
