// =========================================================
//  tv_cinematic_home.dart — Accueil « salon » (demande du 13/11/2026)
// =========================================================
//  De haut en bas :
//   1. une ligne de raccourcis (Direct, Films, Séries, Serveur, Réglages) ;
//   2. le GRAND BANDEAU : ce qu'on regarde en ce moment, sur toute la
//      largeur, son image en fond légèrement floutée, un bouton lecture
//      au centre qui « respire » quand il a le focus ;
//   3. la rangée des favoris : vignettes compactes, coins arrondis, fin
//      liseré doré au focus, image qui avance doucement, et un trait de
//      progression sous chaque carte quand on la connaît vraiment.
//  La barre d'abonnement est dessinée par l'écran qui porte cet accueil
//  (tv_hub_screen.dart).
//
//  Ce qu'on ne fait PAS : ouvrir un flux pour animer une vignette (règle
//  du projet : rien ne se lance tout seul), ni inventer une image ou une
//  progression. Le flou n'est posé que si [blur] est vrai (box au-dessus
//  de 2 Go) ; sinon un voile sombre le remplace.
// =========================================================
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_app_tokens.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_tonight.dart';

Color _field(BuildContext context) =>
    TvAppTokens.of(context).ghost ? TvAppTokens.of(context).bg : TvTokens.bg;
Color _metal(BuildContext context) =>
    TvAppTokens.of(context).ghost ? TvAppTokens.of(context).accent : TvTokens.accent;
Color _metalBright(BuildContext context) => TvAppTokens.of(context).ghost
    ? TvAppTokens.of(context).accentBright
    : TvTokens.accentBright;
Color _onMetal(BuildContext context) =>
    TvAppTokens.of(context).ghost ? TvAppTokens.of(context).onAccent : TvTokens.onAccent;



class TvCinematicHome extends StatelessWidget {
  const TvCinematicHome({
    super.key,
    required this.board,
    required this.blur,
    required this.onPlay,
    required this.onLive,
    required this.onFilms,
    required this.onSeries,
    required this.onServer,
    required this.onSettings,
  });

  final TonightBoard board;
  final bool blur;
  final ValueChanged<TonightPiece> onPlay;
  final VoidCallback onLive;
  final VoidCallback onFilms;
  final VoidCallback onSeries;
  final VoidCallback onServer;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final bool heroFirst = board.hasHero;
    // Une seule rangée : d'abord ce qui est à soi (reprises, favoris),
    // puis ce que la box propose. Aucune carte en double (composeTonight).
    final List<TonightPiece> row = <TonightPiece>[
      ...board.recommendations,
      ...board.discover,
    ];
    final bool vod =
        board.recommendations.any((TonightPiece p) => p.watch != null);
    final String rowLabel = board.recommendations.isEmpty
        ? context.l10n.tvHomePopular
        : (vod ? context.l10n.tvHomeContinue : context.l10n.tvHomeFavorites);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              _Chip(
                icon: Icons.live_tv_rounded,
                label: context.l10n.tvNavLive,
                autofocus: !heroFirst,
                onSelect: onLive,
              ),
              _Chip(
                icon: Icons.movie_rounded,
                label: context.l10n.tvNavFilms,
                onSelect: onFilms,
              ),
              _Chip(
                icon: Icons.video_library_rounded,
                label: context.l10n.tvNavSeries,
                onSelect: onSeries,
              ),
              _Chip(
                icon: Icons.dns_rounded,
                label: context.l10n.tvNavServer,
                onSelect: onServer,
              ),
              _Chip(
                icon: Icons.settings_rounded,
                label: context.l10n.tvNavSettings,
                onSelect: onSettings,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: 70,
          child: _Hero(
            board: board,
            blur: blur,
            autofocus: heroFirst,
            onPlay: board.hero == null ? null : () => onPlay(board.hero!),
          ),
        ),
        if (row.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _RowLabel(rowLabel),
          const SizedBox(height: 8),
          Expanded(
            flex: 30,
            child: _CardRow(pieces: row, onPlay: onPlay),
          ),
        ],
      ],
    );
  }
}

/// Le grand bandeau. Toute la carte prend le focus (cible large pour la
/// télécommande) ; OK lance la lecture.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.board,
    required this.blur,
    required this.autofocus,
    required this.onPlay,
  });

  final TonightBoard board;
  final bool blur;
  final bool autofocus;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final TonightPiece? hero = board.hero;
    final String title = hero?.title ?? context.l10n.tvHomeInvite;
    final String detail = board.heroDetail;
    final String meta = hero?.meta ?? '';
    final String under = <String>[
      if (detail.isNotEmpty) detail,
      if (meta.isNotEmpty) meta,
    ].join(' · ');
    final double? progress = hero?.progress;
    final BorderRadius radius = BorderRadius.circular(22);
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      showGlow: false,
      borderRadius: radius,
      onSelect: onPlay,
      builder: (BuildContext context, bool focused) {
        return AnimatedContainer(
          duration: TvDimens.focusAnim,
          curve: TvDimens.focusCurve,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: focused
                  ? _metalBright(context)
                  : _metal(context).withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _Backdrop(piece: hero, title: title, blur: blur),
              // Voile : le texte reste lisible quelle que soit l'image.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[
                      _field(context).withValues(alpha: 0.92),
                      _field(context).withValues(alpha: 0.55),
                      _field(context).withValues(alpha: 0.20),
                    ],
                  ),
                ),
              ),
              if (onPlay != null) Center(child: _PulsePlay(active: focused)),
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.l10n.tvVoiceTonightTitle.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvAppTokens.of(context).ui(
                        TvDimens.caption,
                        weight: FontWeight.w500,
                        color: _metalBright(context),
                        spacing: 2.2,
                      ),
                    ),
                    const Spacer(),
                    FractionallySizedBox(
                      widthFactor: 0.62,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TvAppTokens.of(context).ui(
                          40,
                          weight: FontWeight.w300,
                          color: TvAppTokens.of(context).text,
                          height: 1.08,
                        ),
                      ),
                    ),
                    if (under.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        under,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvAppTokens.of(context).ui(
                          TvDimens.label,
                          weight: FontWeight.w300,
                          color: TvAppTokens.of(context).muted,
                        ),
                      ),
                    ],
                    if (progress != null) ...<Widget>[
                      const SizedBox(height: 12),
                      FractionallySizedBox(
                        widthFactor: 0.42,
                        alignment: Alignment.centerLeft,
                        child: _ProgressLine(value: progress, height: 3),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Fond du bandeau : l'image de la source, agrandie. Floutée seulement
/// si la box le supporte ; sinon elle est simplement assombrie.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.piece, required this.title, required this.blur});
  final TonightPiece? piece;
  final String title;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final TonightPiece? p = piece;
    final String? art = p?.artworkUrl;
    if (p == null || art == null) return _Monogram(title: title);
    final bool logo = p.artworkIsLogo;
    final Widget image = _Artwork(
      url: art,
      title: title,
      logo: logo,
      logoScale: 0.5,
    );
    // Un logo se montre net et entier, à droite : le flouter le rendrait
    // illisible. Une jaquette remplit le fond et reçoit le flou.
    if (logo) {
      return Align(
        alignment: Alignment.centerRight,
        child: FractionallySizedBox(widthFactor: 0.5, child: image),
      );
    }
    if (!blur) return image;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Transform.scale(scale: 1.06, child: image),
    );
  }
}

/// Bouton lecture au centre du bandeau. Il « respire » doucement tant
/// que le bandeau a le focus. Aucune animation si le système demande de
/// les réduire, ni quand le bandeau n'a pas le focus (rien ne tourne
/// pour rien sur une petite box).
class _PulsePlay extends StatefulWidget {
  const _PulsePlay({required this.active});
  final bool active;

  @override
  State<_PulsePlay> createState() => _PulsePlayState();
}

class _PulsePlayState extends State<_PulsePlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_PulsePlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final bool run = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (run && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!run && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.active;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) {
          final double t = Curves.easeInOut.transform(_c.value);
          return Transform.scale(
            scale: 1 + 0.06 * t,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _field(context).withValues(alpha: on ? 0.55 : 0.38),
                border: Border.all(
                  color: on
                      ? _metalBright(context)
                      : TvAppTokens.of(context).text.withValues(alpha: 0.55),
                  width: 1.2,
                ),
                boxShadow: on
                    ? <BoxShadow>[
                        BoxShadow(
                          color: _metal(context)
                              .withValues(alpha: 0.18 + 0.22 * t),
                          blurRadius: 14 + 10 * t,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
          );
        },
        child: Icon(
          Icons.play_arrow_rounded,
          size: 40,
          color: on ? _metalBright(context) : TvAppTokens.of(context).text,
        ),
      ),
    );
  }
}

/// Trait de progression : fin, discret. [value] entre 0 et 1.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value, this.height = 2});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final double v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(
              color: TvAppTokens.of(context).text.withValues(alpha: 0.14),
            ),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: v,
              child: ColoredBox(color: _metalBright(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TvAppTokens.of(context).ui(
        TvDimens.label,
        weight: FontWeight.w400,
        color: TvAppTokens.of(context).muted,
        spacing: 0.4,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
  });
  final bool autofocus;
  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        showGlow: false,
        borderRadius: BorderRadius.circular(14),
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          final Color fg = focused ? _onMetal(context) : TvAppTokens.of(context).text;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: focused
                  ? _metal(context)
                  : _field(context).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: focused
                    ? _metalBright(context)
                    : _metal(context).withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TvAppTokens.of(context).ui(
                    TvDimens.caption,
                    weight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.pieces, required this.onPlay});
  final List<TonightPiece> pieces;
  final ValueChanged<TonightPiece> onPlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // La carte suit la hauteur disponible (720p comme 4K) : image en
        // 16/9, puis le titre et le trait de progression (34 px).
        final double artH = (box.maxHeight - 34).clamp(40.0, 130.0);
        final double width = artH * 16 / 9;
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: pieces.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (BuildContext context, int i) {
            final TonightPiece piece = pieces[i];
            return _PosterCard(
              piece: piece,
              width: width,
              artHeight: artH,
              onSelect: () => onPlay(piece),
            );
          },
        );
      },
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.piece,
    required this.width,
    required this.artHeight,
    required this.onSelect,
  });
  final TonightPiece piece;
  final double width;
  final double artHeight;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(12);
    final double? progress = piece.progress;
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      showGlow: false,
      borderRadius: radius,
      onSelect: piece.canPlay ? onSelect : null,
      onFocusChange: (bool focused) {
        if (!focused) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 140),
          curve: TvDimens.focusCurve,
        );
      },
      builder: (BuildContext context, bool focused) {
        final bool still = MediaQuery.disableAnimationsOf(context);
        return SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AnimatedContainer(
                duration: TvDimens.focusAnim,
                curve: TvDimens.focusCurve,
                height: artHeight,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: focused
                        ? _metalBright(context)
                        : _metal(context).withValues(alpha: 0.14),
                    width: 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                // Au focus, l'image avance très lentement : la vignette
                // « vit » sans ouvrir de flux.
                child: AnimatedScale(
                  scale: focused && !still ? 1.08 : 1.0,
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 2400),
                  curve: Curves.easeOut,
                  child: _Artwork(
                    url: piece.artworkUrl,
                    title: piece.title,
                    logo: piece.artworkIsLogo,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                piece.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TvAppTokens.of(context).ui(
                  TvDimens.caption,
                  weight: focused ? FontWeight.w500 : FontWeight.w300,
                  color: focused
                      ? TvAppTokens.of(context).text
                      : TvAppTokens.of(context).muted,
                ),
              ),
              const SizedBox(height: 5),
              // Pas de progression connue = pas de trait (rien d'inventé).
              if (progress != null)
                _ProgressLine(value: progress)
              else
                const SizedBox(height: 2),
            ],
          ),
        );
      },
    );
  }
}

/// Jaquette distante, ou monogramme si la source n'a pas d'image.
/// Jamais une affiche embarquée.
///
/// [logo] : l'image est un logo de chaîne. Avant le 13/11/2026 il était
/// agrandi pour REMPLIR la carte (`BoxFit.cover`) : « Eurosport » devenait
/// « ROSPO », « Canal+ » devenait « NAN ». Un logo est maintenant montré EN
/// ENTIER, centré sur le même fond sobre pour toutes les cartes.
class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.url,
    required this.title,
    this.logo = false,
    this.logoScale = 0.74,
  });
  final String? url;
  final String title;
  final bool logo;

  /// Part de la carte occupée par un logo (largeur et hauteur).
  final double logoScale;

  @override
  Widget build(BuildContext context) {
    final String? art = url;
    if (art == null) return _Monogram(title: title);
    if (logo) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              _metal(context).withValues(alpha: 0.22),
              _field(context),
            ],
          ),
        ),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: logoScale,
            heightFactor: logoScale,
            child: CachedNetworkImage(
              imageUrl: art,
              fit: BoxFit.contain,
              memCacheWidth: 360,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => _Monogram(title: title),
            ),
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: art,
      fit: BoxFit.cover,
      memCacheWidth: 360,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => _Monogram(title: title),
      errorWidget: (_, __, ___) => _Monogram(title: title),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final String trimmed = title.trim();
    final String letter = trimmed.isEmpty
        ? ''
        : String.fromCharCodes(<int>[trimmed.runes.first]).toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _metal(context).withValues(alpha: 0.22),
            _field(context),
          ],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TvAppTokens.of(context).display(
            42,
            color: _metalBright(context),
          ),
        ),
      ),
    );
  }
}
