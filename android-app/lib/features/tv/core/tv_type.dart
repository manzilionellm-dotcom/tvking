// =========================================================
//  tv_type.dart — Échelle de texte Zuno TV
// =========================================================
//  Ce module ne choisit AUCUNE couleur. L'appelant passe la couleur
//  des jetons (TvTokens / TvAppTokens), pour que le thème confort des
//  yeux reste le seul propriétaire de la palette.
//
//  Sources, reprises telles quelles :
//
//  • Android TV, Typography
//    https://developer.android.com/design/ui/tv/guides/styles/typography
//    Roboto est la police par défaut de la plateforme. Pour une interface
//    de marque, le guide demande une police lisible (grands contrepoinçons,
//    chasse lisible d'un coup d'œil), un sans-serif pour le corps et les
//    libellés, et pas de police décorative dans les textes longs.
//    Les rôles sont display, headline, title, body, label.
//
//  • Fire TV, 10-foot UI
//    https://developer.amazon.com/docs/fire-tv/design-and-user-experience-guidelines.html
//    Le corps fait au moins 14 sp. L'interligne est plus ouvert que sur
//    un téléphone. On évite les graisses fines et les chasses très étroites.
//    Le texte sur une image repose sur un dégradé sombre.
//
//  • Netflix, mesures publiques de la page (20 septembre 2026)
//    https://font-inspector.com/fonts-used-by/netflix
//    Une seule grotesque. Graisses 400, 500 et 700. Interlettrage normal.
//    Titre 700 avec interligne 1,25. Bouton et sous-titre en 500.
//    Netflix Sans est une police propriétaire : elle n'est pas embarquée.
//
//  • Material 3, jetons d'échelle
//    https://m3.material.io/styles/typography/type-scale-tokens
//    Interligne du title-large : 28/22. Corps large : 24/16.
//    Interlettrage des libellés : 0,1 px (label large) et 0,5 px
//    (label medium / small). Le corps Material ajoute +0,5 px, calibre
//    pour Roboto : on ne le reprend pas, l'interlettrage Netflix est normal.
//
//  Police de lecture : Inter, SIL OFL 1.1, déjà dans les assets.
//  Les rôles TV ne demandent que les graisses 400, 500 et 700.
//  Les fichiers 600 et 800 restent pour la Maison (téléphone).
//  Oswald, condensé, n'est plus choisi pour les titres : sa chasse étroite
//  est celle que Fire TV déconseille à 3 m. Ses fichiers restent dans
//  l'inventaire hors ligne déjà vérifié, pour qu'aucun appel oublié
//  ne parte les télécharger.
//  JetBrains Mono reste réservé aux codes (activation, adresse MAC) :
//  seulement les graisses 400 et 600, les deux fichiers présents.
//  Les horloges utilisent les chiffres tabulaires d'Inter.
// =========================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tv_dimens.dart';

abstract final class TvType {
  /// Plancher Fire TV pour un texte lu à 3 m. Les rôles de l'échelle
  /// ne descendent pas en dessous. Un appel `ui(size)` explicite garde
  /// la taille demandée : les écrans qui étaient sous 14 sp sont relevés
  /// à l'appel, pas par surprise dans chaque bouton.
  static const double minReading = 14;

  /// Trois graisses, celles mesurées chez Netflix : 400, 500, 700.
  /// 600 rejoint 500 (sous-titres et boutons). 800 rejoint 700 (titres).
  static FontWeight readingWeight(FontWeight requested) {
    final int value = requested.value;
    if (value <= 450) return FontWeight.w400;
    if (value < 650) return FontWeight.w500;
    return FontWeight.w700;
  }

  /// JetBrains Mono n'a, dans les assets, que Regular et SemiBold.
  static FontWeight codeWeight(FontWeight requested) =>
      requested.value <= 500 ? FontWeight.w400 : FontWeight.w600;

  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = 0,
  }) =>
      _inter(
        size: size,
        weight: weight,
        color: color,
        letterSpacing: letterSpacing,
        // 1,25 : interligne mesuré sur les titres Netflix.
        height: 1.25,
      );

  static TextStyle ui(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0,
    double? height,
  }) =>
      _inter(
        size: size,
        weight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Paragraphe. 24/16 est l'interligne Material 3 du corps large,
  /// aussi l'interligne « plus ouvert » demandé par Fire TV.
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0,
  }) =>
      _inter(
        size: size < minReading ? minReading : size,
        weight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: 24 / 16,
      );

  static TextStyle figure(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) =>
      _inter(
        size: size < minReading ? minReading : size,
        weight: weight,
        color: color,
        height: 1,
        features: const <FontFeature>[
          FontFeature.tabularFigures(),
          FontFeature.liningFigures(),
        ],
      );

  static TextStyle code(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size < minReading ? minReading : size,
        fontWeight: codeWeight(weight),
        color: color,
        letterSpacing: letterSpacing,
        height: 1,
      );

  /// Échelle Material du thème TV. Les tailles sont celles de `TvDimens`
  /// (canevas 10-foot déjà en place), jamais les 11–12 sp du téléphone.
  static TextTheme material(Color color) {
    TextStyle title(double size) => ui(
          size,
          weight: FontWeight.w500,
          color: color,
          height: 28 / 22,
        );
    return TextTheme(
      displayLarge: display(TvDimens.displayL, color: color),
      displayMedium: display(TvDimens.displayM, color: color),
      displaySmall: display(TvDimens.displayS, color: color),
      headlineLarge: display(TvDimens.headline, color: color),
      headlineMedium: title(TvDimens.title),
      headlineSmall: title(TvDimens.titleS),
      titleLarge: title(TvDimens.title),
      titleMedium: ui(
        TvDimens.body,
        weight: FontWeight.w500,
        color: color,
        height: 24 / 16,
      ),
      titleSmall: ui(TvDimens.label, weight: FontWeight.w500, color: color),
      bodyLarge: body(TvDimens.body, color: color),
      bodyMedium: body(TvDimens.label, color: color),
      bodySmall: body(TvDimens.caption, color: color),
      // 0,1 et 0,5 : interlettrages Material 3 des label large / medium / small.
      labelLarge: ui(
        TvDimens.label,
        weight: FontWeight.w500,
        color: color,
        letterSpacing: 0.1,
        height: 20 / 14,
      ),
      labelMedium: ui(
        TvDimens.caption,
        weight: FontWeight.w500,
        color: color,
        letterSpacing: 0.5,
        height: 20 / 14,
      ),
      labelSmall: ui(
        TvDimens.caption,
        weight: FontWeight.w500,
        color: color,
        letterSpacing: 0.5,
        height: 20 / 14,
      ),
    );
  }

  static TextStyle _inter({
    required double size,
    required FontWeight weight,
    Color? color,
    double letterSpacing = 0,
    double? height,
    List<FontFeature>? features,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: readingWeight(weight),
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: features,
      );
}
