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
//  Le fond n'est pas un aplat brun. C'est une obsidienne profonde
//  (jamais #000000 : le noir pur fatigue le texte clair, Material)
//  avec un halo cuivré LOCAL — l'or déjà choisi, en dégradé court,
//  comme la lumière ambiante du modèle. Les cartes sont un verre
//  teinté (voile sombre translucide) : le halo passe au travers
//  sans `BackdropFilter`. Le flou « givre » est un plus, coupé sur
//  les box lentes (`TvGlassPolicy`).
//
//  Trois moments, même verre, halo plus ou moins fort :
//    - jour    : obsidienne neutre, halo discret.
//    - soir    : obsidienne chaude + halo cuivré. Défaut.
//    - nuit    : encore plus sombre, halo plus faible.
//
//  L'IMAGE de la chaîne n'entre pas dans cette palette. Le lecteur
//  la pose sur un noir pur (`Colors.black`) pour ne pas teinter
//  les bandes ni les pixels.
//
//  Calcul une fois, puis lecture. Le chemin par défaut ne floute
//  rien : une box lente ne repeint que des aplats translucides.
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
    required this.ambientPeak,
    required this.ambient,
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

  /// Centre du halo cuivré (or de marque posé sur l'obsidienne).
  /// C'est le fond le plus clair : le contraste s'y mesure.
  final Color ambientPeak;

  /// Halo local. Les bords retombent sur l'obsidienne. Dégradé court
  /// (Android TV : éviter le banding des grands fondus).
  final Gradient ambient;

  /// Verre des cartes. Même valeur que [card] : un voile, pas un aplat.
  Color get glassFill => card;

  static const Color _obsidianDay = Color(0xFF0E0E0E);
  static const Color _obsidianEvening = Color(0xFF0C0A08);
  static const Color _obsidianNight = Color(0xFF0A0806);
  static const Color _glassRgb = Color(0xFF241E18);

  /// Opacité du voile de verre. Plus le rôle est « devant », plus
  /// il couvre le halo — sans jamais devenir un aplat opaque.
  static const Map<String, double> _glassAlpha = <String, double>{
    'panel': 0.42,
    'card': 0.58,
    'tile': 0.64,
    'sel': 0.70,
    'surface3': 0.78,
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

  /// Ce qu'on voit vraiment : le verre posé sur un fond opaque.
  /// `computeLuminance` ignore l'alpha, donc le contraste se mesure ici.
  static Color seen(Color glass, Color behind) =>
      Color.alphaBlend(glass, behind);

  static TvComfortPalette _build(TvComfortPeriod period) {
    final Color bg = switch (period) {
      TvComfortPeriod.day => _obsidianDay,
      TvComfortPeriod.evening => _obsidianEvening,
      TvComfortPeriod.night => _obsidianNight,
    };
    // Soir = le modèle (halo visible, pas un projecteur). Jour et
    // nuit restent sous ce plafond pour ne pas éclairer la pièce.
    final double glow = switch (period) {
      TvComfortPeriod.day => 0.08,
      TvComfortPeriod.evening => 0.20,
      TvComfortPeriod.night => 0.10,
    };
    final Color peak =
        Color.alphaBlend(TvTokens.accent.withValues(alpha: glow), bg);
    Color veil(String role) => _glassRgb.withValues(alpha: _glassAlpha[role]!);
    final Color panel = veil('panel');
    final Color card = veil('card');
    final Color tile = veil('tile');
    final Color sel = veil('sel');
    final Color surface3 = veil('surface3');
    final List<Color> seenOnPeak = <Color>[
      for (final Color glass in <Color>[panel, card, tile, sel, surface3])
        seen(glass, peak),
    ];
    Color lightest = seenOnPeak.first;
    for (final Color surface in seenOnPeak.skip(1)) {
      if (surface.computeLuminance() > lightest.computeLuminance()) {
        lightest = surface;
      }
    }
    final Color text = _ink(TvTokens.text, bg, 0.87);
    final Color muted = _ink(TvTokens.text, lightest, 0.72);
    Color mutedDim = _floorInk(TvTokens.text, lightest, 4.5);
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
      // Filet cuivré doux (bord de verre), pas un néon plein.
      line: TvTokens.accent.withValues(alpha: 0.42),
      lineSoft: TvTokens.text.withValues(alpha: 0.14),
      text: text,
      muted: muted,
      mutedDim: mutedDim,
      live: _liveAgainst(<Color>[bg, ...seenOnPeak]),
      ambientPeak: peak,
      ambient: RadialGradient(
        // Le cercle est plus grand que l'écran. L'obsidienne est
        // atteinte vers le tiers du rayon, donc le bord du dégradé
        // ne tombe pas dans l'image (banding, Android TV).
        center: const Alignment(0.1, -0.15),
        radius: 2.4,
        colors: <Color>[
          peak,
          Color.lerp(peak, bg, 0.45)!,
          Color.lerp(peak, bg, 0.8)!,
          bg,
        ],
        stops: const <double>[0, 0.1, 0.22, 0.38],
      ),
    );
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
    // Toujours plafonner la saturation à celle de l'or, même si le
    // rouge vif passerait le contraste sur une obsidienne très sombre :
    // un rouge saturé vibre (Material) et les TV le rendent criard.
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
