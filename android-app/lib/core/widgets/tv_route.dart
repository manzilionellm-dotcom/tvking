// =========================================================
//  tv_route.dart — Route enveloppée "identité TV violette"
// =========================================================
//  Les écrans secondaires (Recherche, Catégories, Guide, Réglages…)
//  sont PARTAGÉS entre le téléphone (rouge ember) et la TV (violet).
//  Quand on les pousse DEPUIS la TV, on veut qu'ils héritent de
//  l'identité violette — mais sans toucher au rendu téléphone.
//
//  Une route Flutter poussée se retrouve sur le Navigator racine :
//  elle n'est donc PAS descendante du `TvAccentScope` de l'accueil TV.
//  Résultat sans précaution : sur ces écrans, l'anneau de focus du
//  D-pad redevient rouge. `tvRoute()` corrige ça en ré-établissant,
//  pour CHAQUE écran poussé depuis la TV :
//    1. le `TvAccentScope` violet → tous les `TvFocusable` (focus
//       D-pad) deviennent violets ;
//    2. un `Theme` violet (`AppTheme.tvViolet`) → les composants
//       Material par défaut (interrupteurs, sliders, sélection de
//       texte, ripples…) passent aussi au violet.
//
//  Usage :
//  ```dart
//  Navigator.of(context).push<void>(tvRoute(const SearchScreen()));
//  ```
//
//  NB : les écrans qui peignent en `AppColors.*` STATIQUE (ember en
//  dur) ne sont pas affectés par le Theme — ils nécessitent une passe
//  ciblée par écran. `tvRoute` couvre le focus + le Material par défaut,
//  qui est l'essentiel du ressenti TV.
// =========================================================

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tv_palette.dart';
import 'tv_accent_scope.dart';

/// Construit une route Material dont le contenu est enveloppé dans
/// l'identité TV violette (scope de focus + thème).
MaterialPageRoute<T> tvRoute<T>(Widget child) {
  return MaterialPageRoute<T>(
    builder: (BuildContext context) {
      return TvAccentScope(
        focusBorderColor: TvRoyal.accent,
        focusGlow: TvRoyal.focusGlow(),
        child: Theme(
          data: AppTheme.tvViolet,
          child: child,
        ),
      );
    },
  );
}
