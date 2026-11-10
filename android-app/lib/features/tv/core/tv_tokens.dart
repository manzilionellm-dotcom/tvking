// Palette Noir Fantôme partagée avec la TV : OLED, verre charbon et platine.
// Les couleurs sont centralisées ; aucune modification des lecteurs natifs.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

class TvTokens {
  TvTokens._();

  // ---- Couleurs — système de SURFACES en couches ----
  static const Color bg = AppColors.stealthBlack;
  static const Color panel = AppColors.stealthSurface;
  static const Color card = AppColors.stealthGlass;
  static const Color tile = AppColors.stealthSurface;
  static const Color tileBorder =
      Color(0x0DFFFFFF); // bordure vignette (blanc 5 %)
  static const Color badgeBg = Color(0x1FE6EBF2);
  static const Color sel = Color(0xFF1E1E25); // Surface 2 — focus / élevé
  static const Color surface3 = Color(0xFF24242C); // overlay / menu déployé
  static const Color line = Color(0xFF2B2B34); // hairline / bordure subtile
  static const Color lineSoft = Color(0xFF202027); // bordures discrètes (repos)
  static const Color text = AppColors.stealthPlatinum;
  static const Color muted = AppColors.stealthMuted;
  static const Color mutedDim = Color(0xFF6C6B76); // texte tertiaire / hints
  static const Color accent = AppColors.stealthPlatinum;
  static const Color accentBright = AppColors.stealthIce;
  static const Color accentDeep = Color(0xFF7794B5);
  static const Color onAccent = AppColors.stealthBlack;
  static const Color live =
      Color(0xFFFF4D3D); // pastille EN DIRECT (rouge chaud)
  static const Color success = Color(0xFF4CC38A); // ✓ copié / actif

  // ---- Rayons ----
  static const double rCard = 18;
  static const double rButton = 14;
  static const double rMenuItem = 12;
  static const double rSmall = 10;

  // ---- Fond OLED uniforme ----
  static const Gradient bgGradient = RadialGradient(
    center: Alignment(0.56, -0.40), // 78% / 30%
    radius: 1.3,
    colors: <Color>[bg, bg],
    stops: <double>[0.0, 0.6],
  );

  // ---- Halo platine discret derrière le branding (coin haut-gauche) ----
  // Profondeur « premium » : évite le noir plat sous le logo Zuno.
  static const Gradient brandGlow = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.1,
    colors: <Color>[Color(0x18B7D4FF), Color(0x00000000)],
  );

  // ---- Filet d'accent platine (haut de carte) ----
  static const Gradient accentHairline = LinearGradient(
    colors: <Color>[Color(0x00E6EBF2), accent, Color(0x00E6EBF2)],
  );

  // ---- CTA principal platine ----
  static const Gradient ctaGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[accentBright, accent],
  );

  // ---- Pastille prix ----
  static const Gradient pillGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0x12E6EBF2), Color(0x00E6EBF2)],
  );

  // =========================================================
  //  TYPOGRAPHIE — 3 rôles, jamais plus.
  //   • display = Oswald (titres d'accent : condensé, « métal » — contraste
  //               net avec la calligraphie du logo, qu'on ne copie PAS)
  //   • ui      = Inter  (tout le reste)
  //   • mono    = JetBrains Mono (code d'activation / identifiants UNIQUEMENT)
  // =========================================================
  static TextStyle display(double size,
          {FontWeight weight = FontWeight.w600,
          Color color = text,
          double spacing = 0}) =>
      GoogleFonts.oswald(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: spacing);

  static TextStyle ui(double size,
          {FontWeight weight = FontWeight.w400,
          Color color = text,
          double spacing = 0}) =>
      GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: spacing);

  static TextStyle mono(double size,
          {FontWeight weight = FontWeight.w600,
          Color color = accentBright,
          double spacing = 0}) =>
      GoogleFonts.jetBrainsMono(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: spacing);
}
