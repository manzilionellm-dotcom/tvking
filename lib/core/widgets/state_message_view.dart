// =========================================================
//  state_message_view.dart — Vue d'état réutilisable (vide / erreur / offline)
// =========================================================
//  Brief design : CHAQUE écran doit traiter ses 4 états — loading
//  (squelette shimmer, cf. shimmer_box.dart), vide, erreur, hors-ligne.
//  Ce widget couvre les 3 états « message » avec un rendu 7 MOTION
//  cohérent : icône cerclée, titre, message, et un bouton d'action
//  optionnel pleinement utilisable à la télécommande (TvFocusable).
//
//  i18n-ready : AUCUNE chaîne codée en dur ici. L'appelant fournit
//  `title` / `message` / `actionLabel` (via AppLocalizations une fois
//  la vague i18n câblée). Le widget ne fait que la mise en forme.
//
//  Context-aware (deux modes + deux flavors) via LumiereColors.
// =========================================================

import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';
import '../theme/cinematic_spacing.dart';
import '../theme/lumiere_tokens.dart';
import 'tv_focusable.dart';

class StateMessageView extends StatelessWidget {
  const StateMessageView({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.accent,
    this.autofocusAction = false,
    super.key,
  });

  /// Icône cerclée illustrant l'état (ex. `Icons.inbox_outlined` pour
  /// vide, `Icons.wifi_off_rounded` pour offline, `Icons.error_outline`
  /// pour erreur). Choisie par l'appelant selon le contexte.
  final IconData icon;

  /// Titre court (1 ligne idéalement).
  final String title;

  /// Message explicatif optionnel (2-3 lignes max).
  final String? message;

  /// Libellé du bouton d'action (ex. « Réessayer »). Si fourni avec
  /// [onAction], un bouton focusable apparaît.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Teinte d'accent. Défaut = accent ember. Pour un état d'erreur,
  /// passer `LumiereColors.of(context).statusError` ; pour offline,
  /// une teinte neutre (textTertiary) est élégante.
  final Color? accent;

  /// Met le focus D-pad sur le bouton d'action dès l'affichage (TV).
  final bool autofocusAction;

  @override
  Widget build(BuildContext context) {
    final LumiereColors c = LumiereColors.of(context);
    final Color tint = accent ?? c.accentEmber;
    final bool hasAction = actionLabel != null && onAction != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CinematicSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // --- Icône cerclée ---
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.elevated,
                border: Border.all(color: c.border),
              ),
              child: Icon(icon, size: 38, color: tint),
            ),
            const SizedBox(height: CinematicSpacing.l),

            // --- Titre ---
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium,
            ),

            // --- Message ---
            if (message != null) ...<Widget>[
              const SizedBox(height: CinematicSpacing.s),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium,
                ),
              ),
            ],

            // --- Bouton d'action (focusable TV) ---
            if (hasAction) ...<Widget>[
              const SizedBox(height: CinematicSpacing.xl),
              TvFocusable(
                onTap: onAction!,
                autofocus: autofocusAction,
                borderRadius:
                    BorderRadius.circular(CinematicSpacing.radiusM),
                semanticsLabel: actionLabel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CinematicSpacing.l,
                    vertical: CinematicSpacing.s,
                  ),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius:
                        BorderRadius.circular(CinematicSpacing.radiusM),
                  ),
                  child: Text(
                    actionLabel!,
                    // Texte sombre sur la teinte vive pour le contraste AA.
                    style: AppTextStyles.button.copyWith(color: c.canvas),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
