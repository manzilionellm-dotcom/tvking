// Même direction artistique que la TV : les couleurs et les typographies
// Stealth sont reprises de la PR 221. La composition utilise les vrais dp
// du téléphone : ni réduction du canevas TV, ni police artificiellement petite.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/domain/channel.dart';
import 'tv_tonight.dart';

class TvStealthMobileHome extends StatefulWidget {
  const TvStealthMobileHome({
    super.key,
    required this.board,
    required this.profileName,
    required this.profileIcon,
    required this.profileColor,
    required this.greeting,
    required this.time,
    required this.activationCode,
    required this.status,
    required this.statusColor,
    required this.source,
    required this.onProfile,
    required this.onSearch,
    required this.onPlay,
    required this.onLive,
    required this.onFilms,
    required this.onSeries,
    required this.onServer,
    required this.onSettings,
    this.supplement,
    this.notice,
  });
  final TonightBoard board;
  final String profileName, greeting, time, activationCode, status, source;
  final IconData profileIcon;
  final Color profileColor, statusColor;
  final VoidCallback onProfile,
      onSearch,
      onLive,
      onFilms,
      onSeries,
      onServer,
      onSettings;
  final ValueChanged<TonightPiece> onPlay;
  final Widget? supplement;
  final String? notice;

  @override
  State<TvStealthMobileHome> createState() => _TvStealthMobileHomeState();
}

class _TvStealthMobileHomeState extends State<TvStealthMobileHome> {
  TonightPiece? _focused;

  Color get _ambient {
    final piece = _focused ?? widget.board.hero;
    if (piece?.watch != null) return AppColors.stealthCinema;
    final channel = piece?.channel;
    return switch (ChannelClassifier.classifyGenre(
      channel?.name ?? '',
      channel?.category ?? '',
    )) {
      ChannelGenre.sports => AppColors.stealthSport,
      ChannelGenre.movies || ChannelGenre.series => AppColors.stealthCinema,
      ChannelGenre.kids => AppColors.stealthKids,
      _ => AppColors.stealthIce,
    };
  }

  void _focus(TonightPiece piece) {
    if (_focused != piece) setState(() => _focused = piece);
  }

  @override
  Widget build(BuildContext context) {
    final hero = widget.board.hero;
    final actions = <(String, IconData, String, VoidCallback)>[
      ('live', Icons.live_tv_rounded, context.l10n.tvNavLive, widget.onLive),
      ('films', Icons.movie_outlined, context.l10n.tvNavFilms, widget.onFilms),
      (
        'series',
        Icons.video_library_outlined,
        context.l10n.tvNavSeries,
        widget.onSeries
      ),
      (
        'sources',
        Icons.dns_outlined,
        context.l10n.tvNavServer,
        widget.onServer
      ),
      (
        'settings',
        Icons.settings_outlined,
        context.l10n.tvNavSettings,
        widget.onSettings
      ),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey<String>('zuno-touch-hub-root'),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(children: <Widget>[
                  Expanded(
                      child: Text(context.l10n.tvStealthWordmark,
                          style: AppTextStyles.stealthBrand,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  _RoundAction(
                      label: context.l10n.tvNavSearch,
                      icon: Icons.search_rounded,
                      onTap: widget.onSearch),
                  const SizedBox(width: 8),
                  _RoundAction(
                      label: widget.profileName,
                      icon: widget.profileIcon,
                      color: widget.profileColor,
                      onTap: widget.onProfile),
                ]),
                const SizedBox(height: 8),
                Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _QualityBadge(context.l10n.tvStealthPremierBadge),
                      TextButton(
                        onPressed: widget.onProfile,
                        style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        child: Text(widget.profileName,
                            style: AppTextStyles.stealthCaption),
                      ),
                    ]),
                if (widget.greeting.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(widget.greeting,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.stealthCaption),
                ],
                const SizedBox(height: 18),
                // Chaque commande reste à 48 dp minimum. La navigation peut
                // défiler horizontalement ; elle ne réduit jamais les textes.
                Container(
                  decoration: _glassDecoration(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(6),
                    child: Row(children: <Widget>[
                      for (final action in actions)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: OutlinedButton.icon(
                            key:
                                ValueKey<String>('zuno-touch-hub-${action.$1}'),
                            onPressed: action.$4,
                            icon: Icon(action.$2, size: 20),
                            label: Text(action.$3),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(96, 48),
                              maximumSize: Size(
                                  MediaQuery.sizeOf(context).width - 48,
                                  double.infinity),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              foregroundColor: AppColors.stealthPlatinum,
                              textStyle: AppTextStyles.stealthBody,
                              side: BorderSide(
                                  color: AppColors.stealthPlatinum
                                      .withValues(alpha: .2)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 22),
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: 1.2,
                      colors: <Color>[
                        _ambient.withValues(alpha: .18),
                        AppColors.stealthBlack
                      ],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(children: <Widget>[
                      if (hero != null && (hero.artworkUrl ?? '').isNotEmpty)
                        Positioned.fill(
                            child: ExcludeSemantics(
                                child: Opacity(
                          opacity: .5,
                          child: _Artwork(piece: hero, background: true),
                        ))),
                      Positioned.fill(
                          child: DecoratedBox(
                              decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            AppColors.stealthBlack.withValues(alpha: .15),
                            AppColors.stealthBlack
                          ],
                        ),
                      ))),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 260),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 26),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                  context.l10n.tvVoiceTonightTitle
                                      .toUpperCase(),
                                  style: AppTextStyles.stealthEyebrow),
                              const SizedBox(height: 16),
                              Text(hero?.title ?? context.l10n.tvHomeInvite,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.stealthMobileHero),
                              if (widget
                                  .board.heroDetail.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 10),
                                Text(widget.board.heroDetail,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.stealthBody),
                              ],
                              if ((hero?.meta ?? '').isNotEmpty) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(hero!.meta,
                                    style: AppTextStyles.stealthCaption),
                              ],
                              if (hero?.canPlay == true) ...<Widget>[
                                const SizedBox(height: 22),
                                Row(children: <Widget>[
                                  _RoundAction(
                                    key: const Key('stealth-mobile-hero-play'),
                                    label: context.l10n.moviesPlayTooltip,
                                    icon: Icons.play_arrow_rounded,
                                    primary: true,
                                    onTap: () => widget.onPlay(hero!),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                      child: Text(
                                          context.l10n.moviesPlayTooltip,
                                          style: AppTextStyles.stealthBody)),
                                ]),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                if (widget.board.recommendations.isNotEmpty)
                  _Shelf(
                    title:
                        widget.board.recommendations.any((p) => p.watch != null)
                            ? context.l10n.tvHomeContinue
                            : context.l10n.tvHomeFavorites,
                    pieces: widget.board.recommendations,
                    onPlay: widget.onPlay,
                    onFocus: _focus,
                  ),
                if (widget.board.discover.isNotEmpty)
                  _Shelf(
                      title: context.l10n.tvHomePopular,
                      pieces: widget.board.discover,
                      onPlay: widget.onPlay,
                      onFocus: _focus),
                if (widget.supplement != null) widget.supplement!,
                if ((widget.notice ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(widget.notice!, style: AppTextStyles.stealthCaption),
                ],
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(
                              color: AppColors.stealthPlatinum
                                  .withValues(alpha: .16)))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                          Text(context.l10n.tvActivationCodeLabel,
                              style: AppTextStyles.stealthCaption),
                          SelectableText(widget.activationCode,
                              textDirection: TextDirection.ltr,
                              style: AppTextStyles.stealthCode),
                        ]),
                        const SizedBox(height: 10),
                        Wrap(spacing: 16, runSpacing: 8, children: <Widget>[
                          if (widget.status.isNotEmpty)
                            Text(widget.status,
                                style: AppTextStyles.stealthCaption
                                    .copyWith(color: widget.statusColor)),
                          Text(widget.time,
                              textDirection: TextDirection.ltr,
                              style: AppTextStyles.stealthCaption),
                        ]),
                        if (widget.source.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(widget.source,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.stealthCaption),
                        ],
                      ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _glassDecoration() => BoxDecoration(
      color: AppColors.stealthGlass,
      borderRadius: BorderRadius.circular(16),
      border:
          Border.all(color: AppColors.stealthPlatinum.withValues(alpha: .2)),
    );

class _RoundAction extends StatelessWidget {
  const _RoundAction(
      {super.key,
      required this.label,
      required this.icon,
      required this.onTap,
      this.primary = false,
      this.color});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final Color? color;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, size: primary ? 30 : 24),
        style: IconButton.styleFrom(
          minimumSize: Size.square(primary ? 58 : 48),
          backgroundColor:
              primary ? AppColors.stealthPlatinum : AppColors.stealthGlass,
          foregroundColor: primary
              ? AppColors.stealthBlack
              : color ?? AppColors.stealthPlatinum,
          side: BorderSide(
              color: AppColors.stealthPlatinum.withValues(alpha: .25)),
          shape: const CircleBorder(),
        ),
      );
}

class _Shelf extends StatelessWidget {
  const _Shelf(
      {required this.title,
      required this.pieces,
      required this.onPlay,
      required this.onFocus});
  final String title;
  final List<TonightPiece> pieces;
  final ValueChanged<TonightPiece> onPlay, onFocus;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: AppTextStyles.stealthTitle),
              const SizedBox(height: 12),
              SizedBox(
                height: 156 + MediaQuery.textScalerOf(context).scale(16) * 2.6,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  itemCount: pieces.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _ContentCard(
                      piece: pieces[i],
                      onPlay: () => onPlay(pieces[i]),
                      onFocus: () => onFocus(pieces[i])),
                ),
              ),
            ]),
      );
}

class _ContentCard extends StatefulWidget {
  const _ContentCard(
      {required this.piece, required this.onPlay, required this.onFocus});
  final TonightPiece piece;
  final VoidCallback onPlay, onFocus;
  @override
  State<_ContentCard> createState() => _ContentCardState();
}

class _ContentCardState extends State<_ContentCard> {
  bool _focused = false;
  void _focus(bool value) {
    setState(() => _focused = value);
    if (value) widget.onFocus();
  }

  @override
  Widget build(BuildContext context) {
    final piece = widget.piece;
    final quality = streamQualityLabel(piece.channel?.name ?? piece.title);
    return SizedBox(
      width: 208,
      child: AnimatedScale(
        scale: _focused ? 1.025 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        child: Material(
          color: AppColors.stealthSurface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                  color: AppColors.stealthPlatinum
                      .withValues(alpha: _focused ? 1 : .2))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: piece.canPlay ? widget.onPlay : null,
            onFocusChange: _focus,
            onHover: _focus,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                      child: Stack(fit: StackFit.expand, children: <Widget>[
                    _Artwork(piece: piece),
                    PositionedDirectional(
                        start: 8,
                        end: 8,
                        bottom: 8,
                        child:
                            Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
                          if (piece.channel?.isLive == true)
                            _QualityBadge(context.l10n.badgeLive),
                          if (quality != null) _QualityBadge(quality),
                        ])),
                  ])),
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(piece.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.stealthBody)),
                  if (piece.watch != null && piece.watch!.durMs > 0)
                    LinearProgressIndicator(
                        minHeight: 2,
                        value: (piece.watch!.posMs / piece.watch!.durMs)
                            .clamp(0, 1),
                        color: AppColors.stealthIce,
                        backgroundColor: AppColors.stealthSurface),
                ]),
          ),
        ),
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.stealthBlack.withValues(alpha: .85),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: AppColors.stealthPlatinum.withValues(alpha: .2))),
        child: Text(text,
            style: AppTextStyles.stealthCaption
                .copyWith(color: AppColors.stealthPlatinum)),
      );
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.piece, this.background = false});
  final TonightPiece piece;
  final bool background;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => background
        ? const SizedBox.shrink()
        : Center(
            child: Text(
                piece.title.isEmpty
                    ? 'Z'
                    : piece.title.characters.take(2).toString().toUpperCase(),
                style: AppTextStyles.stealthMobileHero
                    .copyWith(color: AppColors.stealthMuted)));
    if ((piece.artworkUrl ?? '').trim().isEmpty) return fallback();
    return Padding(
      padding:
          piece.channel != null ? const EdgeInsets.all(18) : EdgeInsets.zero,
      child: CachedNetworkImage(
          imageUrl: piece.artworkUrl!,
          fit: piece.channel != null ? BoxFit.contain : BoxFit.cover,
          memCacheWidth: background ? 1280 : 448,
          fadeInDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          placeholder: (_, __) => fallback(),
          errorWidget: (_, __, ___) => fallback()),
    );
  }
}
