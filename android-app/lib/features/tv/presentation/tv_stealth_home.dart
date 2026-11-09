// Accueil Noir Fantôme. Ce widget ne possède ni lecteur ni abonnement :
// il affiche le catalogue déjà composé et appelle les actions existantes.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/app/box_memory_budget.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/domain/channel_genre.dart';
import '../core/tv_ambient_director.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import 'tv_glass.dart';
import 'tv_tonight.dart';

/// Le halo suit le genre réel de la carte focalisée. Aucun accès aux pixels
/// vidéo, aucune image supplémentaire téléchargée pour calculer la couleur.
Color stealthAmbientFor(TonightPiece? piece) {
  if (piece?.watch != null) return AppColors.stealthCinema;
  final channel = piece?.channel;
  final genre = ChannelClassifier.classifyGenre(
    channel?.name ?? '',
    channel?.category ?? '',
  );
  return switch (genre) {
    ChannelGenre.sports => AppColors.stealthSport,
    ChannelGenre.movies || ChannelGenre.series => AppColors.stealthCinema,
    ChannelGenre.kids => AppColors.stealthKids,
    _ => AppColors.stealthIce,
  };
}

class TvStealthHome extends StatefulWidget {
  const TvStealthHome({
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
  final VoidCallback onLive, onFilms, onSeries, onServer, onSettings;

  @override
  State<TvStealthHome> createState() => _TvStealthHomeState();
}

class _TvStealthHomeState extends State<TvStealthHome> {
  TonightPiece? _focusedPiece;

  @override
  void didUpdateWidget(covariant TvStealthHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Un changement de profil/source ne conserve pas le halo de l'ancien.
    if (oldWidget.board.hero?.title != widget.board.hero?.title) {
      _focusedPiece = null;
    }
  }

  void _focusPiece(TonightPiece piece) {
    if (_focusedPiece == piece) return;
    setState(() => _focusedPiece = piece);
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final hero = board.hero;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final animate = BoxMemoryBudget.paintFocusGlow && !reduced;
    return ListenableBuilder(
      listenable: TvAmbientDirector.instance,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Fond bord à bord, indépendant du scroll. Les logos de chaînes
          // restent contenus dans le hero : on n'étire pas un logo en affiche.
          if (hero?.watch != null && (hero?.artworkUrl ?? '').isNotEmpty)
            ExcludeSemantics(
              child: Opacity(
                opacity: .5,
                child: StealthArtwork(piece: hero!, background: true),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: <Color>[AppColors.stealthBlack, Colors.transparent],
                stops: <double>[0, .85],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.transparent, AppColors.stealthBlack],
                stops: <double>[0, .72],
              ),
            ),
          ),
          if (TvAmbientDirector.instance.choice == TvAmbientChoice.auto)
            IgnorePointer(
              child: AnimatedContainer(
                key: const Key('stealth-ambient'),
                duration: animate ? TvAmbientDirector.blend : Duration.zero,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(.7, -.8),
                    radius: 1.2,
                    colors: <Color>[
                      stealthAmbientFor(_focusedPiece ?? hero)
                          .withValues(alpha: .16),
                      Colors.transparent,
                    ],
                    stops: const <double>[0, .8],
                  ),
                ),
              ),
            ),
          FocusTraversalGroup(
            child: SingleChildScrollView(
              key: const PageStorageKey<String>('stealth-home-scroll'),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Navigation(
                    blur: widget.blur &&
                        BoxMemoryBudget.paintFocusGlow &&
                        !reduced,
                    autofocus: hero?.canPlay != true,
                    actions: <(IconData, String, VoidCallback)>[
                      (
                        Icons.live_tv_rounded,
                        context.l10n.tvNavLive,
                        widget.onLive,
                      ),
                      (
                        Icons.movie_outlined,
                        context.l10n.tvNavFilms,
                        widget.onFilms,
                      ),
                      (
                        Icons.video_library_outlined,
                        context.l10n.tvNavSeries,
                        widget.onSeries,
                      ),
                      (
                        Icons.dns_outlined,
                        context.l10n.tvNavServer,
                        widget.onServer,
                      ),
                      (
                        Icons.settings_outlined,
                        context.l10n.tvNavSettings,
                        widget.onSettings,
                      ),
                    ],
                  ),
                  _Spotlight(
                    board: board,
                    onPlay: widget.onPlay,
                    onFocus: () {
                      if (hero != null) _focusPiece(hero);
                    },
                  ),
                  if (board.recommendations.isNotEmpty)
                    _Shelf(
                      title: board.recommendations.any((p) => p.watch != null)
                          ? context.l10n.tvHomeContinue
                          : context.l10n.tvHomeFavorites,
                      pieces: board.recommendations,
                      onPlay: widget.onPlay,
                      onFocus: _focusPiece,
                    ),
                  if (board.discover.isNotEmpty)
                    _Shelf(
                      title: context.l10n.tvHomePopular,
                      pieces: board.discover,
                      onPlay: widget.onPlay,
                      onFocus: _focusPiece,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.actions,
    required this.blur,
    required this.autofocus,
  });
  final List<(IconData, String, VoidCallback)> actions;
  final bool blur, autofocus;
  @override
  Widget build(BuildContext context) => TvGlassPanel(
        blur: blur,
        radius: TvDimens.panelRadius,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            for (int i = 0; i < actions.length; i++)
              StealthAction(
                label: actions[i].$2,
                icon: actions[i].$1,
                autofocus: autofocus && i == 0,
                onSelect: actions[i].$3,
              ),
          ],
        ),
      );
}

/// Tous les contrôles passent par le même focus TV/OK/tactile. Le groupe
/// de navigation Flutter révèle les cartes lors du parcours au D-pad.
/// On ne force pas un scroll lors de l'autofocus initial du bouton Lecture.
class StealthAction extends StatelessWidget {
  const StealthAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onSelect,
    this.autofocus = false,
    this.onFocus,
    this.circular = false,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onSelect;
  final VoidCallback? onFocus;
  final bool autofocus, circular, primary;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: TvFocusBuilder(
          autofocus: autofocus,
          onSelect: onSelect,
          showGlow: false,
          scale: TvFocusScale.medium,
          borderRadius:
              BorderRadius.circular(circular ? 40 : TvDimens.cardRadius),
          onFocusChange: (focused) {
            if (!focused) return;
            onFocus?.call();
          },
          builder: (context, focused) {
            final filled = primary || focused;
            final fg =
                filled ? AppColors.stealthBlack : AppColors.stealthPlatinum;
            return Container(
              width: circular ? 64 : null,
              height: circular ? 64 : 44,
              padding: circular
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color:
                    filled ? AppColors.stealthPlatinum : AppColors.stealthGlass,
                borderRadius: BorderRadius.circular(
                  circular ? 40 : TvDimens.cardRadius,
                ),
                border: Border.all(
                  color: AppColors.stealthPlatinum.withValues(
                    alpha: focused ? 1 : .2,
                  ),
                ),
                boxShadow: focused &&
                        BoxMemoryBudget.paintFocusGlow &&
                        !MediaQuery.disableAnimationsOf(context)
                    ? <BoxShadow>[
                        BoxShadow(
                          color: AppColors.stealthIce.withValues(alpha: .25),
                          blurRadius: 16,
                          spreadRadius: -4,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: circular
                  ? Icon(icon, size: 34, color: fg)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(icon, size: 20, color: fg),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: AppTextStyles.stealthBody.copyWith(color: fg),
                        ),
                      ],
                    ),
            );
          },
        ),
      );
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({
    required this.board,
    required this.onPlay,
    required this.onFocus,
  });
  final TonightBoard board;
  final ValueChanged<TonightPiece> onPlay;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final hero = board.hero;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 260),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      context.l10n.tvVoiceTonightTitle.toUpperCase(),
                      style: AppTextStyles.stealthEyebrow,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hero?.title ?? context.l10n.tvHomeInvite,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.stealthHero,
                    ),
                    if (board.heroDetail.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        board.heroDetail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.stealthBody,
                      ),
                    ],
                    if ((hero?.meta ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        hero!.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.stealthCaption,
                      ),
                    ],
                    if (hero?.canPlay == true) ...<Widget>[
                      const SizedBox(height: 20),
                      Row(
                        children: <Widget>[
                          StealthAction(
                            key: const Key('stealth-hero-play'),
                            label: context.l10n.moviesPlayTooltip,
                            icon: Icons.play_arrow_rounded,
                            circular: true,
                            primary: true,
                            autofocus: true,
                            onFocus: onFocus,
                            onSelect: () => onPlay(hero!),
                          ),
                          const SizedBox(width: 14),
                          Flexible(
                            child: Text(
                              context.l10n.moviesPlayTooltip,
                              style: AppTextStyles.stealthBody,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (box.maxWidth > 700) ...<Widget>[
                const SizedBox(width: 32),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 180,
                    child: hero?.channel != null
                        ? StealthArtwork(piece: hero!)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.title,
    required this.pieces,
    required this.onPlay,
    required this.onFocus,
  });
  final String title;
  final List<TonightPiece> pieces;
  final ValueChanged<TonightPiece> onPlay, onFocus;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Text(title, style: AppTextStyles.stealthTitle),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                itemCount: pieces.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, i) => _ContentCard(
                  piece: pieces[i],
                  onSelect: () => onPlay(pieces[i]),
                  onFocus: () => onFocus(pieces[i]),
                ),
              ),
            ),
          ],
        ),
      );
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.piece,
    required this.onSelect,
    required this.onFocus,
  });
  final TonightPiece piece;
  final VoidCallback onSelect, onFocus;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: piece.title,
        child: TvFocusBuilder(
          enabled: piece.canPlay,
          onSelect: onSelect,
          showGlow: false,
          scale: TvFocusScale.medium,
          onFocusChange: (focused) {
            if (!focused) return;
            onFocus();
          },
          builder: (context, focused) => Container(
            width: 224,
            decoration: BoxDecoration(
              color: AppColors.stealthSurface,
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              border: Border.all(
                color: AppColors.stealthPlatinum.withValues(
                  alpha: focused ? 1 : .24,
                ),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TvDimens.cardRadius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        StealthArtwork(piece: piece),
                        if (piece.channel?.isLive == true ||
                            piece.meta.isNotEmpty)
                          PositionedDirectional(
                            start: 8,
                            end: 8,
                            bottom: 8,
                            child: Wrap(
                              spacing: 6,
                              children: <Widget>[
                                if (piece.channel?.isLive == true)
                                  const _Badge('LIVE'),
                                if (streamQualityLabel(
                                  piece.channel?.name ?? piece.title,
                                )
                                    case final String quality)
                                  _Badge(quality),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Text(
                      piece.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.stealthBody,
                    ),
                  ),
                  if (piece.watch != null && piece.watch!.durMs > 0)
                    LinearProgressIndicator(
                      minHeight: 2,
                      value:
                          (piece.watch!.posMs / piece.watch!.durMs).clamp(0, 1),
                      color: AppColors.stealthIce,
                      backgroundColor: AppColors.stealthSurface,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.stealthBlack.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: AppColors.stealthPlatinum.withValues(alpha: .2),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.stealthCaption.copyWith(
            color: AppColors.stealthPlatinum,
          ),
        ),
      );
}

/// Décodage borné selon la RAM, logos en contain, affiches en cover.
/// Une URL absente ou cassée devient un monogramme, jamais une fausse affiche.
class StealthArtwork extends StatelessWidget {
  const StealthArtwork({
    super.key,
    required this.piece,
    this.background = false,
  });
  final TonightPiece piece;
  final bool background;
  @override
  Widget build(BuildContext context) {
    final url = piece.artworkUrl?.trim() ?? '';
    Widget fallback() => background
        ? const SizedBox.shrink()
        : Center(
            child: Text(
              piece.title.isEmpty
                  ? 'Z'
                  : piece.title.characters.take(2).toString().toUpperCase(),
              style: AppTextStyles.stealthHero.copyWith(
                color: AppColors.stealthMuted,
              ),
            ),
          );
    if (url.isEmpty) return fallback();
    return Padding(
      padding: !background && piece.channel != null
          ? const EdgeInsets.all(18)
          : EdgeInsets.zero,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: !background && piece.channel != null
            ? BoxFit.contain
            : BoxFit.cover,
        memCacheWidth: background
            ? (BoxMemoryBudget.hubBackgroundCacheWidth ?? 1920)
            : 448,
        fadeInDuration: BoxMemoryBudget.logoFade(TvDimens.focusAnim),
        placeholder: (_, __) => fallback(),
        errorWidget: (_, __, ___) => fallback(),
      ),
    );
  }
}
