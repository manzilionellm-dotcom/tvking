// =========================================================
//  shield_settings_screen.dart — Mode Bouclier (réglages MOBILE)
// =========================================================
//  Parité avec l'écran TV (tv_shield_screen.dart) : mêmes quatre
//  interrupteurs, même état VPN, même phrase honnête. Réutilise le MÊME
//  PrivacyShield ; ici en widgets Material classiques (tactile).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/privacy/privacy_shield.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class ShieldSettingsScreen extends StatelessWidget {
  const ShieldSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final PrivacyShield s = PrivacyShield.instance;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.tvShieldTitle)),
      body: ListenableBuilder(
        listenable: s,
        builder: (BuildContext context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.shield_rounded),
                title: Text(context.l10n.tvShieldIntro,
                    style: AppTextStyles.bodyMedium),
                trailing: s.vpnDetectionSupported
                    ? Chip(
                        avatar: Icon(
                          s.vpnActive
                              ? Icons.vpn_lock_rounded
                              : Icons.vpn_lock_outlined,
                          size: 18,
                        ),
                        label: Text(s.vpnActive
                            ? context.l10n.tvShieldVpnOn
                            : context.l10n.tvShieldVpnOff),
                      )
                    : null,
              ),
              const Divider(),
              SwitchListTile(
                value: s.enabled,
                onChanged: s.setEnabled,
                title: Text(context.l10n.tvShieldEnable),
                subtitle: Text(context.l10n.tvShieldEnableHint),
              ),
              SwitchListTile(
                value: s.requireVpn,
                onChanged: s.setRequireVpn,
                title: Text(context.l10n.tvShieldRequireVpn),
                subtitle: Text(s.vpnDetectionSupported
                    ? context.l10n.tvShieldRequireVpnHint
                    : context.l10n.tvShieldVpnUnsupported),
              ),
              SwitchListTile(
                value: s.preferHttps,
                onChanged: s.setPreferHttps,
                title: Text(context.l10n.tvShieldHttps),
                subtitle: Text(context.l10n.tvShieldHttpsHint),
              ),
              SwitchListTile(
                value: s.minimalTelemetry,
                onChanged: s.setMinimalTelemetry,
                title: Text(context.l10n.tvShieldTelemetry),
                subtitle: Text(context.l10n.tvShieldTelemetryHint),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  context.l10n.tvShieldHonest,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
