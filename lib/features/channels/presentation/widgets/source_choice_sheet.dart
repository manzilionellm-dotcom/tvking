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

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/support/vip_support.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/legal_disclaimer.dart';
import '../../../device/data/device_identity.dart';
import '../../../onboarding/data/device_class_repository.dart';
import '../../../playlists/presentation/m3u_login_sheet.dart';
import '../../../playlists/presentation/xtream_login_sheet.dart';
import 'mac_activation_view.dart';

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
    // TÉLÉPHONE : activation par code MAC UNIQUEMENT (ni M3U, ni serveur,
    // ni identifiant) — demande explicite et répétée du client. La TV
    // garde ses options d'ajout (elle a son propre écran dédié,
    // TvAddSourceScreen) : on n'y touche pas.
    final bool isTv = DeviceClassRepository.instance.isTvFor(context);
    if (!isTv) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
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
              MacActivationView(
                onActivated: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      );
    }

    // TV : les chemins d'ajout d'origine (inchangés).
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
                      'Bonjour, je veux activer The Few. '
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
            const SizedBox(height: 18),
            // Mention légale au moment clé (saisie d'une source IPTV) :
            // rappelle que l'app est un simple lecteur et ne fournit aucun
            // contenu — l'utilisateur apporte et assume sa propre source.
            const LegalDisclaimer.compact(),
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
        child: Column(
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
            // Toute la logique (code MAC + copier + envoyer + vérifier) vit
            // dans MacActivationView, partagé avec l'écran d'accueil vide.
            MacActivationView(
              onActivated: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
