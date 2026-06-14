// =========================================================
//  tv_tokens.dart — Design System « Maison Noir » (The Few)
// =========================================================
//  Source de vérité UNIQUE des couleurs, rayons, dégradés et styles de
//  texte de DeFew TV. AUCUNE couleur en dur dans les écrans : tout passe
//  par ici. ADN : club privé, noir profond, or discret.
// =========================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TvTokens {
  TvTokens._();

  // ---- Couleurs (valeurs EXACTES de la charte) ----
  static const Color bg = Color(0xFF070707); // fond global, noir profond
  static const Color panel = Color(0xFF0E0D0C); // sidebar / surfaces
  static const Color card = Color(0xFF121110); // cartes
  static const Color tile = Color(0xFF161514); // fond des vignettes de chaînes
  static const Color tileBorder = Color(0x0DFFFFFF); // bordure vignette (blanc 5 %)
  static const Color badgeBg = Color(0x1FCCB089); // fond badge (or ~12 %)
  static const Color sel = Color(0xFF181512); // item de menu sélectionné
  static const Color line = Color(0xFF231F19); // bordures / séparateurs
  static const Color lineSoft = Color(0xFF1D1A15); // bordures discrètes
  static const Color text = Color(0xFFF3EFE9); // texte principal
  static const Color muted = Color(0xFF8A8377); // texte secondaire
  static const Color mutedDim = Color(0xFF5B554C); // texte tertiaire / hints
  static const Color gold = Color(0xFFCCB089); // ACCENT (logo)
  static const Color goldBright = Color(0xFFE6CFA4); // prix, code, titres d'accent
  static const Color goldDeep = Color(0xFF9C855F); // or sombre : dégradés
  static const Color live = Color(0xFFC8503F); // badge DIRECT (rouge sobre)
  static const Color success = Color(0xFF5FA975); // ✓ copié

  // ---- Rayons ----
  static const double rCard = 18;
  static const double rButton = 14;
  static const double rMenuItem = 12;
  static const double rSmall = 10;

  // ---- Fond global : radial-gradient or très sombre sur noir profond ----
  static const Gradient bgGradient = RadialGradient(
    center: Alignment(0.56, -0.40), // 78% / 30%
    radius: 1.3,
    colors: <Color>[Color(0xFF15120E), bg],
    stops: <double>[0.0, 0.6],
  );

  // ---- Halo chaud discret derrière le branding (coin haut-gauche) ----
  // Profondeur « premium » : évite le noir plat sous le logo The Few.
  static const Gradient brandGlow = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.1,
    colors: <Color>[Color(0x14CCB089), Color(0x00000000)],
  );

  // ---- Filet d'accent or (haut de carte) ----
  static const Gradient goldHairline = LinearGradient(
    colors: <Color>[Color(0x00CCB089), gold, Color(0x00CCB089)],
  );

  // ---- CTA principal (dégradé or) ----
  static const Gradient ctaGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[goldBright, gold],
  );

  // ---- Pastille prix ----
  static const Gradient pillGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0x0FCCB089), Color(0x00CCB089)],
  );

  // =========================================================
  //  TYPOGRAPHIE — 3 rôles, jamais plus.
  //   • display = Oswald (titres d'accent, sobriété TV)
  //   • ui      = Inter  (tout le reste)
  //   • mono    = JetBrains Mono (code d'activation / identifiants UNIQUEMENT)
  // =========================================================
  static TextStyle display(double size,
          {FontWeight weight = FontWeight.w600, Color color = text, double spacing = 0}) =>
      GoogleFonts.oswald(
          fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing);

  static TextStyle ui(double size,
          {FontWeight weight = FontWeight.w400, Color color = text, double spacing = 0}) =>
      GoogleFonts.inter(
          fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing);

  static TextStyle mono(double size,
          {FontWeight weight = FontWeight.w600, Color color = goldBright, double spacing = 0}) =>
      GoogleFonts.jetBrainsMono(
          fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing);
}
