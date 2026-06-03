// =========================================================
//  lumiere_tokens.dart — Système de design "BLACK7 ROYAL"
// =========================================================
//  Identité BLACK7 ROYAL : noir métallique + rouge braise.
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

/// Extension `ThemeData` qui transporte la palette BLACK7 ROYAL complète.
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
    required this.accentEmber,
    required this.emberGlow,
    required this.emberDeep,
    required this.emberHalo,
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
  /// Accent principal BLACK7 ROYAL : l'ember-red (#D63A30 en Cinema Mode).
  /// Nommé d'après sa valeur réelle (anciennement `champagne`, un nom
  /// hérité d'un rebranding antérieur qui ne reflétait plus la couleur).
  final Color accentEmber;

  /// Variante claire — ember glow, états focus / hover / brillance.
  final Color emberGlow;

  /// Variante deep — ember-blood, bordures actives, états sélectionnés
  /// passifs et accent principal du Daylight Mode.
  final Color emberDeep;

  /// Halo ember — utilisé pour les glows / ombres rouges sur les CTAs
  /// primaires et les éléments focus.
  final Color emberHalo;

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
  /// de `accentEmber` par une variation de saturation pour éviter
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
  //  Cinema Mode (BLACK7 ROYAL) — défaut, identité du produit
  // ============================================================
  static const LumiereColors cinema = LumiereColors(
    canvas: Color(0xFF0A0A0C),
    voidSurface: Color(0xFF050507),
    elevated: Color(0xFF14141A),
    glass: Color(0xFF1C1C24),
    overcast: Color(0xFF28282F),
    // Ember-red — saturé mais profond, pas Netflix-red ni néon
    accentEmber: Color(0xFFD63A30),
    emberGlow: Color(0xFFFF5A4A),
    emberDeep: Color(0xFF8E1F1D),
    emberHalo: Color(0xFFFF5A4A),
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
    accentEmber: Color(0xFF9B2421),
    emberGlow: Color(0xFFC8302E),
    emberDeep: Color(0xFF6E1714),
    emberHalo: Color(0xFFC8302E),
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
    Color? accentEmber,
    Color? emberGlow,
    Color? emberDeep,
    Color? emberHalo,
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
      accentEmber: accentEmber ?? this.accentEmber,
      emberGlow: emberGlow ?? this.emberGlow,
      emberDeep: emberDeep ?? this.emberDeep,
      emberHalo: emberHalo ?? this.emberHalo,
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
      accentEmber: Color.lerp(accentEmber, other.accentEmber, t)!,
      emberGlow:
          Color.lerp(emberGlow, other.emberGlow, t)!,
      emberDeep: Color.lerp(emberDeep, other.emberDeep, t)!,
      emberHalo: Color.lerp(emberHalo, other.emberHalo, t)!,
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
