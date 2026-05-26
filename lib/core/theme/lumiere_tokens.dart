// =========================================================
//  lumiere_tokens.dart — Système de design "7 MOTION"
// =========================================================
//  Identité 7 MOTION : noir métallique + rouge braise.
//  Inspiré du logo — cinéma d'action, mouvement, intensité
//  retenue. Pas de Netflix-red criard, pas de néon : le rouge
//  est un rouge "ember" / "braise" qui rougeoie sans agresser.
//
//  Deux modes :
//    - Cinema Mode (dark, défaut) : surfaces charbon presque
//      noires (jamais le noir pur), accents ember-red.
//    - Daylight Mode (light) : version diurne dérivée, ivoires
//      chauds + ember deep pour rester lisible.
//
//  Source de vérité. Aucune valeur de couleur n'existe ailleurs
//  dans l'app.
//
//  Disponibilité :
//    - Composants context-aware (deux modes) →
//      `LumiereColors.of(context).X`
//    - Composants Cinema Mode permanent (splash, lecteur vidéo) →
//      `AppColors.X` (raccourci const)
// =========================================================

import 'package:flutter/material.dart';

/// Extension `ThemeData` qui transporte la palette 7 MOTION complète.
/// Le nom de classe reste `LumiereColors` pour conserver une API stable
/// entre les rebrandings successifs (l'app est encore jeune, l'identité
/// peut bouger ; les valeurs changent, l'API non).
@immutable
class LumiereColors extends ThemeExtension<LumiereColors> {
  const LumiereColors({
    required this.canvas,
    required this.voidSurface,
    required this.elevated,
    required this.glass,
    required this.overcast,
    required this.champagne,
    required this.champagneBright,
    required this.champagneDeep,
    required this.brassGlow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusError,
    required this.statusInfo,
    required this.border,
    required this.scrim,
    required this.canvasGradient,
    required this.heroScrim,
  });

  // -------- Surfaces --------
  /// Fond principal. Cinema : charbon presque noir avec une pointe
  /// de chaleur. Daylight : ivoire chaud.
  final Color canvas;

  /// Surface la plus profonde (splash, vidéo plein écran). Jamais
  /// le noir pur — on garde une trace de chaleur pour les OLED.
  final Color voidSurface;

  /// Surface élevée (cards, panels, sheets).
  final Color elevated;

  /// Glassmorphism — à combiner avec `BackdropFilter`.
  final Color glass;

  /// Overlay le plus haut (modals, snackbars, dialogs).
  final Color overcast;

  // -------- Accent ember (rouge braise) --------
  /// Le nom du token reste `champagne` pour compatibilité, mais
  /// la valeur est désormais ember-red 7 MOTION. Le rebranding
  /// n'a pas à se propager dans 427 références.
  final Color champagne;

  /// Variante claire — ember glow, états focus / hover / brillance.
  final Color champagneBright;

  /// Variante deep — ember-blood, bordures actives, états sélectionnés
  /// passifs et accent principal du Daylight Mode.
  final Color champagneDeep;

  /// Halo ember — utilisé pour les glows / ombres rouges sur les CTAs
  /// primaires et les éléments focus.
  final Color brassGlow;

  // -------- Texte --------
  final Color textPrimary;
  final Color textSecondary;

  /// Niveau intermédiaire — métadonnées discrètes.
  final Color textTertiary;

  /// Texte très estompé — hints, timestamps, états désactivés.
  final Color textMuted;

  // -------- Statuts sémantiques --------
  /// Vert apaisé (jamais néon).
  final Color statusSuccess;

  /// Ambre / orange — buffering, avertissements doux.
  final Color statusWarning;

  /// Rouge ember (le même tone que l'accent ; volontairement distinct
  /// de `champagne` par une variation de saturation pour éviter
  /// l'ambiguïté visuelle accent/erreur).
  final Color statusError;

  /// Bleu cendre froid — info neutre.
  final Color statusInfo;

  // -------- Dérivés --------
  /// Liseré subtil pour cards / panels.
  final Color border;

  /// Voile sombre par-dessus une image.
  final Color scrim;

  /// Gradient de fond global, très subtil.
  final LinearGradient canvasGradient;

  /// Voile dégradé pour le bas des héros plein écran.
  final LinearGradient heroScrim;

  // ============================================================
  //  Cinema Mode (7 MOTION) — défaut, identité du produit
  // ============================================================
  static const LumiereColors cinema = LumiereColors(
    canvas: Color(0xFF0A0A0C),
    voidSurface: Color(0xFF050507),
    elevated: Color(0xFF14141A),
    glass: Color(0xFF1C1C24),
    overcast: Color(0xFF28282F),
    // Ember-red — saturé mais profond, pas Netflix-red ni néon
    champagne: Color(0xFFD63A30),
    champagneBright: Color(0xFFFF5A4A),
    champagneDeep: Color(0xFF8E1F1D),
    brassGlow: Color(0xFFFF5A4A),
    textPrimary: Color(0xFFF0EDE9),
    textSecondary: Color(0xFFB6B0A8),
    textTertiary: Color(0xFF7E7872),
    textMuted: Color(0xFF4E4A45),
    statusSuccess: Color(0xFF5FA975),
    statusWarning: Color(0xFFD69847),
    // Erreur = ember-glow (légèrement plus orangé que l'accent pour
    // se distinguer en contexte d'alerte critique).
    statusError: Color(0xFFE84A3E),
    statusInfo: Color(0xFF6A8DB0),
    border: Color(0x14F0EDE9), // textPrimary @ 8%
    scrim: Color(0xCC050507),
    canvasGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0xFF101012),
        Color(0xFF0A0A0C),
        Color(0xFF050507),
      ],
    ),
    heroScrim: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0x00050507),
        Color(0x80050507),
        Color(0xFF050507),
      ],
      stops: <double>[0.0, 0.55, 1.0],
    ),
  );

  // ============================================================
  //  Daylight Mode — version claire dérivée
  // ============================================================
  //  Ivoires chauds, ember deep pour passer le contraste AA, texte
  //  espresso (jamais noir pur). On évite tout blanc clinique.
  static const LumiereColors daylight = LumiereColors(
    canvas: Color(0xFFF5F2EC),
    voidSurface: Color(0xFFFAF8F3),
    elevated: Color(0xFFE9E5DC),
    glass: Color(0xFFD9D4C8),
    overcast: Color(0xFFCAC4B5),
    champagne: Color(0xFF9B2421),
    champagneBright: Color(0xFFC8302E),
    champagneDeep: Color(0xFF6E1714),
    brassGlow: Color(0xFFC8302E),
    textPrimary: Color(0xFF1A0F0E),
    textSecondary: Color(0xFF423835),
    textTertiary: Color(0xFF6E635E),
    textMuted: Color(0xFF9C9388),
    statusSuccess: Color(0xFF3E7553),
    statusWarning: Color(0xFFA77433),
    statusError: Color(0xFFB02E2A),
    statusInfo: Color(0xFF466389),
    border: Color(0x141A0F0E), // textPrimary @ 8%
    scrim: Color(0xCCFAF8F3),
    canvasGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0xFFFAF8F3),
        Color(0xFFF5F2EC),
        Color(0xFFEDE9DF),
      ],
    ),
    heroScrim: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0x00F5F2EC),
        Color(0x80F5F2EC),
        Color(0xFFF5F2EC),
      ],
      stops: <double>[0.0, 0.55, 1.0],
    ),
  );

  /// Helper pratique. Tombe sur Cinema Mode si l'extension n'est pas
  /// attachée (sécurité).
  static LumiereColors of(BuildContext context) {
    return Theme.of(context).extension<LumiereColors>() ?? cinema;
  }

  @override
  LumiereColors copyWith({
    Color? canvas,
    Color? voidSurface,
    Color? elevated,
    Color? glass,
    Color? overcast,
    Color? champagne,
    Color? champagneBright,
    Color? champagneDeep,
    Color? brassGlow,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textMuted,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusError,
    Color? statusInfo,
    Color? border,
    Color? scrim,
    LinearGradient? canvasGradient,
    LinearGradient? heroScrim,
  }) {
    return LumiereColors(
      canvas: canvas ?? this.canvas,
      voidSurface: voidSurface ?? this.voidSurface,
      elevated: elevated ?? this.elevated,
      glass: glass ?? this.glass,
      overcast: overcast ?? this.overcast,
      champagne: champagne ?? this.champagne,
      champagneBright: champagneBright ?? this.champagneBright,
      champagneDeep: champagneDeep ?? this.champagneDeep,
      brassGlow: brassGlow ?? this.brassGlow,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textMuted: textMuted ?? this.textMuted,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusWarning: statusWarning ?? this.statusWarning,
      statusError: statusError ?? this.statusError,
      statusInfo: statusInfo ?? this.statusInfo,
      border: border ?? this.border,
      scrim: scrim ?? this.scrim,
      canvasGradient: canvasGradient ?? this.canvasGradient,
      heroScrim: heroScrim ?? this.heroScrim,
    );
  }

  @override
  LumiereColors lerp(ThemeExtension<LumiereColors>? other, double t) {
    if (other is! LumiereColors) return this;
    return LumiereColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      voidSurface: Color.lerp(voidSurface, other.voidSurface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      overcast: Color.lerp(overcast, other.overcast, t)!,
      champagne: Color.lerp(champagne, other.champagne, t)!,
      champagneBright:
          Color.lerp(champagneBright, other.champagneBright, t)!,
      champagneDeep: Color.lerp(champagneDeep, other.champagneDeep, t)!,
      brassGlow: Color.lerp(brassGlow, other.brassGlow, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      border: Color.lerp(border, other.border, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      canvasGradient:
          LinearGradient.lerp(canvasGradient, other.canvasGradient, t)!,
      heroScrim: LinearGradient.lerp(heroScrim, other.heroScrim, t)!,
    );
  }
}
