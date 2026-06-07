// =========================================================
//  tv_palette.dart — Palette "VIOLET ROYAL" (version Télévision)
// =========================================================
//  POURQUOI une palette dédiée à la TV ?
//  ----------------------------------------------------------
//  L'app téléphone garde son identité historique BLACK7 ROYAL
//  (charbon + rouge braise, cf. `lumiere_tokens.dart`). La version
//  Télévision (Android TV / Fire TV / Google TV) adopte, elle, une
//  identité « VIOLET ROYAL » : un violet profond inspiré des grandes
//  apps de streaming TV (type Vu Player Pro), MAIS calibré sur des
//  études d'ergonomie visuelle, pas « au feeling ».
//
//  CE QUE DISENT LES ÉTUDES (sources réelles, voir plus bas) :
//   1. JAMAIS de noir pur (#000000) en fond ni de blanc pur (#FFFFFF)
//      en texte : le contraste maximal (21:1) crée un effet de HALO
//      (« halation ») qui fatigue l'œil, surtout dans le noir et pour
//      les ~40 % de personnes astigmates. → On part d'un gris très
//      foncé teinté violet, et d'un blanc cassé.
//      (Material Design — Dark theme ; UX Movement)
//   2. Le ROUGE saturé est le plus fatigant sur grand écran et les TV
//      le rendent « criard » avec des bandes (banding). Google
//      déconseille explicitement les rouges saturés sur Android TV.
//   3. Le BLEU est calme mais froid (lumière bleue le soir = mauvais
//      pour les yeux/sommeil) et devenu banal (Disney+, Prime, Max…).
//   4. Le VIOLET est le juste milieu : il ATTIRE l'œil et fait
//      « premium » sans l'agressivité du rouge ni la froideur du bleu.
//   5. L'accent ne doit servir QU'au focus/sélection et au bouton
//      Play (jamais en grand aplat), désaturé à ~70 % (jamais néon)
//      pour ne pas « vibrer » sur les TV en mode vif.
//
//  SOURCES :
//   - Material Design — Dark theme : https://m2.material.io/design/color/dark-theme.html
//   - Android TV — Focus & Layouts : https://developer.android.com/design/ui/tv/guides/styles/focus-system
//   - UX Movement — pure black / saturated bg :
//       https://uxmovement.com/content/why-you-should-never-use-pure-black-for-text-or-backgrounds/
//   - WCAG 1.4.3 (contraste) : https://www.w3.org/TR/UNDERSTANDING-WCAG20/visual-audio-contrast-contrast.html
//
//  RÈGLE PROJET #5 : aucune couleur en dur ailleurs que dans les
//  fichiers de tokens. Les écrans TV lisent ces constantes, jamais
//  un `Color(0xFF...)` inline.
// =========================================================

import 'package:flutter/material.dart';

/// Tokens de couleur de la version Télévision (mode « cinéma » permanent
/// — la TV n'a pas de Daylight Mode, on regarde toujours dans la pénombre).
///
/// Classe `abstract final` (mêmes garanties que `AppColors`) : que des
/// constantes statiques, jamais d'instance.
abstract final class TvRoyal {
  // -------------------------------------------------------
  //  FONDS / SURFACES — gris très foncé teinté violet
  // -------------------------------------------------------
  //  Échelle d'élévation : plus une surface est « haute » (proche de
  //  l'utilisateur), plus elle s'éclaircit légèrement. C'est ce qui
  //  donne la profondeur en dark theme (Material) — on ne met pas
  //  d'ombre noire sur du presque-noir, on monte la luminosité.

  /// Niveau 0 — fond principal. Presque-noir à sous-ton violet.
  /// (#14121A) Évite la halation du noir pur tout en restant sous le
  /// seuil « trop lumineux dans une pièce sombre ».
  static const Color background = Color(0xFF14121A);

  /// Surface la plus profonde (splash, lecteur plein écran).
  static const Color voidSurface = Color(0xFF0F0D15);

  /// Niveau 1 — surface élevée (cartes, panneaux, feuilles).
  static const Color surface = Color(0xFF1E1B26);

  /// Niveau 2 — survol / rangée active / en-têtes de feuille.
  static const Color surfaceHigh = Color(0xFF272234);

  /// Niveau 3 — overlay le plus haut (menus, dialogues).
  static const Color surfaceOverlay = Color(0xFF322B42);

  /// Liseré fin entre surfaces (faible contraste, ne « découpe » pas).
  static const Color divider = Color(0xFF2E2A38);

  /// Liseré subtil pour cartes au repos (texte @ ~10 %).
  static Color get border => textPrimary.withValues(alpha: 0.10);

  // -------------------------------------------------------
  //  ACCENT VIOLET — réservé focus / sélection / bouton Play
  // -------------------------------------------------------

  /// Accent principal — violet lumineux à ~70 % de saturation
  /// (PAS néon). C'est LA couleur qui « attire l'œil » : focus du
  /// D-pad, bouton Regarder, élément sélectionné. Jamais en grand fond.
  static const Color accent = Color(0xFF9B6DFF);

  /// Variante claire — halo / glow autour de l'élément focus, hovers.
  static const Color accentGlow = Color(0xFFB794FF);

  /// Variante profonde — états pressés, dégradés de CTA, bordures actives.
  static const Color accentDeep = Color(0xFF6D4BD0);

  /// Voile d'accent — fond très léger d'un chip / état sélectionné passif.
  static Color get accentSurface => accent.withValues(alpha: 0.16);

  // -------------------------------------------------------
  //  ACCENT SECONDAIRE — teal doux (complément froid désaturé)
  // -------------------------------------------------------
  //  Pour ce qui doit se distinguer du violet sans rivaliser avec lui :
  //  barres de progression, badges « NOUVEAU », pastilles d'info.
  //  Désaturé pour ne pas « vibrer » à côté du violet.

  static const Color secondary = Color(0xFF5BC8C0);
  static Color get secondarySurface => secondary.withValues(alpha: 0.14);

  // -------------------------------------------------------
  //  TEXTE — blanc cassé (jamais blanc pur)
  // -------------------------------------------------------
  //  On encode directement les niveaux d'emphase en HEX (plutôt qu'en
  //  opacité runtime) pour qu'ils soient explicites et testables, comme
  //  le recommande Material (87 % / 60 % / 38 %).

  /// Emphase forte — titres, noms de chaînes. ~13:1 sur le fond :
  /// confortable, bien au-dessus de WCAG AAA, sans le 21:1 fatigant.
  static const Color textPrimary = Color(0xFFECE8F2);

  /// Emphase moyenne — sous-titres, métadonnées, descriptions.
  static const Color textSecondary = Color(0xFFA39FB0);

  /// Emphase faible — hints, horodatages discrets.
  static const Color textTertiary = Color(0xFF807B8C);

  /// Désactivé — états grisés (≈ 38 %).
  static const Color textMuted = Color(0xFF6E6A78);

  // -------------------------------------------------------
  //  STATUTS SÉMANTIQUES
  // -------------------------------------------------------

  /// Confirmations / OK — vert apaisé, jamais néon.
  static const Color success = Color(0xFF5FB98C);

  /// Attentions douces / buffering — ambre chaud.
  static const Color warning = Color(0xFFE0A24A);

  /// Badge LIVE / erreur critique — rose-rouge légèrement désaturé qui
  /// s'accorde au violet (et reste lisible sans le « criard » du rouge
  /// pur déconseillé par Google sur TV).
  static const Color live = Color(0xFFFF4D6D);

  // -------------------------------------------------------
  //  DÉGRADÉS RÉUTILISÉS
  // -------------------------------------------------------

  /// Dégradé de fond global — voile violet très sombre, du haut (un
  /// soupçon plus clair) vers le bas (plus profond). Reste DARK pour
  /// respecter la consigne « pas trop lumineux dans le noir ».
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF1B1626),
      Color(0xFF14121A),
      Color(0xFF0F0D15),
    ],
  );

  /// Dégradé d'accent — pour les CTA primaires (Play) et badges premium.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[accentGlow, accentDeep],
  );

  /// Voile de lecture en bas d'une affiche / vignette (pour poser le
  /// titre par-dessus l'image sans perdre en lisibilité).
  static const LinearGradient cardScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0x000F0D15),
      Color(0x000F0D15),
      Color(0xE60F0D15),
    ],
    stops: <double>[0.0, 0.42, 1.0],
  );

  /// Voile dégradé pour le bas d'un hero plein écran.
  static const LinearGradient heroScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0x0014121A),
      Color(0x9914121A),
      Color(0xFF14121A),
    ],
    stops: <double>[0.0, 0.55, 1.0],
  );

  // -------------------------------------------------------
  //  HALO / OMBRES DE FOCUS
  // -------------------------------------------------------
  //  Sur TV, le FOCUS est l'état n°1 (navigation D-pad). Google
  //  recommande de COMBINER agrandissement (scale) + halo (glow) +
  //  bordure pour un focus repérable du canapé. Voici le halo violet.

  /// Halo violet diffus — autour de l'élément qui a le focus, ou d'un
  /// CTA primaire. `intensity` permet de monter le glow pour les gros
  /// éléments (hero) ou de le calmer pour les petites cartes.
  static List<BoxShadow> focusGlow({double intensity = 1.0}) => <BoxShadow>[
        BoxShadow(
          color: accentGlow.withValues(alpha: 0.38 * intensity),
          blurRadius: 28 * intensity,
          spreadRadius: 1 * intensity,
        ),
      ];
}
