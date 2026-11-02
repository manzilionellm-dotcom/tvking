import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tv_tokens.dart';

/// Palette de l'interface pilotée par le panel. Les TvTokens historiques
/// restent figés pour les commandes Cast : leur apparence est conservée.
/// L'accès par contexte rend les écrans dépendants du Theme, sans recréer
/// le lecteur, les routes, le focus ni leurs State lors d'un changement.
@immutable
class TvAppTokens extends ThemeExtension<TvAppTokens> {
  const TvAppTokens({this.light = false, this.remoteAccent});
  final bool light;
  final Color? remoteAccent;

  static TvAppTokens of(BuildContext context) =>
      Theme.of(context).extension<TvAppTokens>() ?? const TvAppTokens();

  /// Les contrôles superposés à la vidéo gardent un fond sombre : un thème
  /// clair ne doit jamais poser du texte noir directement sur l'image.
  static TvAppTokens playbackOf(BuildContext context) {
    final palette = of(context);
    return palette.light
        ? TvAppTokens(remoteAccent: palette.remoteAccent)
        : palette;
  }

  Color get bg => light ? const Color(0xFFF6F5F2) : TvTokens.bg;
  Color get panel => light ? const Color(0xFFECEAE5) : TvTokens.panel;
  Color get card => light ? const Color(0xFFFFFFFF) : TvTokens.card;
  Color get tile => light ? const Color(0xFFF0EEE9) : TvTokens.tile;
  Color get tileBorder => light ? const Color(0x1A17171C) : TvTokens.tileBorder;
  Color get badgeBg => remoteAccent == null && !light
      ? TvTokens.badgeBg
      : accent.withValues(alpha: .12);
  Color get sel => light ? const Color(0xFFE3E1DA) : TvTokens.sel;
  Color get surface3 => light ? const Color(0xFFDAD7CF) : TvTokens.surface3;
  Color get line => light ? const Color(0xFFC8C5BD) : TvTokens.line;
  Color get lineSoft => light ? const Color(0xFFE0DDD5) : TvTokens.lineSoft;
  Color get text => light ? const Color(0xFF202026) : TvTokens.text;
  Color get muted => light ? const Color(0xFF55535D) : TvTokens.muted;
  Color get mutedDim => light ? const Color(0xFF65616C) : TvTokens.mutedDim;
  Color get accent => remoteAccent ?? TvTokens.accent;
  Color get accentBright {
    if (remoteAccent == null && !light) return TvTokens.accentBright;
    // Accent servant aussi de texte : contraste lisible sur le fond choisi,
    // même si le panel reçoit du blanc, du jaune ou un bleu très sombre.
    return _readableAccent(accent, bg);
  }

  Color get accentDeep => remoteAccent == null
      ? TvTokens.accentDeep
      : HSLColor.fromColor(accent)
            .withLightness(
              (HSLColor.fromColor(accent).lightness - .22).clamp(0.0, 1.0),
            )
            .toColor();
  Color get onAccent {
    if (remoteAccent == null) return TvTokens.onAccent;
    const dark = Color(0xFF14100A);
    const white = Color(0xFFFFFFFF);
    return contrast(dark, accent) >= contrast(white, accent) ? dark : white;
  }

  Color get live => light ? const Color(0xFFB62D24) : TvTokens.live;
  Color get success => light ? const Color(0xFF207A4D) : TvTokens.success;

  Gradient get bgGradient => !light && remoteAccent == null
      ? TvTokens.bgGradient
      : RadialGradient(
          center: const Alignment(0.56, -.40),
          radius: 1.3,
          colors: <Color>[
            Color.alphaBlend(accent.withValues(alpha: light ? .06 : .08), bg),
            bg,
          ],
          stops: const <double>[0, .6],
        );
  Gradient get brandGlow => remoteAccent == null
      ? TvTokens.brandGlow
      : RadialGradient(
          center: Alignment.topLeft,
          radius: 1.1,
          colors: <Color>[
            accent.withValues(alpha: .094),
            accent.withValues(alpha: 0),
          ],
        );
  Gradient get accentHairline => remoteAccent == null
      ? TvTokens.accentHairline
      : LinearGradient(
          colors: <Color>[
            accent.withValues(alpha: 0),
            accent,
            accent.withValues(alpha: 0),
          ],
        );
  Gradient get ctaGradient => !light && remoteAccent == null
      ? TvTokens.ctaGradient
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[accent, accent],
        );
  Gradient get pillGradient => remoteAccent == null
      ? TvTokens.pillGradient
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            accent.withValues(alpha: .07),
            accent.withValues(alpha: 0),
          ],
        );

  TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
    double spacing = 0,
  }) => GoogleFonts.oswald(
    fontSize: size,
    fontWeight: weight,
    color: color ?? text,
    letterSpacing: spacing,
  );
  TextStyle ui(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double spacing = 0,
  }) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    color: color ?? text,
    letterSpacing: spacing,
  );
  TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
    double spacing = 0,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: size,
    fontWeight: weight,
    color: color ?? accentBright,
    letterSpacing: spacing,
  );

  static double contrast(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
  }

  static Color _readableAccent(Color color, Color background) {
    if (contrast(color, background) >= 4.5) return color;
    final hsl = HSLColor.fromColor(color);
    final towardDark = background.computeLuminance() > .5;
    for (int step = 1; step <= 100; step++) {
      final lightness = (hsl.lightness + (towardDark ? -step : step) / 100)
          .clamp(0.0, 1.0);
      final candidate = hsl.withLightness(lightness).toColor();
      if (contrast(candidate, background) >= 4.5) return candidate;
    }
    return towardDark ? Colors.black : Colors.white;
  }

  @override
  TvAppTokens copyWith({bool? light, Color? remoteAccent}) => TvAppTokens(
    light: light ?? this.light,
    remoteAccent: remoteAccent ?? this.remoteAccent,
  );
  @override
  TvAppTokens lerp(covariant TvAppTokens? other, double t) => other == null
      ? this
      : TvAppTokens(
          light: t < .5 ? light : other.light,
          remoteAccent: Color.lerp(remoteAccent, other.remoteAccent, t),
        );
}
