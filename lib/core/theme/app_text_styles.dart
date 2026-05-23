// =========================================================
//  app_text_styles.dart — Typographie "TV King"
// =========================================================
//  Police principale : Inter (chargée via google_fonts).
//  On définit ici TOUTES les tailles utilisées dans l'app
//  pour garder une hiérarchie cohérente.
//
//  Échelle volontairement généreuse — l'app doit être lisible
//  à 3 mètres sur une TV.
// =========================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTextStyles {
  /// Titre XL (écran d'accueil, "TV KING").
  static TextStyle get displayLarge => GoogleFonts.inter(
        fontSize: 48,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -1.0,
        height: 1.1,
      );

  /// Titre de section (ex : "Mes favoris", "En direct").
  static TextStyle get headlineLarge => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      );

  /// Titre moyen (nom d'une chaîne en gros).
  static TextStyle get headlineMedium => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  /// Corps de texte standard.
  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  /// Sous-titre / métadonnées (catégorie, durée, etc.).
  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  /// Petit label (badges, numéros de chaîne).
  static TextStyle get labelSmall => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 1.2,
      );

  /// Style des initiales géantes sur les vignettes sans logo.
  static TextStyle get channelInitials => GoogleFonts.inter(
        fontSize: 56,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
        letterSpacing: -2,
      );
}
