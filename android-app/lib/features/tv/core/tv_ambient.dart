// =========================================================
//  tv_ambient.dart — Halo qui suit le contenu, pas l'image
// =========================================================
//  Le halo reste de l'interface. Aucun filtre n'est posé sur
//  la vidéo : on ne lit qu'un genre (chaîne ou catégorie EPG)
//  et, si on l'a déjà, la moyenne d'une petite image (affiche,
//  logo). Jamais la surface du lecteur.
//
//  Sources, et seulement elles :
//
//  • Philips, brevet US 2007/0091111. On ne prend pas chaque
//    image : une moyenne de couleur (R_AVG) sur une zone, puis
//    une correction de gamma « négative » pour que le halo ne
//    devienne pas criard. Le gamma vidéo cité est 2,5 ; le gamma
//    utile d'une source ambiante (LED) est 1,8. On applique
//    donc l'exposant 2,5 / 1,8 au rouge, au vert et au bleu
//    linéaires de cette moyenne.
//    https://www.freepatentsonline.com/y2007/0091111.html
//
//  • Philips, communiqué Ambilight, et Ingrid Vogels (IS&T,
//    CIC 2009) : la SMPTE place la lumière autour de l'écran
//    à environ 10 % du blanc de pointe, pour fatiguer moins
//    l'œil. Le halo ne dépasse pas cette luminance.
//    https://www.newscenter.philips.com/pwc_nc/main/shared/assets/at/Downloadablefile/at-en_news06_ce_ambilight_background-15769.pdf
//
//  • What Hi-Fi, modes Ambilight : « Football » est plus vif
//    et plus réactif, « Relax » est plus calme. Ici, le sport
//    monte vers le plafond SMPTE ; le cinéma redescend vers
//    l'obsidienne et vers l'or déjà choisi (plus chaud).
//    https://www.whathifi.com/advice/what-is-ambilight-is-the-philips-tv-technology-worth-it
//
//  • Android TV, couleurs tirées de l'affiche (pas du fond
//    d'écran) : https://developer.android.com/design/ui/tv/guides/styles/color-system
//    La moyenne ignore le noir et le blanc purs, comme la
//    Palette Android écarte les tons extrêmes avant de noter
//    saturation, luminance et population.
//    https://developer.android.com/develop/ui/views/graphics/palette-colors
//
//  Le genre vient de `ChannelGenre` (déjà classé sur la
//  catégorie M3U / Xtream, ou sur la catégorie EPG par le
//  même classeur). On n'ajoute pas de liste de mots.
// =========================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../channels/domain/channel_genre.dart';
import 'tv_comfort.dart';
import 'tv_tokens.dart';

/// Ce que le halo doit faire. Neutre = le soir déjà dessiné.
enum TvAmbientMood { cinema, sport, neutral }

/// Halo prêt à peindre. [peak] est le centre, [bg] l'obsidienne.
@immutable
class TvAmbientLook {
  const TvAmbientLook({required this.peak, required this.bg});

  final Color peak;
  final Color bg;

  /// Même géométrie que le soir confort : le cercle dépasse l'écran,
  /// l'obsidienne arrive avant son bord.
  Gradient get gradient => RadialGradient(
        center: const Alignment(0.1, -0.15),
        radius: 2.4,
        colors: <Color>[
          peak,
          Color.lerp(peak, bg, 0.45)!,
          Color.lerp(peak, bg, 0.8)!,
          bg,
        ],
        stops: const <double>[0, 0.1, 0.22, 0.38],
      );

  static TvAmbientLook lerp(TvAmbientLook a, TvAmbientLook b, double t) {
    return TvAmbientLook(
      peak: Color.lerp(a.peak, b.peak, t)!,
      bg: Color.lerp(a.bg, b.bg, t)!,
    );
  }
}

/// Calcul pur. Testable sans écran et sans décodeur.
abstract final class TvAmbientMath {
  /// Plafond SMPTE : 10 % du blanc de pointe (luminance relative 1).
  static const double smpteCeiling = 0.10;

  /// Film, série, documentaire : plus sombre et plus chaud.
  /// Sport : plus clair, teinte de l'échantillon gardée.
  static TvAmbientMood moodFor(ChannelGenre genre, [String? epgCategory]) {
    final ChannelGenre fromGuide =
        (epgCategory == null || epgCategory.trim().isEmpty)
            ? ChannelGenre.other
            : ChannelClassifier.classifyGenre('', epgCategory);
    final ChannelGenre picked = switch (fromGuide) {
      ChannelGenre.sports ||
      ChannelGenre.movies ||
      ChannelGenre.series ||
      ChannelGenre.documentary =>
        fromGuide,
      _ => genre,
    };
    return switch (picked) {
      ChannelGenre.sports => TvAmbientMood.sport,
      ChannelGenre.movies ||
      ChannelGenre.series ||
      ChannelGenre.documentary =>
        TvAmbientMood.cinema,
      _ => TvAmbientMood.neutral,
    };
  }

  /// Moyenne Philips (R_AVG) des pixels qui ne sont ni le noir des
  /// bandes ni un blanc brûlé. [rgb] est une suite r, v, b, r, v, b…
  /// Vide ou tout extrême : on rend l'or de marque, pas un noir.
  static Color averageRgb(List<int> rgb) {
    int rs = 0, gs = 0, bs = 0, n = 0;
    for (int i = 0; i + 2 < rgb.length; i += 3) {
      final Color c = Color.fromARGB(255, rgb[i], rgb[i + 1], rgb[i + 2]);
      final double y = c.computeLuminance();
      if (y < 0.05 || y > 0.90) continue;
      rs += rgb[i];
      gs += rgb[i + 1];
      bs += rgb[i + 2];
      n++;
    }
    if (n == 0) return TvTokens.accent;
    return Color.fromARGB(255, rs ~/ n, gs ~/ n, bs ~/ n);
  }

  /// [seed] a déjà été moyenné, ou c'est l'or si on n'a pas d'image.
  /// Le soir confort sert de milieu : le cinéma va vers le sombre,
  /// le sport va à mi-chemin du plafond SMPTE.
  static TvAmbientLook look({
    required TvAmbientMood mood,
    required Color seed,
    required TvComfortPalette evening,
  }) {
    final Color corrected = _ledGamma(seed);
    final double cap = HSLColor.fromColor(TvTokens.accent).saturation;
    HSLColor hsl = HSLColor.fromColor(corrected);
    final double eveningL = evening.ambientPeak.computeLuminance();
    final double target = switch (mood) {
      TvAmbientMood.cinema => eveningL * 0.5,
      TvAmbientMood.sport => eveningL + (smpteCeiling - eveningL) * 0.5,
      TvAmbientMood.neutral => eveningL,
    };
    if (mood == TvAmbientMood.cinema) {
      final HSLColor warm = HSLColor.fromColor(TvTokens.accent);
      hsl = HSLColor.lerp(hsl, warm, 0.5)!;
      hsl = hsl.withSaturation(math.min(hsl.saturation, cap * 0.7));
    } else {
      hsl = hsl.withSaturation(math.min(hsl.saturation, cap));
    }
    final Color peak = _withLuminance(hsl, target.clamp(0.0, smpteCeiling));
    return TvAmbientLook(peak: peak, bg: evening.bg);
  }

  /// Gamma 2,5 du flux, ramené vers 1,8 (brevet Philips).
  static Color _ledGamma(Color input) {
    double channel(double u) {
      final double lin = u <= 0.04045
          ? u / 12.92
          : math.pow((u + 0.055) / 1.055, 2.4).toDouble();
      final double shaped = math.pow(lin.clamp(0.0, 1.0), 2.5 / 1.8).toDouble();
      final double out = shaped <= 0.0031308
          ? shaped * 12.92
          : 1.055 * math.pow(shaped, 1 / 2.4).toDouble() - 0.055;
      return out.clamp(0.0, 1.0);
    }

    return Color.from(
      alpha: 1,
      red: channel(input.r),
      green: channel(input.g),
      blue: channel(input.b),
    );
  }

  static Color _withLuminance(HSLColor hsl, double target) {
    Color best = hsl.toColor();
    double bestGap = (best.computeLuminance() - target).abs();
    for (int step = 0; step <= 100; step++) {
      final Color candidate = hsl.withLightness(step / 100).toColor();
      final double gap = (candidate.computeLuminance() - target).abs();
      if (gap < bestGap) {
        best = candidate;
        bestGap = gap;
      }
    }
    return best;
  }
}
