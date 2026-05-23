// =========================================================
//  app_colors.dart — Palette officielle "TV King VIP"
// =========================================================
//  Toutes les couleurs de l'app vivent ICI.
//  Règle absolue : ne JAMAIS écrire `Color(0xFF...)` ailleurs
//  dans le projet. Toujours passer par AppColors.x.
//  Comme ça, si demain on change la teinte d'accent, on le
//  fait en un seul endroit.
// =========================================================

import 'package:flutter/material.dart';

/// Palette de l'application.
///
/// `abstract final` = on ne peut pas instancier cette classe,
/// on l'utilise uniquement comme namespace : `AppColors.background`.
abstract final class AppColors {
  // ----- Fonds -----------------------------------------------------
  /// Fond principal : noir profond, presque bleuté.
  static const Color background = Color(0xFF0A0A0F);

  /// Surface des cartes / panneaux (un cran plus clair que le fond).
  static const Color surface = Color(0xFF1A1A24);

  /// Variante de surface, plus claire encore, pour le hover/focus.
  static const Color surfaceHigh = Color(0xFF24243A);

  // ----- Accents ---------------------------------------------------
  /// Rose électrique — accent principal (boutons, focus, badges live).
  static const Color accentPink = Color(0xFFFF3366);

  /// Cyan lumineux — accent secondaire (liens, highlights).
  static const Color accentCyan = Color(0xFF00D9FF);

  /// Or — réservé aux badges "Premium" et au logo.
  static const Color gold = Color(0xFFFFD700);

  // ----- Texte -----------------------------------------------------
  /// Texte principal (100 % blanc).
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Texte secondaire (sous-titres, métadonnées).
  static const Color textSecondary = Color(0xB3FFFFFF); // 70 % opacité

  /// Texte discret (timestamps, hints).
  static const Color textMuted = Color(0x80FFFFFF); // 50 % opacité

  // ----- Sémantique ------------------------------------------------
  /// Rouge "live" — pulse sous les chaînes en direct.
  static const Color live = Color(0xFFFF1744);

  /// Vert OK (succès, téléchargement terminé).
  static const Color success = Color(0xFF00E676);

  /// Orange warning (buffering, réseau faible).
  static const Color warning = Color(0xFFFFAB00);

  // ----- Gradients réutilisables -----------------------------------
  /// Dégradé "halo VIP" — utilisé en arrière-plan de l'app.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF0A0A0F),
      Color(0xFF12121F),
      Color(0xFF0A0A0F),
    ],
  );

  /// Dégradé bouton premium (rose -> cyan).
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[accentPink, accentCyan],
  );
}
