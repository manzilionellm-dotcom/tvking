// =========================================================
//  tv_comfort.dart — Palette TV « confort » (soirée, pièce sombre)
// =========================================================
//  La box lit CETTE palette via `TvAppTokens`. `TvTokens` ne bouge pas :
//  les commandes Cast gardent l'ancien or sur noir (test historique).
//
//  On n'invente pas une marque. On applique des règles publiées aux
//  couleurs déjà décidées (ivoire, or champagne, halo, dégradé chaud) :
//
//  1. Fond gris foncé, pas noir pur. Material (« Dark theme ») :
//     le fond de base est #121212, un gris, parce que le noir pur
//     fatigue le texte clair.
//     https://m2.material.io/develop/android/theming/dark
//  2. L'élévation, en sombre, est un voile blanc dont l'alpha vient
//     de Material Components, `ElevationOverlayProvider` :
//     (4,5 × ln(1 + dp) + 2) / 100.
//     https://github.com/material-components/material-components-android/blob/master/lib/java/com/google/android/material/elevation/ElevationOverlayProvider.java
//  3. Le texte clair n'est pas blanc pur. Material pose le blanc à
//     87 % (emphase forte) et 60 % (emphase moyenne). Ici le « blanc »
//     est l'ivoire déjà choisi (`TvTokens.text`) : moins bleu, même
//     règle. Le 38 % « désactivé » n'est pas utilisé pour un texte
//     qu'on doit lire (WCAG 1.4.3 ne l'exempte que s'il est inactif).
//  4. Les couleurs saturées vibrent sur fond sombre (Material, dark
//     theme). Le rouge EN DIRECT historique ne passe pas 4,5:1 sur
//     les surfaces relevées : on garde sa teinte, on plafonne sa
//     saturation à celle de l'or déjà en place, puis on éclaircit
//     juste assez pour le contraste.
//  5. Android TV : thème sombre cinématographique, sRGB, contraste,
//     grands caractères, dégradés courts (éviter le banding), ne pas
//     compter sur la couleur seule.
//     https://developer.android.com/design/ui/tv/guides/styles/color-system
//     https://developer.android.com/design/ui/tv/guides/foundations/color-on-tv
//     https://developer.android.com/design/ui/tv/guides/styles/typography
//  6. WCAG 2.2 : 4,5:1 pour le texte (1.4.3), 7:1 visé pour le texte
//     principal (1.4.6), 3:1 pour un composant d'interface (1.4.11).
//     https://www.w3.org/TR/WCAG22/#contrast-minimum
//
//  Trois moments, même recette, pour pouvoir évoluer sans casser
//  les écrans :
//    - jour    : pile Material neutre (#121212 + voiles). Contraste
//                un peu plus haut si la pièce n'est pas noire.
//    - soir    : la même pile, teintée avec l'or du halo déjà dessiné
//                (`TvTokens.brandGlow`). C'est le défaut : on regarde
//                la télé le soir, dans le noir.
//    - nuit    : la base n'est plus #121212 mais la première couleur
//                du dégradé déjà écrit (plus chaude, encore foncée).
//                Les mêmes voiles d'élévation s'appliquent dessus.
//
//  L'IMAGE de la chaîne n'entre pas dans cette palette. Le lecteur
//  la pose sur un noir pur (`Colors.black`) pour ne pas teinter
//  les bandes ni les pixels.
//
//  Calcul une fois, puis lecture. Aucun flou, aucun filtre, aucune
//  animation : une box lente ne repeint que des aplats.
// =========================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tv_tokens.dart';

/// Moment de la palette. Le choix « auto » vit dans
/// `TvComfortSchedule` : ici on ne connaît qu'un moment déjà tranché.
enum TvComfortPeriod { day, evening, night }

/// Une pile de surfaces + encres, pour un moment donné.
@immutable
class TvComfortPalette {
  const TvComfortPalette({
    required this.bg,
    required this.panel,
    required this.card,
    required this.tile,
    required this.sel,
    required this.surface3,
    required this.line,
    required this.lineSoft,
    required this.text,
    required this.muted,
    required this.mutedDim,
    required this.live,
  });

  final Color bg;
  final Color panel;
  final Color card;
  final Color tile;
  final Color sel;
  final Color surface3;
  final Color line;
  final Color lineSoft;
  final Color text;
  final Color muted;
  final Color mutedDim;

  /// Rouge d'alerte / pastille EN DIRECT, lisible sur les surfaces.
  /// Un aplat de cette couleur porte le texte `TvAppTokens.onLive`,
  /// pas un blanc pur (le blanc ne tient pas le 4,5:1).
  final Color live;

  static const Color _materialBase = Color(0xFF121212);

  /// dp des rôles, du plus enfoncé au plus haut. L'ordre suit la pile
  /// historique (fond < panneau < carte < sélection < menu).
  static const Map<String, double> _dp = <String, double>{
    'bg': 0,
    'panel': 1,
    'lineSoft': 2,
    'card': 3,
    'tile': 4,
    'sel': 6,
    'surface3': 8,
    'line': 12,
  };

  static final Map<TvComfortPeriod, TvComfortPalette> _cached =
      <TvComfortPeriod, TvComfortPalette>{
    for (final TvComfortPeriod period in TvComfortPeriod.values)
      period: _build(period),
  };

  static TvComfortPalette of(TvComfortPeriod period) => _cached[period]!;

  /// Heures locales, sans géolocalisation (une box n'a pas à demander
  /// où elle est). Découpe simple, au même endroit, pour pouvoir la
  /// changer plus tard : nuit avant 7 h et à partir de 22 h, jour
  /// jusqu'à 17 h, soir entre les deux.
  static TvComfortPeriod fromHour(int hour) {
    if (hour < 7 || hour >= 22) return TvComfortPeriod.night;
    if (hour < 17) return TvComfortPeriod.day;
    return TvComfortPeriod.evening;
  }

  /// Prochain seuil 7 h / 17 h / 22 h. Le planning ne se réveille
  /// qu'à ce moment-là, pas à chaque image.
  static DateTime nextBoundary(DateTime now) {
    final DateTime local = now;
    const List<int> hours = <int>[7, 17, 22];
    for (final int hour in hours) {
      final DateTime slot = DateTime(local.year, local.month, local.day, hour);
      if (slot.isAfter(local)) return slot;
    }
    final DateTime tomorrow = local.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7);
  }

  static double contrast(Color a, Color b) {
    final double x = a.computeLuminance();
    final double y = b.computeLuminance();
    final double hi = x > y ? x : y;
    final double lo = x > y ? y : x;
    return (hi + 0.05) / (lo + 0.05);
  }

  static TvComfortPalette _build(TvComfortPeriod period) {
    final Color base = switch (period) {
      TvComfortPeriod.day => _materialBase,
      TvComfortPeriod.evening => _materialBase,
      // Première couleur du dégradé Maison Noir : déjà chaude, déjà
      // dans le fichier, plus foncée qu'un or dilué.
      TvComfortPeriod.night =>
        (TvTokens.bgGradient as RadialGradient).colors.first,
    };
    final double tint = period == TvComfortPeriod.evening ? _brandGlowAlpha : 0;
    Color lift(String role) {
      final Color elevated = _elevation(base, _dp[role]!);
      if (tint == 0) return elevated;
      return Color.alphaBlend(
          TvTokens.accent.withValues(alpha: tint), elevated);
    }

    final Color bg = lift('bg');
    final Color panel = lift('panel');
    final Color card = lift('card');
    final Color tile = lift('tile');
    final Color sel = lift('sel');
    final Color surface3 = lift('surface3');
    final Color line = lift('line');
    final Color lineSoft = lift('lineSoft');
    final Color text = _ink(TvTokens.text, bg, 0.87);
    final Color muted = _ink(TvTokens.text, card, 0.60);
    // Plancher WCAG sur la surface de menu (la plus claire des grands
    // aplats). On ne descend pas sous le « muted », pour garder
    // l'ordre : principal > secondaire > tertiaire.
    Color mutedDim = _floorInk(TvTokens.text, surface3, 4.5);
    if (mutedDim.computeLuminance() > muted.computeLuminance()) {
      mutedDim = muted;
    }
    return TvComfortPalette(
      bg: bg,
      panel: panel,
      card: card,
      tile: tile,
      sel: sel,
      surface3: surface3,
      line: line,
      lineSoft: lineSoft,
      text: text,
      muted: muted,
      mutedDim: mutedDim,
      live: _liveAgainst(<Color>[bg, panel, card, tile, sel, surface3]),
    );
  }

  /// Alpha du premier stop de `TvTokens.brandGlow` (0x18 aujourd'hui).
  /// Si le halo de marque change, le soir suit.
  static double get _brandGlowAlpha =>
      (TvTokens.brandGlow as RadialGradient).colors.first.a;

  static Color _elevation(Color base, double dp) {
    if (dp <= 0) return base;
    final double alpha = (4.5 * math.log(1 + dp) + 2) / 100;
    return Color.alphaBlend(Colors.white.withValues(alpha: alpha), base);
  }

  /// Encre = ivoire de marque posé à `opacity` sur la surface, comme
  /// Material pose le blanc à 87 % ou 60 %.
  static Color _ink(Color ink, Color surface, double opacity) =>
      Color.alphaBlend(ink.withValues(alpha: opacity), surface);

  /// Opacité la plus basse de l'ivoire qui atteint encore [minContrast]
  /// sur [surface].
  static Color _floorInk(Color ink, Color surface, double minContrast) {
    Color best = ink;
    for (int step = 1; step <= 100; step++) {
      final Color candidate = _ink(ink, surface, step / 100);
      if (contrast(candidate, surface) >= minContrast) return candidate;
      best = candidate;
    }
    return best;
  }

  /// Le rouge historique, ou sa version lisible : même teinte, saturation
  /// plafonnée à celle de l'or, luminosité juste au-dessus de 4,5:1 sur
  /// la surface la plus claire.
  static Color _liveAgainst(List<Color> surfaces) {
    Color hardest = surfaces.first;
    for (final Color surface in surfaces.skip(1)) {
      if (surface.computeLuminance() > hardest.computeLuminance()) {
        hardest = surface;
      }
    }
    if (contrast(TvTokens.live, hardest) >= 4.5) return TvTokens.live;
    final HSLColor src = HSLColor.fromColor(TvTokens.live);
    final double cap = HSLColor.fromColor(TvTokens.accent).saturation;
    final double saturation = math.min(src.saturation, cap);
    for (int step = 0; step <= 1000; step++) {
      final Color candidate =
          src.withSaturation(saturation).withLightness(step / 1000).toColor();
      if (contrast(candidate, hardest) >= 4.5) return candidate;
    }
    return TvTokens.live;
  }
}
