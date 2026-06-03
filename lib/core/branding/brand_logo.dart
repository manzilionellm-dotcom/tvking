// =========================================================
//  brand_logo.dart — Logo officiel BLACK7 ROYAL
// =========================================================
//  Wrapper centralisé autour de l'asset PNG/JPG du logo. Permet
//  de changer la source (asset path) à un seul endroit le jour
//  où on aura une version SVG ou des variantes (sombre/claire).
//
//  Trois tailles standardisées :
//    - .compact (28 dp)   — pour les AppBars
//    - .medium  (84 dp)   — pour l'écran "À propos", onboarding
//    - .splash  (120 dp)  — pour le splash et les hero d'accueil
//
//  Le logo est conçu sur fond sombre (rouge braise sur noir).
//  En Daylight Mode on ajoute un fond noir derrière l'image pour
//  préserver la lisibilité du métal et de l'ember.
// =========================================================

import 'package:flutter/material.dart';

import '../flavor/flavor.dart';
import '../theme/app_colors.dart';
import '../theme/lumiere_tokens.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = BrandLogoSize.medium,
  });

  /// Variante compacte 28 dp pour les barres du haut.
  const BrandLogo.compact({super.key}) : size = BrandLogoSize.compact;

  /// Variante moyenne 84 dp pour À propos / onboarding.
  const BrandLogo.medium({super.key}) : size = BrandLogoSize.medium;

  /// Variante splash 120 dp.
  const BrandLogo.splash({super.key}) : size = BrandLogoSize.splash;

  final BrandLogoSize size;

  /// Asset PNG/JPG selon le flavor courant. Le logo Red Room (R rouge
  /// stylise sur velours noir, livre par l'utilisateur) remplace
  /// 1:1 le logo BLACK7 ROYAL partout dans l'app quand le binaire est
  /// celui de Red Room.
  static String get _assetPath {
    switch (FlavorConfig.current.flavor) {
      case Flavor.redRoom:
        return 'assets/branding/logo_redroom.png';
      case Flavor.sevenMotion:
        return 'assets/branding/logo_black7royal.png';
    }
  }

  /// Lettre de repli affichee si l'asset image ne charge pas (rare,
  /// mais on prefere une lettre qu'un widget casse).
  static String get _fallbackLetter {
    switch (FlavorConfig.current.flavor) {
      case Flavor.redRoom:
        return 'R';
      case Flavor.sevenMotion:
        return '7';
    }
  }

  double get _dp {
    switch (size) {
      case BrandLogoSize.compact:
        return 28;
      case BrandLogoSize.medium:
        return 84;
      case BrandLogoSize.splash:
        return 120;
    }
  }

  double get _radius {
    switch (size) {
      case BrandLogoSize.compact:
        return 6;
      case BrandLogoSize.medium:
        return 18;
      case BrandLogoSize.splash:
        return 22;
    }
  }

  @override
  Widget build(BuildContext context) {
    final LumiereColors palette = LumiereColors.of(context);
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      width: _dp,
      height: _dp,
      decoration: BoxDecoration(
        // Le logo est conçu sur fond noir — on conserve un fond noir
        // même en Daylight pour préserver le métal et l'ember.
        color: AppColors.voidSurface,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: size == BrandLogoSize.splash || size == BrandLogoSize.medium
            ? AppColors.emberGlowShadow
            : null,
        border: isLight
            ? Border.all(color: palette.border, width: 0.8)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        _assetPath,
        fit: BoxFit.cover,
        // En cas d'erreur de chargement (asset manquant), on dégrade
        // sur un placeholder texte plutôt que de crasher.
        errorBuilder: (BuildContext _, Object __, StackTrace? ___) {
          return Center(
            child: Text(
              _fallbackLetter,
              style: TextStyle(
                color: AppColors.accent,
                fontSize: _dp * 0.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        },
      ),
    );
  }
}

enum BrandLogoSize { compact, medium, splash }

/// Constantes de chaîne pour les wordmarks BLACK7 ROYAL.
abstract final class BrandStrings {
  /// Nom court — utilisé partout dans l'app.
  static const String appName = 'BLACK7 ROYAL';

  /// Nom long — utilisé dans le titre de la fenêtre / des stores.
  static const String longName = 'BLACK7 ROYAL — Premium IPTV';

  /// Tagline courte pour les hero / onboarding.
  static const String tagline = 'Cinéma sans limites';
}
