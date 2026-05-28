// =========================================================
//  app_text_styles.dart — Typographie LUMIÈRE Maison Noir
// =========================================================
//  Police principale : Inter (chargée via google_fonts).
//  Échelle cinématographique — l'app doit respirer comme une
//  affiche de film, jamais comme un dashboard de SaaS.
//
//  Choix :
//    - Display & headlines en poids moyens (500–700), JAMAIS w800
//      sauf usage très ponctuel — on évite la lourdeur "tape-à-l'œil".
//    - Letter-spacing négatif sur les gros titres pour donner du
//      poids visuel sans alourdir la graisse.
//    - Letter-spacing positif sur les labels (uppercase, signatures
//      typographiques) pour la sensation premium.
//    - Hauteur de ligne (`height`) généreuse sur les corps de texte
//      pour la lisibilité à distance et le rythme cinématographique.
// =========================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTextStyles {
  /// Display XL — réservé aux moments rares (splash, hero d'onboarding).
  /// Poids moyen + tracking serré = sensation "affiche cinéma".
  static TextStyle get displayLarge => GoogleFonts.inter(
        fontSize: 52,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        letterSpacing: -1.4,
        height: 1.05,
      );

  /// Display HERO — titre principal d'une bannière cinéma
  /// edge-to-edge (HomeScreen, hero d'une chaîne en vedette).
  /// Très grand, tracking serré, poids moyen : on imite l'impact
  /// d'une affiche de cinéma. À utiliser parcimonieusement —
  /// jamais plus d'un par écran.
  static TextStyle get displayHero => GoogleFonts.inter(
        fontSize: 38,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: -1.0,
        height: 1.05,
      );

  /// Eyebrow champagne — la petite ligne au-dessus d'un titre
  /// hero ("LE PLUS REGARDÉ", "À LA UNE", "NOUVEAUTÉ"). Couleur
  /// champagne désaturée pour rester premium sans rouge.
  /// Remplace `eyebrow` (qui restait en accent rouge) sur les
  /// surfaces où on ne veut PAS du critique.
  static TextStyle get eyebrowChampagne => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.champagne,
        letterSpacing: 2.6,
        height: 1.0,
      );

  /// Titre de section principal (Films, Séries, Sports…).
  static TextStyle get headlineLarge => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: -0.6,
        height: 1.15,
      );

  /// Titre moyen (nom d'une chaîne en avant, header d'écran).
  static TextStyle get headlineMedium => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: -0.2,
        height: 1.2,
      );

  /// Corps de texte standard — descriptions, paragraphes courts.
  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.5,
      );

  /// Sous-titre / métadonnées (catégorie, durée, qualité).
  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.45,
      );

  /// Petit label uppercase — badges, sections, signatures.
  /// Tracking large = touche premium, lisibilité distinctive.
  static TextStyle get labelSmall => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
        letterSpacing: 1.6,
        height: 1.0,
      );

  /// Eyebrow — petit texte au-dessus d'un titre, utilisé dans les
  /// hero sections et les cards de mise en avant.
  static TextStyle get eyebrow => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.accent,
        letterSpacing: 2.4,
        height: 1.0,
      );

  /// Initiales géantes sur les vignettes sans logo.
  /// Allègement vs ancienne version (w900 → w700) — plus élégant.
  static TextStyle get channelInitials => GoogleFonts.inter(
        fontSize: 56,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -2.4,
        height: 1.0,
      );

  /// Texte de bouton primaire (CTA). Pas en uppercase — on garde
  /// la chaleur du titre cas naturel, tracking légèrement ouvert.
  static TextStyle get button => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        height: 1.0,
      );

  /// Texte numérique tabulaire — durées, horaires, statistiques.
  /// `tabular figures` = chiffres de largeur fixe (pas de saut visuel).
  static TextStyle get numeric => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
}
