import '../../../core/theme/remote_palette.dart';
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

  // ---- Couleurs — système de SURFACES en couches (la profondeur naît de
  //  l'empilement, pas des bordures). Refonte « quiet luxury » : noir CHAUD
  //  (jamais #000 → pas de banding OLED), accent champagne. ----
  static Color get bg => RemotePalette.instance.resolve('background', const Color(0xFF0A0908)); // Surface 0 — noir chaud
  static Color get panel => RemotePalette.instance.resolve('surface', const Color(0xFF0F0D0B)); // sidebar (proche du fond)
  static Color get card => RemotePalette.instance.resolve('surface', const Color(0xFF141210)); // Surface 1 — carte au repos
  static Color get tile => RemotePalette.instance.resolve('surfaceHigh', const Color(0xFF1A1712)); // fond des vignettes de chaînes
  static Color get tileBorder => RemotePalette.instance.resolve('border', const Color(0x0DFFFFFF)); // bordure vignette (blanc 5 %)
  static Color get badgeBg => gold.withValues(alpha: 0.12); // fond badge (or ~12 %)
  static Color get sel => RemotePalette.instance.resolve('surfaceHigh', const Color(0xFF1E1B16)); // Surface 2 — focus / élevé
  static Color get surface3 => RemotePalette.instance.resolve('overlay', const Color(0xFF242019)); // overlay / menu déployé
  static Color get line => RemotePalette.instance.resolve('border', const Color(0xFF2A2620)); // hairline / bordure subtile
  static Color get lineSoft => RemotePalette.instance.resolve('border', const Color(0xFF211D17)); // bordures discrètes (repos)
  static Color get text => RemotePalette.instance.resolve('text', const Color(0xFFF4F1EB)); // texte principal
  static Color get muted => RemotePalette.instance.resolve('secondary', const Color(0xFF9A9388)); // texte secondaire
  static Color get mutedDim => RemotePalette.instance.resolve('muted', const Color(0xFF6B655B)); // texte tertiaire / hints
  static Color get gold => RemotePalette.instance.resolve('accent', const Color(0xFFCCB089)); // ACCENT (brand)
  static Color get goldBright => RemotePalette.instance.resolve('accentBright', const Color(0xFFE4CBA0)); // OR FOCUS (texte + lueur)
  static Color get goldDeep => RemotePalette.instance.resolve('accentDeep', const Color(0xFF9C855F)); // or sombre : dégradés
  static const Color live = Color(0xFFE0503C); // pastille EN DIRECT (rouge vif sobre)
  static const Color success = Color(0xFF5FA975); // ✓ copié

  // ---- Rayons ----
  static const double rCard = 18;
  static const double rButton = 14;
  static const double rMenuItem = 12;
  static const double rSmall = 10;

  // ---- Fond global : radial-gradient or très sombre sur noir profond ----
  static Gradient get bgGradient => RadialGradient(
    center: const Alignment(0.56, -0.40), // 78% / 30%
    radius: 1.3,
    colors: <Color>[RemotePalette.instance.resolve('surface', const Color(0xFF15120E)), bg],
    stops: const <double>[0.0, 0.6],
  );

  // ---- Halo chaud discret derrière le branding (coin haut-gauche) ----
  // Profondeur « premium » : évite le noir plat sous le logo The Few.
  static Gradient get brandGlow => RadialGradient(
    center: Alignment.topLeft,
    radius: 1.1,
    colors: <Color>[gold.withValues(alpha: 0.08), gold.withValues(alpha: 0)],
  );

  // ---- Filet d'accent or (haut de carte) ----
  static Gradient get goldHairline => LinearGradient(
    colors: <Color>[const Color(0x00CCB089), gold, const Color(0x00CCB089)],
  );

  // ---- CTA principal (dégradé or) ----
  static Gradient get ctaGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[goldBright, gold],
  );

  // ---- Pastille prix ----
  static Gradient get pillGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[gold.withValues(alpha: 0.06), gold.withValues(alpha: 0)],
  );

  // =========================================================
  //  TYPOGRAPHIE — 3 rôles, jamais plus.
  //   • display = Oswald (titres d'accent, sobriété TV)
  //   • ui      = Inter  (tout le reste)
  //   • mono    = JetBrains Mono (code d'activation / identifiants UNIQUEMENT)
  // =========================================================
  static TextStyle display(double size,
          {FontWeight weight = FontWeight.w600, Color? color, double spacing = 0}) =>
      GoogleFonts.oswald(
          fontSize: size, fontWeight: weight, color: color ?? text, letterSpacing: spacing);

  static TextStyle ui(double size,
          {FontWeight weight = FontWeight.w400, Color? color, double spacing = 0}) =>
      GoogleFonts.inter(
          fontSize: size, fontWeight: weight, color: color ?? text, letterSpacing: spacing);

  static TextStyle mono(double size,
          {FontWeight weight = FontWeight.w600, Color? color, double spacing = 0}) =>
      GoogleFonts.jetBrainsMono(
          fontSize: size, fontWeight: weight, color: color ?? goldBright, letterSpacing: spacing);
}
