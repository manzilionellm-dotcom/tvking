// =========================================================
//  brand_logo.dart — Logo officiel The Few
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
    this.glowColor,
  });

  /// Variante compacte 28 dp pour les barres du haut.
  const BrandLogo.compact({super.key})
      : size = BrandLogoSize.compact,
        glowColor = null;

  /// Variante moyenne 84 dp pour À propos / onboarding.
  const BrandLogo.medium({super.key})
      : size = BrandLogoSize.medium,
        glowColor = null;

  /// Variante splash 120 dp.
  const BrandLogo.splash({super.key})
      : size = BrandLogoSize.splash,
        glowColor = null;

  /// Variante hero 160 dp — pour le splash Télévision (lisible à 3 m).
  /// `glowColor` permet de teinter le halo (ex. violet sur la version
  /// TV) au lieu du halo ember par défaut.
  const BrandLogo.hero({super.key, this.glowColor})
      : size = BrandLogoSize.hero;

  final BrandLogoSize size;

  /// Couleur du halo lumineux autour du logo. `null` = halo ember par
  /// défaut (identité téléphone). Fournir une couleur pour l'adapter à
  /// une autre palette (ex. `TvRoyal.accentGlow` sur la TV).
  final Color? glowColor;

  /// Asset PNG/JPG selon le flavor courant. Le logo Red Room (R rouge
  /// stylise sur velours noir, livre par l'utilisateur) remplace
  /// 1:1 le logo The Few partout dans l'app quand le binaire est
  /// celui de Red Room.
  static String get _assetPath {
    switch (FlavorConfig.current.flavor) {
      case Flavor.sevenMotion:
        return 'assets/branding/logo_black7royal.png';
      case Flavor.prive:
        return 'assets/branding/prive_icon.png';
    }
  }

  /// Lettre de repli affichee si l'asset image ne charge pas (rare,
  /// mais on prefere une lettre qu'un widget casse).
  static String get _fallbackLetter {
    switch (FlavorConfig.current.flavor) {
      case Flavor.sevenMotion:
        return '7';
      case Flavor.prive:
        return 'P';
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
      case BrandLogoSize.hero:
        return 160;
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
      case BrandLogoSize.hero:
        return 30;
    }
  }

  /// Halo autour du logo. Les grandes tailles (medium/splash/hero)
  /// rayonnent ; les petites (compact) restent plates. Si `glowColor`
  /// est fourni, on teinte le halo avec cette couleur (ex. violet TV),
  /// sinon on garde le halo ember de l'identité téléphone.
  List<BoxShadow>? _resolveGlow() {
    final bool wantsGlow = size == BrandLogoSize.medium ||
        size == BrandLogoSize.splash ||
        size == BrandLogoSize.hero;
    if (!wantsGlow) return null;
    if (glowColor != null) {
      return <BoxShadow>[
        BoxShadow(
          color: glowColor!.withValues(alpha: 0.45),
          blurRadius: 40,
          spreadRadius: 2,
        ),
      ];
    }
    return AppColors.emberGlowShadow;
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
        boxShadow: _resolveGlow(),
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

enum BrandLogoSize { compact, medium, splash, hero }

/// Constantes de chaîne pour les wordmarks The Few.
abstract final class BrandStrings {
  /// Nom court — utilisé partout dans l'app.
  static const String appName = 'The Few';

  /// Nom long — utilisé dans le titre de la fenêtre / des stores.
  static const String longName = 'The Few — Premium IPTV';

  /// Tagline courte pour les hero / onboarding.
  static const String tagline = 'Cinéma sans limites';
}
