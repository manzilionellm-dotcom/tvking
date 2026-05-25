// =========================================================
//  lumiere_tokens.dart — Système de design "LUMIÈRE / Maison Noir"
// =========================================================
//  Source de vérité unique pour les couleurs et l'accent
//  cinématographique. Deux modes :
//
//    - Cinema Mode (dark, défaut) : "club privé caché", chaud,
//      immersif, doux pour les yeux. Maison Noir.
//    - Daylight Mode : version claire dérivée pour usage diurne.
//      Mêmes intentions (champagne, calme, premium) inversées.
//
//  Règle absolue : aucune valeur de couleur ne doit exister
//  ailleurs dans l'app. Tout passe par `LumiereColors` ou par
//  son facade statique `AppColors` (qui réplique le Cinema Mode
//  pour rétrocompatibilité).
//
//  Disponibilité dans les widgets :
//    - via `Theme.of(context).extension<LumiereColors>()!` pour
//      les composants qui doivent s'adapter aux deux modes
//    - via `AppColors.X` (constants) pour les composants qui
//      restent en Cinema Mode permanent (mini-player, splash...)
// =========================================================

import 'package:flutter/material.dart';

/// Extension `ThemeData` qui transporte la palette LUMIÈRE complète.
/// Les composants context-aware lisent ces tokens via
/// `Theme.of(context).extension<LumiereColors>()!`.
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
  /// Fond principal de l'app. En Cinema : aubergine très foncée.
  /// En Daylight : ivoire chaud.
  final Color canvas;

  /// Surface "vide" (splash, vidéo en plein écran). Plus profond
  /// que le canvas. En Cinema c'est le noir le plus sombre qu'on
  /// s'autorise — toujours teinté pour éviter le noir pur.
  final Color voidSurface;

  /// Surface élevée (cards, panels, sheets).
  final Color elevated;

  /// Glassmorphism — un peu plus claire que `elevated`, semi-translucide
  /// quand combinée avec `BackdropFilter`.
  final Color glass;

  /// Overlay le plus haut (modals, snackbars, dialogs).
  final Color overcast;

  // -------- Accent champagne --------
  /// Accent principal — chaud, sobre, signe "privé / premium".
  final Color champagne;

  /// Variante claire — pour les états focus / hover / brillance.
  final Color champagneBright;

  /// Variante deep — pour les bordures actives, états sélectionnés
  /// passifs, et le Daylight Mode où il devient l'accent principal.
  final Color champagneDeep;

  /// Halo cuivré — utilisé pour les glows / ombres champagne sur
  /// les CTAs primaires et les éléments focus.
  final Color brassGlow;

  // -------- Texte --------
  final Color textPrimary;
  final Color textSecondary;

  /// Niveau intermédiaire — métadonnées, sous-titres discrets.
  final Color textTertiary;

  /// Texte très estompé — hints, timestamps, états désactivés.
  final Color textMuted;

  // -------- Statuts sémantiques --------
  /// Vert apaisé (jamais néon).
  final Color statusSuccess;

  /// Ambre champagne — buffering, avertissements doux.
  final Color statusWarning;

  /// Rouge bordeaux — erreurs critiques, badge LIVE. Volontairement
  /// pas le rouge Netflix #E50914 ni les rouges saturés tape-à-l'œil.
  final Color statusError;

  /// Bleu cendre froid — info neutre.
  final Color statusInfo;

  // -------- Dérivés --------
  /// Liseré subtil pour délimiter cards / panels sans agressivité.
  final Color border;

  /// Voile sombre par-dessus une image (cards, hero) pour rendre
  /// le texte par-dessus lisible.
  final Color scrim;

  /// Gradient de fond global, très subtil, donne la profondeur sans
  /// distraire du contenu.
  final LinearGradient canvasGradient;

  /// Voile dégradé pour le bas des héros plein écran.
  final LinearGradient heroScrim;

  // ============================================================
  //  Cinema Mode (Maison Noir) — défaut, identité du produit
  // ============================================================
  static const LumiereColors cinema = LumiereColors(
    canvas: Color(0xFF0E0B14),
    voidSurface: Color(0xFF0A0810),
    elevated: Color(0xFF16121C),
    glass: Color(0xFF1C1826),
    overcast: Color(0xFF221D2D),
    champagne: Color(0xFFD4B483),
    champagneBright: Color(0xFFE8C896),
    champagneDeep: Color(0xFF9C8359),
    brassGlow: Color(0xFFB8965E),
    textPrimary: Color(0xFFF4EDE4),
    textSecondary: Color(0xFFC8BFB2),
    textTertiary: Color(0xFF8A8278),
    textMuted: Color(0xFF5C564E),
    statusSuccess: Color(0xFF7FB890),
    statusWarning: Color(0xFFD4A574),
    statusError: Color(0xFFC97064),
    statusInfo: Color(0xFF8FA8C4),
    border: Color(0x14F4EDE4), // text.primary @ 8% — liseré subtil
    scrim: Color(0xCC0A0810),
    canvasGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0xFF14101D),
        Color(0xFF0E0B14),
        Color(0xFF09070D),
      ],
    ),
    heroScrim: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0x000A0810),
        Color(0x800A0810),
        Color(0xFF0A0810),
      ],
      stops: <double>[0.0, 0.55, 1.0],
    ),
  );

  // ============================================================
  //  Daylight Mode — version claire dérivée, mêmes intentions
  // ============================================================
  //  Les couleurs sont dérivées pour préserver l'identité Maison
  //  Noir : ivoires chauds, champagne plus profond pour passer la
  //  contraste AA sur fond clair, textes en espresso (jamais noir
  //  pur). Aucun blanc clinique, aucun gris froid.
  static const LumiereColors daylight = LumiereColors(
    canvas: Color(0xFFF6F1E8),
    voidSurface: Color(0xFFFAF7F1),
    elevated: Color(0xFFECE4D3),
    glass: Color(0xFFDDD3BE),
    overcast: Color(0xFFCFC4AC),
    champagne: Color(0xFF8A7142),
    champagneBright: Color(0xFF9C8359),
    champagneDeep: Color(0xFF6E5933),
    brassGlow: Color(0xFF76603C),
    textPrimary: Color(0xFF1A1612),
    textSecondary: Color(0xFF4A4138),
    textTertiary: Color(0xFF7A6F61),
    textMuted: Color(0xFFA89C87),
    statusSuccess: Color(0xFF4E8261),
    statusWarning: Color(0xFFB07F3E),
    statusError: Color(0xFFA14538),
    statusInfo: Color(0xFF466389),
    border: Color(0x141A1612), // text.primary @ 8%
    scrim: Color(0xCCFAF7F1),
    canvasGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0xFFFAF7F1),
        Color(0xFFF6F1E8),
        Color(0xFFEDE5D5),
      ],
    ),
    heroScrim: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color(0x00F6F1E8),
        Color(0x80F6F1E8),
        Color(0xFFF6F1E8),
      ],
      stops: <double>[0.0, 0.55, 1.0],
    ),
  );

  /// Helper pratique pour accéder à la palette depuis un widget.
  /// Tombe sur Cinema Mode si l'extension n'est pas attachée (sécurité).
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
