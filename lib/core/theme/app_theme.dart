// =========================================================
//  app_theme.dart — Le ThemeData global de l'app
// =========================================================
//  C'est ici qu'on assemble couleurs + typographie en un
//  ThemeData que MaterialApp consomme via `theme:`.
//  Tous les widgets Material (Scaffold, Button, AppBar...)
//  prendront automatiquement ces réglages.
// =========================================================

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

abstract final class AppTheme {
  static ThemeData get dark {
    // ColorScheme = ensemble cohérent de couleurs Material 3.
    // On le construit "from seed" pour générer automatiquement
    // les variantes (container, onSurface...) à partir d'un accent.
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accentPink,
      brightness: Brightness.dark,
      surface: AppColors.surface,
      primary: AppColors.accentPink,
      secondary: AppColors.accentCyan,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,

      // AppBar transparente : on veut voir le gradient derrière.
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),

      // Style des cartes par défaut (on les surcharge souvent
      // pour notre effet glassmorphism, mais ça sert de fallback).
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // Textes — on relie nos AppTextStyles au TextTheme Material.
      textTheme: TextTheme(
        displayLarge: AppTextStyles.displayLarge,
        headlineLarge: AppTextStyles.headlineLarge,
        headlineMedium: AppTextStyles.headlineMedium,
        bodyLarge: AppTextStyles.bodyLarge,
        bodyMedium: AppTextStyles.bodyMedium,
        labelSmall: AppTextStyles.labelSmall,
      ),

      // Animation des transitions de page : on garde du sobre.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
