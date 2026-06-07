// =========================================================
//  tv_accent_scope.dart — Diffusion de l'accent de focus (TV)
// =========================================================
//  PROBLÈME D'ARCHITECTURE résolu ici
//  ----------------------------------------------------------
//  `TvFocusable` (le wrapper focus-aware utilisé PARTOUT, téléphone
//  ET TV) affiche par défaut un focus ROUGE EMBER (identité téléphone
//  BLACK7 ROYAL). Mais la version Télévision veut un focus VIOLET
//  (identité « VIOLET ROYAL », cf. `tv_palette.dart`).
//
//  On ne peut PAS changer la couleur en dur dans `TvFocusable` : ça
//  repeindrait aussi tout le téléphone. Et passer la couleur en
//  paramètre à chaque `TvFocusable` serait verbeux et oubliable.
//
//  SOLUTION : un `InheritedWidget` posé HAUT dans l'arbre de la version
//  TV. Tout `TvFocusable` descendant lit cette couleur via
//  `TvAccentScope.maybeOf(context)`. Pas de scope (téléphone) = focus
//  ember par défaut. Scope violet (TV) = focus violet automatique,
//  sans toucher un seul widget enfant. Une source de vérité, DRY.
// =========================================================

import 'package:flutter/material.dart';

/// Porte la couleur de focus (et son halo) à appliquer aux
/// `TvFocusable` descendants. Posé en racine du sous-arbre TV.
class TvAccentScope extends InheritedWidget {
  const TvAccentScope({
    required this.focusBorderColor,
    required this.focusGlow,
    required super.child,
    super.key,
  });

  /// Couleur de la bordure de focus (ex. `TvRoyal.accent`).
  final Color focusBorderColor;

  /// Halo (BoxShadow) affiché autour de l'élément focusé.
  final List<BoxShadow> focusGlow;

  /// Récupère le scope le plus proche, ou `null` si on n'est pas
  /// sous un `TvAccentScope` (cas téléphone → focus ember par défaut).
  static TvAccentScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TvAccentScope>();
  }

  @override
  bool updateShouldNotify(TvAccentScope oldWidget) {
    return focusBorderColor != oldWidget.focusBorderColor ||
        focusGlow != oldWidget.focusGlow;
  }
}
