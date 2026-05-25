// =========================================================
//  app_theme.dart — Thèmes globaux Maison Noir
// =========================================================
//  Deux ThemeData, un pour chaque mode :
//
//    - `AppTheme.cinema`  → dark, Maison Noir, défaut, identité
//                           "club privé caché"
//    - `AppTheme.daylight` → light, version diurne dérivée
//
//  Le `MaterialApp` choisit entre les deux via `themeMode` qui
//  est piloté par `ThemeModeRepository`.
//
//  Spécificités cinématographiques attachées au thème :
//    - boutons "premium CTA" (champagne + halo cuivré)
//    - focus rings champagne pour la nav clavier / Android TV
//    - inputs sobres (pas de bordure agressive)
//    - radii généreux (16) pour les cards, plus serrés (10) pour
//      les inputs/boutons (sensation "objet" plutôt que "écran")
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'lumiere_tokens.dart';

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

  // ============================================================
  //  Constructeur partagé
  // ============================================================

  static ThemeData _buildTheme({
    required Brightness brightness,
    required LumiereColors palette,
    required Color primaryOnAccent,
  }) {
    final ColorScheme colorScheme = ColorScheme(
      brightness: brightness,
      primary: palette.champagne,
      onPrimary: primaryOnAccent,
      primaryContainer: palette.champagneDeep,
      onPrimaryContainer: palette.textPrimary,
      secondary: palette.brassGlow,
      onSecondary: primaryOnAccent,
      secondaryContainer: palette.glass,
      onSecondaryContainer: palette.textPrimary,
      tertiary: palette.statusInfo,
      onTertiary: primaryOnAccent,
      error: palette.statusError,
      onError: primaryOnAccent,
      surface: palette.elevated,
      onSurface: palette.textPrimary,
      surfaceContainerHighest: palette.overcast,
      surfaceContainerHigh: palette.glass,
      surfaceContainer: palette.elevated,
      surfaceContainerLow: palette.canvas,
      surfaceContainerLowest: palette.voidSurface,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.border,
      outlineVariant: palette.border,
      scrim: palette.scrim,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,

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
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      // ----- Cards : rayons généreux, pas d'élévation matérielle -----
      cardTheme: CardThemeData(
        color: palette.elevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.border),
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

      // ----- CTA primaire (champagne plein + halo cuivré) -----
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.champagne,
          foregroundColor: primaryOnAccent,
          disabledBackgroundColor: palette.glass,
          disabledForegroundColor: palette.textMuted,
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          // Focus / hover → champagne bright. Pressed → champagne deep.
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.pressed)) {
                return palette.champagneDeep.withValues(alpha: 0.25);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return palette.champagneBright.withValues(alpha: 0.16);
              }
              return null;
            },
          ),
          side: WidgetStateProperty.resolveWith<BorderSide?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(color: palette.champagneBright, width: 2);
              }
              return null;
            },
          ),
        ),
      ),

      // ----- CTA secondaire (bordure champagne, fond transparent) -----
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.champagne,
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(
            color: palette.champagne.withValues(alpha: 0.5),
            width: 1.2,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.pressed)) {
                return palette.champagne.withValues(alpha: 0.20);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return palette.champagne.withValues(alpha: 0.10);
              }
              return null;
            },
          ),
          side: WidgetStateProperty.resolveWith<BorderSide?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(color: palette.champagneBright, width: 2);
              }
              return BorderSide(
                color: palette.champagne.withValues(alpha: 0.5),
                width: 1.2,
              );
            },
          ),
        ),
      ),

      // ----- CTA tertiaire (lien texte) -----
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.champagne,
          textStyle: AppTextStyles.button,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.pressed)) {
                return palette.champagne.withValues(alpha: 0.15);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return palette.champagne.withValues(alpha: 0.08);
              }
              return null;
            },
          ),
        ),
      ),

      // ----- Inputs : sobres, fond glass, focus champagne -----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.glass,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: palette.textMuted,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.champagne, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.statusError, width: 1.4),
        ),
      ),

      // ----- Switch : track champagne quand actif -----
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) return primaryOnAccent;
            return palette.textSecondary;
          },
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) return palette.champagne;
            return palette.glass;
          },
        ),
        trackOutlineColor: WidgetStateProperty.all<Color>(palette.border),
      ),

      // ----- Slider : track champagne -----
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.champagne,
        inactiveTrackColor: palette.champagne.withValues(alpha: 0.18),
        thumbColor: palette.champagneBright,
        overlayColor: palette.champagne.withValues(alpha: 0.18),
      ),

      // ----- Snackbar : surface overcast + texte primaire -----
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.overcast,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: palette.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // ----- Dialog : surface elevated + radius généreux -----
      dialogTheme: DialogThemeData(
        backgroundColor: palette.elevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: AppTextStyles.headlineMedium.copyWith(
          color: palette.textPrimary,
        ),
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: palette.textSecondary,
        ),
      ),

      // ----- Bottom sheet -----
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.elevated,
        modalBackgroundColor: palette.canvas,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // ----- Focus theme global (Android TV / clavier) -----
      focusColor: palette.champagne.withValues(alpha: 0.18),
      hoverColor: palette.champagne.withValues(alpha: 0.10),
      splashColor: palette.champagne.withValues(alpha: 0.14),
      highlightColor: palette.champagne.withValues(alpha: 0.08),

      // ----- Divider sobre -----
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),

      // ----- Transitions de page : fade sobre (pas de slide brusque) -----
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
