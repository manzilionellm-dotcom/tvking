// =========================================================
//  app_theme.dart — Thèmes globaux Maison Noir (version safe)
// =========================================================
//  Deux ThemeData, un pour chaque mode :
//
//    - `AppTheme.cinema`  → dark, Maison Noir, défaut, identité
//                           "club privé caché"
//    - `AppTheme.daylight` → light, version diurne dérivée
//
//  IMPORTANT : cette version a été rétrogradée volontairement
//  aux APIs Flutter 3.16+ pour passer la CI. Les enrichissements
//  (filledButtonTheme custom, dialogTheme, focus rings via
//  WidgetStateProperty…) seront re-réintroduits par couches après
//  confirmation que la version Flutter du CI les supporte tous.
//
//  Le `MaterialApp` choisit entre les deux via `themeMode` qui
//  est piloté par `ThemeModeRepository`.
// =========================================================

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'lumiere_tokens.dart';
import 'tv_palette.dart';

abstract final class AppTheme {
  /// Cinema Mode (dark) — identité Maison Noir, défaut.
  static ThemeData get cinema => _buildTheme(
        brightness: Brightness.dark,
        palette: LumiereColors.cinema,
        primaryOnAccent: const Color(0xFF1A1612),
      );

  /// Daylight Mode (light) — version claire dérivée.
  static ThemeData get daylight => _buildTheme(
        brightness: Brightness.light,
        palette: LumiereColors.daylight,
        primaryOnAccent: const Color(0xFFFAF7F1),
      );

  /// Alias historique — l'ancien code consomme `AppTheme.dark`.
  static ThemeData get dark => cinema;

  /// Thème VIOLET ROYAL — réservé à la version Télévision. Dérivé des
  /// tokens `TvRoyal`, il sert à recoloriser les composants Material
  /// (interrupteurs, sliders, sélections…) quand on enveloppe un écran
  /// secondaire poussé depuis la TV (cf. `tvRoute`). On réutilise le
  /// même constructeur que l'ember : on lui passe juste une palette
  /// `LumiereColors` dont les "ember*" portent en réalité des violets.
  static ThemeData get tvViolet => _buildTheme(
        brightness: Brightness.dark,
        palette: _violetPalette,
        primaryOnAccent: TvRoyal.voidSurface,
      );

  /// Palette LumiereColors peuplée avec les valeurs violettes de TvRoyal.
  /// Les champs gardent leur nom historique ("accentEmber"…) mais
  /// transportent des violets — l'API reste stable, seules les valeurs
  /// changent (même principe que `LumiereColors.daylight`).
  static final LumiereColors _violetPalette = LumiereColors(
    canvas: TvRoyal.background,
    voidSurface: TvRoyal.voidSurface,
    elevated: TvRoyal.surface,
    glass: TvRoyal.surfaceHigh,
    overcast: TvRoyal.surfaceOverlay,
    accentEmber: TvRoyal.accent,
    emberGlow: TvRoyal.accentGlow,
    emberDeep: TvRoyal.accentDeep,
    emberHalo: TvRoyal.accentGlow,
    textPrimary: TvRoyal.textPrimary,
    textSecondary: TvRoyal.textSecondary,
    textTertiary: TvRoyal.textTertiary,
    textMuted: TvRoyal.textMuted,
    statusSuccess: TvRoyal.success,
    statusWarning: TvRoyal.warning,
    statusError: TvRoyal.live,
    statusInfo: TvRoyal.secondary,
    border: TvRoyal.border,
    scrim: const Color(0xCC0F0D15),
    canvasGradient: TvRoyal.backgroundGradient,
    heroScrim: TvRoyal.heroScrim,
  );

  // ============================================================
  //  Constructeur partagé — APIs Flutter 3.16+ uniquement
  // ============================================================

  static ThemeData _buildTheme({
    required Brightness brightness,
    required LumiereColors palette,
    required Color primaryOnAccent,
  }) {
    // ColorScheme.fromSeed est le constructeur sûr — il calcule
    // tous les containers Material 3 dérivés à partir d'un accent,
    // pas besoin de spécifier surfaceContainerHighest etc.
    // manuellement (paramètres qui sont arrivés à différentes
    // versions du SDK et qui auraient pu casser la compile).
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: palette.accentEmber,
      brightness: brightness,
      surface: palette.elevated,
      primary: palette.accentEmber,
      onPrimary: primaryOnAccent,
      secondary: palette.emberHalo,
      error: palette.statusError,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,

      // L'extension LumiereColors reste exposée — `Theme.of(context)
      // .extension<LumiereColors>()` continue de fonctionner pour
      // les composants context-aware.
      extensions: <ThemeExtension<LumiereColors>>[palette],

      // ----- AppBar : transparente pour révéler le gradient -----
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.headlineMedium.copyWith(
          color: palette.textPrimary,
        ),
      ),

      // ----- Cards : rayons généreux, pas d'élévation matérielle -----
      cardTheme: CardThemeData(
        color: palette.elevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),

      // ----- Texte global -----
      textTheme: TextTheme(
        displayLarge: AppTextStyles.displayLarge.copyWith(
          color: palette.textPrimary,
        ),
        headlineLarge: AppTextStyles.headlineLarge.copyWith(
          color: palette.textPrimary,
        ),
        headlineMedium: AppTextStyles.headlineMedium.copyWith(
          color: palette.textPrimary,
        ),
        bodyLarge: AppTextStyles.bodyLarge.copyWith(
          color: palette.textPrimary,
        ),
        bodyMedium: AppTextStyles.bodyMedium.copyWith(
          color: palette.textSecondary,
        ),
        labelSmall: AppTextStyles.labelSmall.copyWith(
          color: palette.textTertiary,
        ),
      ),

      iconTheme: IconThemeData(
        color: palette.textSecondary,
        size: 22,
      ),

      // ----- Focus / hover accentEmber — APIs stables -----
      focusColor: AppColors.accent.withValues(alpha: 0.18),
      hoverColor: AppColors.accent.withValues(alpha: 0.10),
      splashColor: AppColors.accent.withValues(alpha: 0.14),
      highlightColor: AppColors.accent.withValues(alpha: 0.08),

      // ----- Transitions de page : fade sobre -----
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
