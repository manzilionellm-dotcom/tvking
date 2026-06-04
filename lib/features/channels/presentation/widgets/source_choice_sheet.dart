// =========================================================
//  source_choice_sheet.dart — Feuille "Ma source" (accueil)
// =========================================================
//  Demande utilisateur 2026-06-01 : depuis l'accueil, en 1 tap sur
//  le bouton "+", proposer DEUX chemins clairs et confortables :
//
//    1. "Ajouter mes codes"  → AddPlaylistScreen (Xtream / M3U /
//                              M3U en lot). Le client colle ses
//                              propres identifiants.
//    2. "Activer l'app"      → activation à distance par le
//                              revendeur : on montre l'identifiant
//                              appareil (MAC), copiable + envoyable
//                              au support en 1 tap.
//
//  Réutilise les briques existantes (DeviceIdentity pour le MAC,
//  showSupportChoiceSheet pour le contact "concierge" invisible).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/support/support_choice_sheet.dart';
import '../../../../core/support/vip_support.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../device/data/device_identity.dart';
import '../../../playlists/presentation/m3u_login_sheet.dart';
import '../../../playlists/presentation/xtream_login_sheet.dart';

/// Ouvre la feuille de choix de source depuis l'accueil.
Future<void> showSourceChoiceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext ctx) => const _SourceChoiceSheet(),
  );
}

class _SourceChoiceSheet extends StatelessWidget {
  const _SourceChoiceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Poignée.
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.mySource,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.sourceQuestion,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),

            _SourceTile(
              icon: Icons.vpn_key_rounded,
              title: context.l10n.sourceLoginCode,
              subtitle: context.l10n.sourceLoginCodeSub,
              onTap: () {
                Navigator.of(context).pop();
                showXtreamLoginSheet(context);
              },
            ),
            const SizedBox(height: 12),
            _SourceTile(
              icon: Icons.link_rounded,
              title: context.l10n.sourceOwn,
              subtitle: context.l10n.sourceOwnSub,
              onTap: () {
                Navigator.of(context).pop();
                showM3uLoginSheet(context);
              },
            ),
            const SizedBox(height: 12),
            _SourceTile(
              icon: Icons.support_agent_rounded,
              title: context.l10n.sourceActivate,
              subtitle: context.l10n.sourceActivateSub,
              onTap: () async {
                // Redirige DIRECTEMENT vers le contact (WhatsApp) avec la
                // MAC pré-remplie : le client n'a qu'à envoyer. Si WhatsApp
                // n'est pas dispo, on retombe sur l'écran MAC classique
                // (copier + autres canaux).
                final String mac = await DeviceIdentity.instance.mac;
                final bool ok = await VipSupport.openWhatsApp(
                  customMessage:
                      'Bonjour, je veux activer BLACK7 ROYAL. '
                      'Mon identifiant (MAC) : $mac',
                );
                if (!context.mounted) return;
                if (ok) {
                  Navigator.of(context).pop();
                } else {
                  showActivationSheet(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte de choix (icône + titre + sous-titre), grand format tap-friendly.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accentSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================
//  Feuille d'activation à distance (MAC)
// =========================================================

/// Ouvre la feuille d'activation : montre l'identifiant appareil (MAC),
/// copiable + envoyable au support en 1 tap.
Future<void> showActivationSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext ctx) => const _ActivationSheet(),
  );
}

class _ActivationSheet extends StatelessWidget {
  const _ActivationSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: FutureBuilder<String>(
          future: DeviceIdentity.instance.mac,
          builder: (BuildContext context, AsyncSnapshot<String> snap) {
            final String? mac = snap.data;
            final String macDisplay = mac ?? 'MK:??:??:??:??:??';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SelectableText(
                    macDisplay,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
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
                                await Clipboard.setData(
                                  ClipboardData(text: mac),
                                );
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
                            : () => showSupportChoiceSheet(
                                  context,
                                  customMessage:
                                      'Bonjour, voici mon identifiant pour '
                                      'activer mes chaînes :\n\n$mac',
                                ),
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
              ],
            );
          },
        ),
      ),
    );
  }
}
