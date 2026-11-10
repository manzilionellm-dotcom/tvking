import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'tv_comfort.dart';
import 'tv_ghost.dart';
import 'tv_tokens.dart';
import 'tv_type.dart';

/// Palette de l'interface pilotée par le panel. Les TvTokens historiques
/// restent figés pour les commandes Cast : leur apparence est conservée.
/// L'accès par contexte rend les écrans dépendants du Theme, sans recréer
/// le lecteur, les routes, le focus ni leurs State lors d'un changement.
///
/// Noir Fantôme garde son noir OLED et son accent platine, même si le
/// panel a mémorisé un thème clair ou une couleur. Ces valeurs restent
/// disponibles quand la personne choisit Confort. Le puits vidéo du
/// lecteur n'utilise pas ces surfaces.
@immutable
class TvAppTokens extends ThemeExtension<TvAppTokens> {
  const TvAppTokens({
    bool light = false,
    this.remoteAccent,
    this.period = TvComfortPeriod.evening,
    this.ghost = false,
  }) : _requestedLight = light;
  final bool _requestedLight;

  /// État réellement affiché : Material et les écrans doivent eux aussi
  /// rester sombres sous Ghost. La demande du panel n'est pas effacée.
  bool get light => !ghost && _requestedLight;
  final Color? remoteAccent;

  /// Moment sombre (jour / soir / nuit). Ignoré en mode clair du panel
  /// et quand [ghost] est vrai (le Ghost a sa propre pile).
  final TvComfortPeriod period;

  /// Apparence Noir Fantôme. Ses surfaces et accents restent prioritaires
  /// sur les couleurs du panel ; Confort conserve leur comportement.
  final bool ghost;

  bool get _darkGhost => ghost;

  TvComfortPalette get _comfort => TvComfortPalette.of(period);

  static TvAppTokens of(BuildContext context) =>
      Theme.of(context).extension<TvAppTokens>() ?? const TvAppTokens();

  /// Les contrôles superposés à la vidéo gardent un fond sombre : un thème
  /// clair ne doit jamais poser du texte noir directement sur l'image.
  static TvAppTokens playbackOf(BuildContext context) {
    final palette = of(context);
    // Chrome du lecteur : sombre, même si le panel a demandé le clair,
    // pour ne pas poser du texte noir sur l'image. Le moment (soir, etc.)
    // colore les cartons, pas les pixels de la vidéo.
    return palette.light
        ? TvAppTokens(
            remoteAccent: palette.remoteAccent,
            period: palette.period,
            ghost: palette.ghost,
          )
        : palette;
  }

  Color get bg => light
      ? const Color(0xFFF6F5F2)
      : _darkGhost
          ? TvGhost.bg
          : _comfort.bg;
  Color get panel => light
      ? const Color(0xFFECEAE5)
      : _darkGhost
          ? TvGhost.panel
          : _comfort.panel;
  Color get card => light
      ? const Color(0xFFFFFFFF)
      : _darkGhost
          ? TvGhost.card
          : _comfort.card;
  Color get tile => light
      ? const Color(0xFFF0EEE9)
      : _darkGhost
          ? TvGhost.tile
          : _comfort.tile;
  Color get tileBorder =>
      light ? const Color(0x1A17171C) : text.withValues(alpha: 0.10);
  Color get badgeBg => accent.withValues(alpha: .12);
  Color get sel => light
      ? const Color(0xFFE3E1DA)
      : _darkGhost
          ? TvGhost.sel
          : _comfort.sel;
  Color get surface3 => light
      ? const Color(0xFFDAD7CF)
      : _darkGhost
          ? TvGhost.surface3
          : _comfort.surface3;
  Color get line => light
      ? const Color(0xFFC8C5BD)
      : _darkGhost
          ? TvGhost.line
          : _comfort.line;
  Color get lineSoft => light
      ? const Color(0xFFE0DDD5)
      : _darkGhost
          ? TvGhost.lineSoft
          : _comfort.lineSoft;
  Color get text => light
      ? const Color(0xFF202026)
      : _darkGhost
          ? TvGhost.text
          : _comfort.text;
  Color get muted => light
      ? const Color(0xFF55535D)
      : _darkGhost
          ? TvGhost.muted
          : _comfort.muted;
  Color get mutedDim => light
      ? const Color(0xFF65616C)
      : _darkGhost
          ? TvGhost.mutedDim
          : _comfort.mutedDim;
  Color get accent =>
      _darkGhost ? TvGhost.chrome : remoteAccent ?? TvTokens.accent;
  Color get accentBright {
    if (_darkGhost) return TvGhost.chromeBright;
    if (remoteAccent == null && !light) return TvTokens.accentBright;
    // Accent servant aussi de texte : contraste lisible sur le fond choisi,
    // même si le panel reçoit du blanc, du jaune ou un bleu très sombre.
    return _readableAccent(accent, bg);
  }

  Color get accentDeep => _darkGhost
      ? TvGhost.chromeDeep
      : remoteAccent == null
          ? TvTokens.accentDeep
          : HSLColor.fromColor(accent)
              .withLightness(
                (HSLColor.fromColor(accent).lightness - .22).clamp(0.0, 1.0),
              )
              .toColor();
  Color get onAccent {
    if (_darkGhost) return TvGhost.onChrome;
    if (remoteAccent == null) return TvTokens.onAccent;
    const dark = Color(0xFF14100A);
    const white = Color(0xFFFFFFFF);
    return contrast(dark, accent) >= contrast(white, accent) ? dark : white;
  }

  Color get live => light ? const Color(0xFFB62D24) : _comfort.live;

  /// Texte posé SUR un aplat [live]. Sombre le soir (le rose lisible
  /// est trop clair pour du blanc), clair si le panel est en mode jour.
  Color get onLive {
    const Color dark = TvTokens.onAccent;
    const Color white = Color(0xFFFFFFFF);
    return TvComfortPalette.contrast(dark, live) >=
            TvComfortPalette.contrast(white, live)
        ? dark
        : white;
  }

  Color get success => light ? const Color(0xFF207A4D) : TvTokens.success;

  /// Verre des cartes (voile translucide). Le layout VIP le pose sur
  /// le halo ; les écrans déjà écrits lisent [card], qui est ce verre.
  Color get glassFill => light
      ? card.withValues(alpha: 0.92)
      : _darkGhost
          ? AppColors.stealthGlass
      : _comfort.glassFill;

  /// Filet du verre : platine sous Ghost, accent du panel sous Confort.
  Color get glassEdge => light ? line : accent.withValues(alpha: 0.42);

  Gradient get bgGradient => _darkGhost || (!light && remoteAccent == null)
      ? _darkGhost
          ? RadialGradient(
              center: const Alignment(0.56, -.40),
              radius: 1.3,
              colors: <Color>[bg, bg],
              stops: const <double>[0, .6],
            )
          : _comfort.ambient
      : RadialGradient(
          center: const Alignment(0.56, -.40),
          radius: 1.3,
          colors: <Color>[
            Color.alphaBlend(accent.withValues(alpha: light ? .06 : .08), bg),
            bg,
          ],
          stops: const <double>[0, .6],
        );
  Gradient get brandGlow => remoteAccent == null && !_darkGhost
      ? TvTokens.brandGlow
      : RadialGradient(
          center: Alignment.topLeft,
          radius: 1.1,
          colors: <Color>[
            accent.withValues(alpha: .094),
            accent.withValues(alpha: 0),
          ],
        );
  Gradient get accentHairline => remoteAccent == null && !_darkGhost
      ? TvTokens.accentHairline
      : LinearGradient(
          colors: <Color>[
            accent.withValues(alpha: 0),
            accent,
            accent.withValues(alpha: 0),
          ],
        );

  /// Bouton principal : accent plein, pas le reflet vif.
  /// Le reflet (`accentBright`) reste réservé au focus, pour ne pas
  /// éclairer un grand aplat dans une pièce noire. Le texte du bouton
  /// est [onAccent] (7:1 sur l'or historique).
  Gradient get ctaGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[accent, accent],
      );
  Gradient get pillGradient => remoteAccent == null && !_darkGhost
      ? TvTokens.pillGradient
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            accent.withValues(alpha: .07),
            accent.withValues(alpha: 0),
          ],
        );

  /// Oswald seulement pour les grands titres (Android TV : une fonte
  /// plus expressive se limite au display). Inter, sans-serif aux
  /// contreformes larges, porte le texte courant. Les deux sont déjà
  /// dans les assets : aucun téléchargement sur la box.
  ///
  /// `height` 1,15 / 1,3 : l'interligne Material (corps souvent ~1,4)
  /// sans doubler la hauteur des lignes déjà serrées de la grille TV.
  TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
    double spacing = 0,
  }) => TvType.display(
    size,
    weight: weight,
    color: color ?? text,
    letterSpacing: spacing,
  );
  TextStyle ui(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double spacing = 0,
    double? height,
  }) => TvType.ui(
    size,
    weight: weight,
    color: color ?? text,
    letterSpacing: spacing,
    height: height,
  );
  TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TvType.body(size, weight: weight, color: color ?? text);
  TextStyle figure(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) => TvType.figure(size, weight: weight, color: color ?? text);
  TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
    double spacing = 0,
  }) => TvType.code(
    size,
    weight: weight,
    color: color ?? accentBright,
    letterSpacing: spacing,
  );

  static double contrast(Color a, Color b) => TvComfortPalette.contrast(a, b);

  static Color _readableAccent(Color color, Color background) {
    if (contrast(color, background) >= 4.5) return color;
    final hsl = HSLColor.fromColor(color);
    final towardDark = background.computeLuminance() > .5;
    for (int step = 1; step <= 100; step++) {
      final lightness =
          (hsl.lightness + (towardDark ? -step : step) / 100).clamp(0.0, 1.0);
      final candidate = hsl.withLightness(lightness).toColor();
      if (contrast(candidate, background) >= 4.5) return candidate;
    }
    return towardDark ? Colors.black : Colors.white;
  }

  @override
  TvAppTokens copyWith({
    bool? light,
    Color? remoteAccent,
    TvComfortPeriod? period,
    bool? ghost,
  }) =>
      TvAppTokens(
        light: light ?? _requestedLight,
        remoteAccent: remoteAccent ?? this.remoteAccent,
        period: period ?? this.period,
        ghost: ghost ?? this.ghost,
      );
  @override
  TvAppTokens lerp(covariant TvAppTokens? other, double t) => other == null
      ? this
      : TvAppTokens(
          light: t < .5 ? _requestedLight : other._requestedLight,
          period: t < .5 ? period : other.period,
          ghost: t < .5 ? ghost : other.ghost,
          remoteAccent: Color.lerp(remoteAccent, other.remoteAccent, t),
        );
}
