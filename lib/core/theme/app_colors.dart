// =========================================================
//  app_colors.dart — Palette "TV King" v2 (premium streaming)
// =========================================================
//  Refonte Phase 1.4 — direction "Apple TV / Netflix / Plex" :
//
//    - Un SEUL accent primaire (or) — fini les arc-en-ciels
//      rose/cyan/or qui rendaient l'UI "tape à l'œil".
//    - Fond bleu nuit profond (PAS noir pur) — plus doux à
//      l'œil sur écran OLED, sensation "cinéma".
//    - Surfaces structurées en 3 niveaux d'élévation.
//    - Texte hiérarchisé en 3 tons (primaire / secondaire / muet).
//    - Couleurs sémantiques (live/success/warning) discrètes.
//
//  Règle absolue : aucun `Color(0xFF...)` ailleurs dans l'app.
//  Tout passe par AppColors.X.
//
//  Migration : les anciennes constantes (accentPink, accentCyan,
//  gold) sont conservées comme alias vers les nouvelles couleurs
//  pour ne pas casser l'existant — mais le nouveau code utilise
//  uniquement `accent`, `textSecondary`, etc.
// =========================================================

import 'package:flutter/material.dart';

abstract final class AppColors {
  // -------------------------------------------------------
  //  FONDS / SURFACES
  // -------------------------------------------------------

  /// Fond principal de l'app : bleu nuit profond.
  /// Volontairement PAS noir pur — moins fatigant pour les yeux,
  /// donne une sensation "cinéma" / "premium".
  static const Color background = Color(0xFF0F1216);

  /// Surface élevée (cards, panneaux, sheets).
  static const Color surface = Color(0xFF1A1F26);

  /// Surface très élevée (modals, snackbars, dialogs).
  static const Color surfaceHigh = Color(0xFF242B33);

  /// Surface au survol/focus, ou pour structurer des sections
  /// imbriquées sans casser la hiérarchie.
  static const Color surfaceOverlay = Color(0xFF2F3640);

  /// Bordure subtile pour délimiter des cards sans agressivité.
  static Color get border => Colors.white.withValues(alpha: 0.06);

  // -------------------------------------------------------
  //  ACCENT UNIQUE
  // -------------------------------------------------------

  /// Couleur d'accent UNIQUE — un or chaud qui signe "premium".
  /// Utilisée pour : focus actif, état sélectionné, CTA principal,
  /// badges importants, indicateurs critiques.
  static const Color accent = Color(0xFFFFCB05);

  /// Variante atténuée de l'accent — pour les états "hover passif",
  /// les bordures actives, les icônes secondaires.
  static const Color accentMuted = Color(0xFFB89200);

  /// Très subtil — fond d'un état sélectionné, halo lointain.
  static Color get accentSurface => accent.withValues(alpha: 0.12);

  // -------------------------------------------------------
  //  TEXTE
  // -------------------------------------------------------

  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Gris froid lisible mais discret — sous-titres, métadonnées.
  static const Color textSecondary = Color(0xFFA8B2C0);

  /// Texte très estompé — hints, timestamps, états désactivés.
  static const Color textMuted = Color(0xFF5C6675);

  // -------------------------------------------------------
  //  SÉMANTIQUE
  // -------------------------------------------------------

  /// Rouge sang pour le badge LIVE et les erreurs critiques.
  static const Color live = Color(0xFFFF4757);

  /// Vert apaisant — confirmations, état "OK".
  static const Color success = Color(0xFF1ED760);

  /// Orange chaud — buffering, attentions.
  static const Color warning = Color(0xFFFFA940);

  // -------------------------------------------------------
  //  GRADIENTS RÉUTILISÉS
  // -------------------------------------------------------

  /// Dégradé de fond global de l'app — très subtil pour donner
  /// de la profondeur sans détourner le regard du contenu.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF14181F),
      Color(0xFF0F1216),
      Color(0xFF0B0E12),
    ],
  );

  /// Voile de lecture sur images / vignettes pour rendre le texte
  /// blanc lisible par-dessus. À appliquer en `Positioned.fill`.
  static const LinearGradient cardScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0x00000000),
      Color(0xCC000000),
    ],
    stops: <double>[0.0, 0.4, 1.0],
  );

  // -------------------------------------------------------
  //  ALIAS DÉPRÉCIÉS (compatibilité ascendante uniquement)
  // -------------------------------------------------------
  //  Le code existant utilise encore ces noms. On les redirige
  //  vers les nouvelles couleurs pour ne rien casser. Pour le
  //  nouveau code → utiliser les noms ci-dessus directement.
  // -------------------------------------------------------

  @Deprecated('Use AppColors.accent instead')
  static const Color accentPink = accent;

  @Deprecated('Use AppColors.textSecondary or AppColors.accentMuted instead')
  static const Color accentCyan = textSecondary;

  @Deprecated('Use AppColors.accent instead')
  static const Color gold = accent;

  /// Dégradé premium (or → or muted) — réservé aux CTA "Premium"
  /// (futur Phase 5). Pas utilisé dans la nav courante.
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[accent, accentMuted],
  );
}
