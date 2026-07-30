// =========================================================
//  friendly_error_view.dart — Écran d'erreur « à la Netflix »
// =========================================================
//  OBJECTIF (Vague V9)
//  -------------------
//  Un écran d'erreur ne doit JAMAIS montrer :
//    - un écran noir muet (« ça ne marche pas mais je ne sais pas quoi
//      faire »),
//    - du texte technique brut (`Exception: SocketException…`,
//      `type 'Null' is not a subtype…`) que personne ne comprend.
//
//  À la place, comme les grandes apps de streaming, on affiche :
//    1. une ILLUSTRATION / ICÔNE qui traduit le TYPE de problème
//       (réseau coupé, serveur en panne, rien à afficher, imprévu),
//    2. un TITRE court et humain,
//    3. un SOUS-TITRE qui explique et rassure,
//    4. un BOUTON D'ACTION clair (« Réessayer » / « Retour »).
//
//  Ce widget est TRANSVERSE (core/widgets) : un seul endroit pour régler
//  le look des erreurs de toute l'app → cohérence garantie.
//
//  DEUX VARIANTES (même API, deux constructeurs) :
//    - `FriendlyErrorView.mobile(...)` → boutons Material classiques
//      (tap au doigt), typographie mobile.
//    - `FriendlyErrorView.tv(...)`     → boutons FOCUSABLES à la
//      télécommande (D-pad), typo 10-foot (lisible à 3 m), autofocus
//      sur l'action principale pour que « OK » réessaie directement.
//
//  PÉDAGOGIE — Pourquoi le widget ne connaît PAS `context.l10n` ?
//    Volontairement, il reçoit des CHAÎNES DÉJÀ TRADUITES (title,
//    message, actionLabel…). L'appelant écrit `context.l10n.tvRetry`,
//    etc. Avantages :
//      - le widget reste pur (aucune dépendance de génération l10n),
//      - il est réutilisable même hors d'un MaterialApp localisé
//        (tests, previews),
//      - chaque écran choisit les clés les plus justes pour SON
//        contexte (une erreur EPG ≠ une erreur de lecture).
// =========================================================

import 'package:flutter/material.dart';

import '../../features/tv/core/tv_dimens.dart';
import '../../features/tv/core/tv_tokens.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'tv_focusable.dart';

/// Type d'erreur — pilote l'icône par défaut et laisse à terme la porte
/// ouverte à une illustration dédiée par catégorie.
enum FriendlyErrorKind {
  /// Pas de connexion / blocage réseau (FAI, DNS, WiFi coupé).
  network,

  /// Le serveur (fournisseur IPTV, backend) ne répond pas ou renvoie
  /// une erreur — côté distant, pas côté app.
  server,

  /// Aucune donnée à afficher — ce n'est pas une panne, juste « vide »
  /// (aucun résultat, aucune chaîne dans ce rayon…).
  empty,

  /// Imprévu non catégorisé — le filet de sécurité par défaut.
  unknown,
}

/// Écran d'erreur convivial, réutilisable partout dans l'app.
///
/// Exemple — variante MOBILE (dans le `builder` d'un `FutureBuilder`,
/// branche d'échec réseau) :
/// ```dart
/// if (snapshot.hasError) {
///   return FriendlyErrorView.mobile(
///     kind: FriendlyErrorKind.network,
///     title: context.l10n.tvFamilyNetworkError, // « Connexion impossible… »
///     message: context.l10n.tvChannelNetworkHint,
///     actionLabel: context.l10n.buttonRetry,     // « Réessayer »
///     onAction: _reload,
///   );
/// }
/// ```
///
/// Exemple — variante TV (focusable D-pad, « OK » réessaie) :
/// ```dart
/// FriendlyErrorView.tv(
///   kind: FriendlyErrorKind.server,
///   title: context.l10n.tvChannelUnavailable,
///   message: context.l10n.tvBlackBoxAdviceServerDown,
///   actionLabel: context.l10n.tvRetry,      // « Réessayer »
///   onAction: _retry,
///   secondaryLabel: context.l10n.buttonBack, // « Retour »
///   onSecondary: () => Navigator.of(context).pop(),
/// )
/// ```
class FriendlyErrorView extends StatelessWidget {
  /// Variante MOBILE — boutons Material (tap au doigt).
  const FriendlyErrorView.mobile({
    required this.kind,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.icon,
    this.compact = false,
    super.key,
  }) : _tv = false;

  /// Variante TV — boutons focusables télécommande (D-pad), autofocus
  /// sur l'action principale, typographie 10-foot.
  const FriendlyErrorView.tv({
    required this.kind,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.icon,
    this.compact = false,
    super.key,
  }) : _tv = true;

  /// Type d'erreur → choisit l'icône par défaut.
  final FriendlyErrorKind kind;

  /// Titre court et humain (ex. « Connexion impossible »). OBLIGATOIRE.
  final String title;

  /// Sous-titre explicatif / rassurant (optionnel mais recommandé).
  final String? message;

  /// Libellé de l'action principale (ex. « Réessayer »). Si `null`, aucun
  /// bouton principal n'est affiché.
  final String? actionLabel;

  /// Callback de l'action principale (OK télécommande / tap).
  final VoidCallback? onAction;

  /// Libellé de l'action secondaire (ex. « Retour »). Optionnel.
  final String? secondaryLabel;

  /// Callback de l'action secondaire.
  final VoidCallback? onSecondary;

  /// Icône à imposer (sinon celle par défaut du [kind]).
  final IconData? icon;

  /// Mode compact — réduit l'icône et les espacements pour tenir dans
  /// une zone restreinte (rangée, feuille modale) plutôt qu'un plein
  /// écran.
  final bool compact;

  /// Drapeau interne : true = variante TV, false = variante mobile.
  final bool _tv;

  /// Icône par défaut selon le type d'erreur. Choisies pour être
  /// immédiatement « lisibles » : un WiFi barré = réseau, un nuage barré
  /// = serveur, une boîte vide = rien à afficher, un cercle « ! » =
  /// imprévu.
  IconData get _defaultIcon {
    switch (kind) {
      case FriendlyErrorKind.network:
        return Icons.wifi_off_rounded;
      case FriendlyErrorKind.server:
        return Icons.cloud_off_rounded;
      case FriendlyErrorKind.empty:
        return Icons.inbox_rounded;
      case FriendlyErrorKind.unknown:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _tv ? _buildTv(context) : _buildMobile(context);
  }

  // -------------------------------------------------------
  //  VARIANTE MOBILE
  // -------------------------------------------------------
  Widget _buildMobile(BuildContext context) {
    final double iconSize = compact ? 40 : 56;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Icône dans un halo circulaire très discret : donne le
            // « poids » d'une illustration sans image à charger.
            Container(
              width: iconSize + 28,
              height: iconSize + 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceHigh,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                icon ?? _defaultIcon,
                size: iconSize,
                color: AppColors.textTertiary,
              ),
            ),
            SizedBox(height: compact ? 14 : 20),

            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium.copyWith(
                fontSize: compact ? 17 : 20,
              ),
            ),

            if (message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],

            if (actionLabel != null || secondaryLabel != null)
              SizedBox(height: compact ? 16 : 24),

            // Boutons : principal (rempli, accent) + secondaire (contour).
            if (actionLabel != null || secondaryLabel != null)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  if (secondaryLabel != null)
                    OutlinedButton.icon(
                      onPressed: onSecondary,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(secondaryLabel!),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(
                          color: AppColors.accent.withValues(alpha: 0.6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                    ),
                  if (actionLabel != null)
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(actionLabel!),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.voidSurface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  //  VARIANTE TV (10-foot, focusable D-pad)
  // -------------------------------------------------------
  Widget _buildTv(BuildContext context) {
    final double iconSize = compact ? 48 : 72;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TvDimens.safeH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Icône dans un halo circulaire (surface élevée) — cohérent avec
            // l'ADN « Maison Noir » des écrans TV.
            Container(
              width: iconSize + 40,
              height: iconSize + 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: TvTokens.card,
              ),
              child: Icon(
                icon ?? _defaultIcon,
                size: iconSize,
                color: TvTokens.muted,
              ),
            ),
            SizedBox(height: compact ? 18 : 28),

            Text(
              title,
              textAlign: TextAlign.center,
              style: TvTokens.ui(
                compact ? TvDimens.title : TvDimens.headline,
                weight: FontWeight.w700,
                color: TvTokens.text,
              ),
            ),

            if (message != null) ...<Widget>[
              const SizedBox(height: 10),
              ConstrainedBox(
                // On borne la largeur : à 3 m, une ligne trop longue
                // fatigue l'œil. ~640 dp = ligne de lecture confortable.
                constraints: const BoxConstraints(maxWidth: 640),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TvTokens.ui(TvDimens.body, color: TvTokens.muted),
                ),
              ),
            ],

            if (actionLabel != null || secondaryLabel != null)
              SizedBox(height: compact ? 20 : 32),

            if (actionLabel != null || secondaryLabel != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Action principale EN PREMIER + autofocus : à
                  // l'affichage de l'erreur, le focus est déjà sur
                  // « Réessayer » → un simple « OK » relance.
                  if (actionLabel != null)
                    _TvErrorButton(
                      label: actionLabel!,
                      icon: Icons.refresh_rounded,
                      onTap: onAction ?? () {},
                      primary: true,
                      autofocus: true,
                    ),
                  if (actionLabel != null && secondaryLabel != null)
                    const SizedBox(width: 16),
                  if (secondaryLabel != null)
                    _TvErrorButton(
                      label: secondaryLabel!,
                      icon: Icons.arrow_back_rounded,
                      onTap: onSecondary ?? () {},
                      primary: false,
                      autofocus: actionLabel == null,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Bouton d'action TV — focusable télécommande via [TvFocusable].
/// Principal = rempli accent (ember Cinéma) ; secondaire = contour discret.
/// Les couleurs/tailles viennent du design system TV (TvTokens/TvDimens),
/// jamais de valeurs en dur (règle 5 des conventions).
class _TvErrorButton extends StatelessWidget {
  const _TvErrorButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.primary,
    required this.autofocus,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final Color fg = primary ? TvTokens.onEmber : TvTokens.text;
    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      semanticsLabel: label,
      borderRadius: BorderRadius.circular(TvTokens.rButton),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          color: primary ? TvTokens.ember : TvTokens.card,
          border:
              primary ? null : Border.all(color: TvTokens.line, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 22, color: fg),
            const SizedBox(width: 10),
            Text(
              label,
              style: TvTokens.ui(
                TvDimens.body,
                weight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
