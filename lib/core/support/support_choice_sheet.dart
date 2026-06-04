// =========================================================
//  support_choice_sheet.dart — Bottom sheet 2 choix contact
// =========================================================
//  Quand l'utilisateur tape le bouton Aide VIP, ou le bouton
//  "Activer mes chaînes", on lui propose DEUX canaux :
//
//    1. MESSAGE (instantané)     → ouvre WhatsApp en silence
//                                   avec le bon message pré-rempli.
//    2. APPEL TÉLÉPHONIQUE       → ouvre le composeur Téléphone
//                                   pré-rempli avec le numéro support.
//
//  Le mot "WhatsApp" n'est JAMAIS écrit côté UI — c'est purement
//  un détail d'implémentation. Le client voit deux canaux pro,
//  équivalents, comme dans toute app de service premium (banques,
//  assurances, conciergerie privée).
//
//  Design : sheet avec poignée glissable, fond surfaceHigh,
//  cards ember sobres, animations 180 ms. Compatible TV (focus
//  D-pad sur chaque carte via TvFocusable).
// =========================================================

import 'package:flutter/material.dart';

import '../i18n/l10n_extension.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/tv_focusable.dart';
import 'vip_support.dart';

/// Affiche le sheet de choix. Appelle ce helper depuis n'importe
/// quel bouton "support" / "aide" / "activation".
///
/// - `customMessage` : message pré-rempli côté messagerie (utile
///   pour les boutons d'activation qui doivent envoyer le MAC).
///   Si null, message générique 'j'ai besoin d'aide'.
Future<void> showSupportChoiceSheet(
  BuildContext context, {
  String? customMessage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext sheetCtx) => _SupportChoiceSheet(
      customMessage: customMessage,
    ),
  );
}

class _SupportChoiceSheet extends StatelessWidget {
  const _SupportChoiceSheet({this.customMessage});

  final String? customMessage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ----- Poignée d'arrastre du sheet -----
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(context.l10n.supportHowToReach,
                style: AppTextStyles.headlineMedium.copyWith(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              context.l10n.supportPickChannel,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),

            // ===== Option 1 — Message instantané =====
            _ChoiceCard(
              icon: Icons.forum_rounded,
              title: context.l10n.supportInstantMessage,
              subtitle: context.l10n.supportInstantMessageSub,
              onTap: () async {
                Navigator.of(context).pop();
                final bool ok = await VipSupport.openWhatsApp(
                  customMessage: customMessage,
                );
                if (!ok && context.mounted) {
                  _toast(context, context.l10n.supportMessageError);
                }
              },
            ),
            const SizedBox(height: 12),

            // ===== Option 2 — Appel téléphonique =====
            _ChoiceCard(
              icon: Icons.phone_in_talk_rounded,
              title: context.l10n.supportPhoneCall,
              subtitle:
                  context.l10n.supportPhoneCallSub(VipSupport.displayNumber),
              onTap: () async {
                Navigator.of(context).pop();
                final bool ok = await VipSupport.openPhoneCall();
                if (!ok && context.mounted) {
                  _toast(context, context.l10n.supportCallError);
                }
              },
            ),

            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  context.l10n.buttonCancel,
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message, style: AppTextStyles.bodyMedium),
      ),
    );
  }
}

/// Carte cliquable d'un canal de contact — focus-aware via
/// `TvFocusable` pour rester utilisable à la télécommande TV.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
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
    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      unfocusedBorderColor: AppColors.border,
      semanticsLabel: title,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            // ----- Pastille icône ember -----
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.45),
                ),
              ),
              child: Icon(
                icon,
                color: AppColors.accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            // ----- Titre + sous-titre -----
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.accent,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
