// =========================================================
//  tv_tokens.dart — Design System « Maison Noir » Zuno (TV)
// =========================================================
//  Source de vérité UNIQUE des couleurs, rayons, dégradés et styles de
//  texte de Zuno TV. AUCUNE couleur en dur dans les écrans : tout passe
//  par ici (règle n°5 d'AGENTS.md).
//
//  ADN visuel (25/09/2026) : le logo Zuno est une calligraphie OR brossé
//  sur noir. L'interface prolonge ce logo : noir profond, or champagne,
//  ivoire. Pourquoi ces choix, et pas d'autres :
//
//   • FOND NOIR PROFOND (#070708), jamais #000 pur. Sur OLED le noir absolu
//     crée du « banding » ; un noir à peine relevé donne de la profondeur et
//     laisse l'or « flotter ». Les surfaces s'empilent par paliers (+4/+6 de
//     luminance) : la hiérarchie naît de l'EMPILEMENT, pas des bordures
//     (plus calme à 3 m de distance).
//   • OR CHAMPAGNE (#C99A3A) = accent unique. C'est l'or MOYEN du logo (ni
//     le reflet blanc, ni l'ombre brune) : il porte TOUTE l'attention
//     (focus, CTA, sélection) ; le reste est neutre, donc l'œil sait
//     toujours où il est — crucial en navigation D-pad.
//   • OR VIF (#F2CF7A) pour le focus (anneau + lueur + texte accent) : c'est
//     le reflet du logo, plus lumineux que l'accent au repos, il « s'allume »
//     quand on arrive dessus.
//   • TEXTE SUR OR : SOMBRE (#14100A), jamais blanc. Blanc sur or champagne
//     ≈ 2.3:1 (illisible) ; noir chaud sur or ≈ 9:1.
//   • IVOIRE (#F0EDE9) pour le texte : un blanc légèrement chaud fatigue
//     moins qu'un blanc pur et s'accorde à l'or.
//   • CONTRASTES : ivoire/noir ≈ 17:1 ; muted/noir ≈ 6.8:1 ; or vif/noir
//     ≈ 13:1 ; or champagne/noir ≈ 8:1.
// =========================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TvTokens {
  TvTokens._();

  // ---- Couleurs — système de SURFACES en couches ----
  static const Color bg = Color(0xFF070708); // Surface 0 — noir profond
  static const Color panel = Color(0xFF0E0E11); // sidebar (proche du fond)
  static const Color card = Color(0xFF141418); // Surface 1 — carte au repos
  static const Color tile = Color(0xFF191920); // fond des vignettes de chaînes
  static const Color tileBorder = Color(0x0DFFFFFF); // bordure vignette (blanc 5 %)
  static const Color badgeBg = Color(0x1FC99A3A); // fond badge (or ~12 %)
  static const Color sel = Color(0xFF1E1E25); // Surface 2 — focus / élevé
  static const Color surface3 = Color(0xFF24242C); // overlay / menu déployé
  static const Color line = Color(0xFF2B2B34); // hairline / bordure subtile
  static const Color lineSoft = Color(0xFF202027); // bordures discrètes (repos)
  static const Color text = Color(0xFFF0EDE9); // texte principal (ivoire)
  static const Color muted = Color(0xFF9C9BA4); // texte secondaire
  static const Color mutedDim = Color(0xFF6C6B76); // texte tertiaire / hints
  static const Color accent = Color(0xFFC99A3A); // ACCENT (or champagne — l'or du logo)
  static const Color accentBright = Color(0xFFF2CF7A); // OR VIF focus (texte + lueur)
  static const Color accentDeep = Color(0xFF8C6420); // or sombre : dégradés
  static const Color onAccent = Color(0xFF14100A); // texte posé SUR un fond or (sombre !)
  static const Color live = Color(0xFFFF4D3D); // pastille EN DIRECT (rouge chaud)
  static const Color success = Color(0xFF4CC38A); // ✓ copié / actif

  // ---- Rayons ----
  static const double rCard = 18;
  static const double rButton = 14;
  static const double rMenuItem = 12;
  static const double rSmall = 10;

  // ---- Fond global : halo doré très sombre (haut-droite) sur noir.
  //  Donne une « scène » au lieu d'un aplat : l'œil perçoit une lumière
  //  lointaine, comme une salle de projection. Reste quasi noir (≤ 3 %
  //  d'or) pour ne jamais concurrencer les affiches et logos de chaînes. ----
  static const Gradient bgGradient = RadialGradient(
    center: Alignment(0.56, -0.40), // 78% / 30%
    radius: 1.3,
    colors: <Color>[Color(0xFF1A150C), bg],
    stops: <double>[0.0, 0.6],
  );

  // ---- Halo chaud discret derrière le branding (coin haut-gauche) ----
  // Profondeur « premium » : évite le noir plat sous le logo Zuno.
  static const Gradient brandGlow = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.1,
    colors: <Color>[Color(0x18C99A3A), Color(0x00000000)],
  );

  // ---- Filet d'accent or (haut de carte) ----
  static const Gradient accentHairline = LinearGradient(
    colors: <Color>[Color(0x00C99A3A), accent, Color(0x00C99A3A)],
  );

  // ---- CTA principal (dégradé or : vif en haut, champagne en bas) ----
  static const Gradient ctaGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[accentBright, accent],
  );

  // ---- Pastille prix ----
  static const Gradient pillGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0x12C99A3A), Color(0x00C99A3A)],
  );

  // =========================================================
  //  TYPOGRAPHIE — 3 rôles, jamais plus.
  //   • display = Oswald (titres d'accent : condensé, « métal » — contraste
  //               net avec la calligraphie du logo, qu'on ne copie PAS)
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
          {FontWeight weight = FontWeight.w600, Color color = accentBright, double spacing = 0}) =>
      GoogleFonts.jetBrainsMono(
          fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing);
}
