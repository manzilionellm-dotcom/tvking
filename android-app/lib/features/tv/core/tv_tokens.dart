// =========================================================
//  tv_tokens.dart — Design System « Maison Noir » 7 MOTION (TV)
// =========================================================
//  Source de vérité UNIQUE des couleurs, rayons, dégradés et styles de
//  texte de 7 MOTION TV. AUCUNE couleur en dur dans les écrans : tout passe
//  par ici (règle n°5 d'AGENTS.md).
//
//  ADN visuel (24/09/2026) : le thème SOMBRE de la marque 7 MOTION —
//  charbon profond, braise rouge, ivoire. Il remplace l'ancien « or
//  champagne » hérité de The Few. Pourquoi ces choix, et pas d'autres :
//
//   • FOND CHARBON, jamais #000 pur. Sur OLED le noir absolu crée du
//     « banding » et un effet de trou ; un charbon légèrement bleuté
//     (#0A0A0C) donne de la profondeur et fait ressortir la braise. Les
//     surfaces s'empilent par paliers (+4/+6 de luminance) : la hiérarchie
//     naît de l'EMPILEMENT, pas des bordures (plus calme à 3 m de distance).
//   • BRAISE (#D63A30) = accent unique. C'est le rouge du « 7 » du logo :
//     l'interface prolonge l'identité au lieu de la contredire. Il porte
//     TOUTE l'attention (focus, CTA, sélection) ; le reste est neutre, donc
//     l'œil sait toujours où il est — crucial en navigation D-pad.
//   • BRAISE VIVE (#FF5A4E) pour le focus (anneau + lueur + texte accent) :
//     plus lumineuse que l'accent au repos, elle « s'allume » quand on
//     arrive dessus, sans passer par un rouge criard.
//   • IVOIRE (#F0EDE9) pour le texte : un blanc légèrement chaud fatigue
//     moins qu'un blanc pur et casse la froideur du charbon.
//   • CONTRASTES : ivoire/charbon ≈ 16:1 ; muted/charbon ≈ 6.5:1 ;
//     texte sur fond braise ≈ 4.4:1 — OK pour du texte large/gras (tout le
//     texte TV l'est, l'app est rendue à ≥ 1,5× pour un écran 1080p).
// =========================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TvTokens {
  TvTokens._();

  // ---- Couleurs — système de SURFACES en couches ----
  static const Color bg = Color(0xFF0A0A0C); // Surface 0 — charbon profond
  static const Color panel = Color(0xFF0E0E11); // sidebar (proche du fond)
  static const Color card = Color(0xFF141418); // Surface 1 — carte au repos
  static const Color tile = Color(0xFF191920); // fond des vignettes de chaînes
  static const Color tileBorder = Color(0x0DFFFFFF); // bordure vignette (blanc 5 %)
  static const Color badgeBg = Color(0x1FD63A30); // fond badge (braise ~12 %)
  static const Color sel = Color(0xFF1E1E25); // Surface 2 — focus / élevé
  static const Color surface3 = Color(0xFF24242C); // overlay / menu déployé
  static const Color line = Color(0xFF2B2B34); // hairline / bordure subtile
  static const Color lineSoft = Color(0xFF202027); // bordures discrètes (repos)
  static const Color text = Color(0xFFF0EDE9); // texte principal (ivoire)
  static const Color muted = Color(0xFF9C9BA4); // texte secondaire
  static const Color mutedDim = Color(0xFF6C6B76); // texte tertiaire / hints
  static const Color accent = Color(0xFFD63A30); // ACCENT (braise — le 7 du logo)
  static const Color accentBright = Color(0xFFFF5A4E); // BRAISE FOCUS (texte + lueur)
  static const Color accentDeep = Color(0xFF9E2A22); // braise sombre : dégradés
  static const Color onAccent = Color(0xFFFFF7F5); // texte posé SUR un fond braise
  static const Color live = Color(0xFFFF4D3D); // pastille EN DIRECT (rouge chaud)
  static const Color success = Color(0xFF4CC38A); // ✓ copié / actif

  // ---- Rayons ----
  static const double rCard = 18;
  static const double rButton = 14;
  static const double rMenuItem = 12;
  static const double rSmall = 10;

  // ---- Fond global : halo braise très sombre (haut-droite) sur charbon.
  //  Donne une « scène » au lieu d'un aplat : l'œil perçoit une lumière
  //  lointaine, comme une salle de projection. Reste quasi noir (≤ 3 % de
  //  rouge) pour ne jamais concurrencer les affiches et logos de chaînes. ----
  static const Gradient bgGradient = RadialGradient(
    center: Alignment(0.56, -0.40), // 78% / 30%
    radius: 1.3,
    colors: <Color>[Color(0xFF1A0F10), bg],
    stops: <double>[0.0, 0.6],
  );

  // ---- Halo chaud discret derrière le branding (coin haut-gauche) ----
  // Profondeur « premium » : évite le charbon plat sous le logo 7 MOTION.
  static const Gradient brandGlow = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.1,
    colors: <Color>[Color(0x18D63A30), Color(0x00000000)],
  );

  // ---- Filet d'accent braise (haut de carte) ----
  static const Gradient accentHairline = LinearGradient(
    colors: <Color>[Color(0x00D63A30), accent, Color(0x00D63A30)],
  );

  // ---- CTA principal (dégradé braise : vive en haut, brand en bas) ----
  static const Gradient ctaGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[accentBright, accent],
  );

  // ---- Pastille prix ----
  static const Gradient pillGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0x12D63A30), Color(0x00D63A30)],
  );

  // =========================================================
  //  TYPOGRAPHIE — 3 rôles, jamais plus.
  //   • display = Oswald (titres d'accent : condensé, « métal » comme le
  //               mot MOTION du logo)
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
