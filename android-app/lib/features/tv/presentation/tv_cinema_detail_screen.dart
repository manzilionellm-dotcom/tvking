// =========================================================
//  tv_cinema_detail_screen.dart — Fiche film + page série
// =========================================================
//  FICHE FILM : grande image de fond, titre, année · durée · note · genre,
//  résumé, distribution. Boutons (le 1er a le focus → un enfant appuie sur
//  OK et le film démarre) :
//    ▶ Lecture  /  ▶ Reprendre à 42:10
//    ↺ Depuis le début              (si film entamé)
//    ⬇ Télécharger / 45 % / ✓ Téléchargé (→ supprimer)
//
//  PAGE SÉRIE : même en-tête ; bouton « Reprendre S2 · E3 » (ou « Lecture
//  S1 · E1 ») ; en dessous, SAISONS à gauche et ÉPISODES à droite (vignette,
//  titre, durée, résumé, barre de progression, bouton ⬇ par épisode).
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../cinema/data/cinema_downloads.dart';
import '../../cinema/data/cinema_repository.dart';
import '../../cinema/data/watch_progress.dart';
import '../../cinema/domain/cinema_models.dart';
import '../../vod/data/download_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_cinema_common.dart';

// =========================================================
//  Commun : fond + en-tête
// =========================================================

class _Backdrop extends StatelessWidget {
  const _Backdrop({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();
    return Positioned(
      right: 0,
      top: 0,
      width: 820,
      height: 460,
      child: ShaderMask(
        // Fondu vers la gauche et vers le bas : le texte reste lisible.
        shaderCallback: (Rect r) => const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: <Color>[Colors.white, Colors.transparent],
          stops: <double>[0.45, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ShaderMask(
          shaderCallback: (Rect r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.white, Colors.transparent],
            stops: <double>[0.55, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: Opacity(
            opacity: 0.55,
            child: CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              memCacheWidth: 960,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.meta, this.plot, this.extra});
  final String title;
  final List<String> meta;
  final String? plot;
  final List<String>? extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TvTokens.display(TvDimens.displayL, color: TvTokens.text)),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(meta.join('  ·  '),
                style: TvTokens.ui(TvDimens.body, weight: FontWeight.w600, color: TvTokens.accentBright)),
          ),
        if (plot != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(plot!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.ui(TvDimens.body, color: TvTokens.text)),
          ),
        for (final String line in extra ?? const <String>[])
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.ui(TvDimens.label, color: TvTokens.mutedDim)),
          ),
      ],
    );
  }
}

String? _durationLabel(BuildContext context, int sec) {
  if (sec <= 0) return null;
  final int h = sec ~/ 3600;
  final int m = (sec % 3600) ~/ 60;
  return h > 0 ? '$h h ${m.toString().padLeft(2, '0')}' : context.l10n.tvCinemaMinutes(m.toString());
}

/// Bouton de téléchargement (libellé et action selon l'état).
class _DownloadPill extends StatefulWidget {
  const _DownloadPill({required this.item, this.compact = false});
  final VodPlayItem item;

  /// Version icône seule (ligne d'épisode).
  final bool compact;

  @override
  State<_DownloadPill> createState() => _DownloadPillState();
}

class _DownloadPillState extends State<_DownloadPill> {
  StreamSubscription<List<Download>>? _sub;
  Download? _d;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _d = DownloadsRepository.instance.byId(widget.item.id);
    _sub = DownloadsRepository.instance.stream.listen((_) {
      final Download? d = DownloadsRepository.instance.byId(widget.item.id);
      if (mounted) setState(() => _d = d);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onSelect() async {
    final Download? d = _d;
    if (d == null || d.status == DownloadStatus.error || d.status == DownloadStatus.paused) {
      final CinemaDownloadStart r = await CinemaDownloads.start(widget.item.toVodMovie());
      if (!mounted) return;
      if (r == CinemaDownloadStart.noSpace) {
        final int free = await CinemaDownloads.freeBytes();
        if (!mounted) return;
        setState(() => _msg = context.l10n.tvCinemaNoSpace(
            (free / (1024 * 1024 * 1024)).toStringAsFixed(1)));
        Future<void>.delayed(const Duration(seconds: 5), () {
          if (mounted) setState(() => _msg = null);
        });
      }
      return;
    }
    if (d.status == DownloadStatus.downloading) {
      await DownloadsRepository.instance.pause(d.id);
      return;
    }
    // Terminé → proposer la suppression (confirmation).
    await showCinemaSheet(context, title: widget.item.subtitle ?? widget.item.title, actions: <CinemaSheetAction>[
      CinemaSheetAction(Icons.delete_outline_rounded, context.l10n.tvCinemaDeleteDownload,
          () => DownloadsRepository.instance.delete(d.id)),
      CinemaSheetAction(Icons.close_rounded, context.l10n.tvCancel, () {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final Download? d = _d;
    final String pct = ((d?.progress ?? 0) * 100).round().toString();
    final IconData icon;
    final String label;
    if (d == null) {
      icon = Icons.download_rounded;
      label = context.l10n.tvCinemaDownload;
    } else {
      switch (d.status) {
        case DownloadStatus.done:
          icon = Icons.download_done_rounded;
          label = context.l10n.tvCinemaDownloaded;
        case DownloadStatus.downloading:
          icon = Icons.downloading_rounded;
          label = context.l10n.tvCinemaDownloading(pct);
        case DownloadStatus.paused:
          icon = Icons.pause_circle_outline_rounded;
          label = context.l10n.tvCinemaDownloadPaused(pct);
        case DownloadStatus.error:
          icon = Icons.error_outline_rounded;
          label = context.l10n.tvCinemaDownloadError;
      }
    }
    if (widget.compact) {
      return TvFocusBuilder(
        scale: TvFocusScale.small,
        onSelect: () => unawaited(_onSelect()),
        builder: (BuildContext context, bool focused) => Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: focused ? TvTokens.accent : TvTokens.sel,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              if (d != null && d.status == DownloadStatus.downloading)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    value: d.progress > 0 ? d.progress : null,
                    strokeWidth: 3,
                    color: focused ? TvTokens.onAccent : TvTokens.accent,
                  ),
                ),
              Icon(icon, size: 24, color: focused ? TvTokens.onAccent : TvTokens.accentBright),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CinemaPill(icon: icon, label: label, onSelect: () => unawaited(_onSelect())),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_msg!, style: TvTokens.ui(TvDimens.caption, color: TvTokens.live)),
          ),
      ],
    );
  }
}

// =========================================================
//  FICHE FILM
// =========================================================

class TvMovieDetailScreen extends StatefulWidget {
  const TvMovieDetailScreen({super.key, required this.title});
  final CinemaTitle title;

  @override
  State<TvMovieDetailScreen> createState() => _TvMovieDetailScreenState();
}

class _TvMovieDetailScreenState extends State<TvMovieDetailScreen> {
  CinemaDetails? _d;

  @override
  void initState() {
    super.initState();
    WatchProgressRepository.instance.addListener(_refresh);
    unawaited(DownloadsRepository.instance.initialize());
    unawaited(CinemaRepository.instance.movieDetails(widget.title).then((CinemaDetails d) {
      if (mounted) setState(() => _d = d);
    }));
  }

  @override
  void dispose() {
    WatchProgressRepository.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final CinemaTitle t = widget.title;
    final CinemaDetails d = _d ?? CinemaDetails.empty;
    final WatchEntry? w = WatchProgressRepository.instance.get(t.id);
    final bool resumable = w != null && w.isResumable && !w.upNext;
    final VodPlayItem item = VodPlayItem.movie(t);
    final double? rating = d.rating ?? t.rating;
    final List<String> meta = <String>[
      if (t.year != null) t.year! else if (d.releaseDate != null && d.releaseDate!.length >= 4) d.releaseDate!.substring(0, 4),
      if (_durationLabel(context, d.durationSec) != null) _durationLabel(context, d.durationSec)!,
      if (rating != null) '★ ${rating.toStringAsFixed(1)}',
      if (d.genre != null) d.genre!,
    ];
    return Stack(
      children: <Widget>[
        _Backdrop(url: d.backdropUrl ?? d.posterUrl ?? t.posterUrl),
        Padding(
          padding: const EdgeInsets.fromLTRB(TvDimens.contentMargin, 60, TvDimens.contentMargin, 40),
          child: SizedBox(
            width: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Header(
                  title: t.name,
                  meta: meta,
                  plot: d.plot,
                  extra: <String>[
                    if (d.cast != null) context.l10n.tvCinemaCast(d.cast!),
                    if (d.director != null) context.l10n.tvCinemaDirector(d.director!),
                  ],
                ),
                if (_d == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: TvTokens.accent)),
                  ),
                const SizedBox(height: 30),
                if (resumable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: 420,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: w.fraction,
                          minHeight: 5,
                          color: TvTokens.accent,
                          backgroundColor: TvTokens.line,
                        ),
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: <Widget>[
                    CinemaPill(
                      icon: Icons.play_arrow_rounded,
                      autofocus: true,
                      label: resumable
                          ? context.l10n.tvCinemaResumeAt(formatClock(Duration(milliseconds: w.posMs)))
                          : context.l10n.tvCinemaPlay,
                      onSelect: () => unawaited(openVod(context, item)),
                    ),
                    if (resumable)
                      CinemaPill(
                        icon: Icons.replay_rounded,
                        label: context.l10n.tvCinemaFromStart,
                        onSelect: () => unawaited(openVod(context, item, fromStart: true)),
                      ),
                    _DownloadPill(item: item),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =========================================================
//  PAGE SÉRIE
// =========================================================

class TvSeriesScreen extends StatefulWidget {
  const TvSeriesScreen({super.key, required this.title});
  final CinemaTitle title;

  @override
  State<TvSeriesScreen> createState() => _TvSeriesScreenState();
}

class _TvSeriesScreenState extends State<TvSeriesScreen> {
  SeriesDetails? _s;
  bool _loading = true;
  int? _season;

  @override
  void initState() {
    super.initState();
    WatchProgressRepository.instance.addListener(_refresh);
    unawaited(DownloadsRepository.instance.initialize());
    unawaited(_load());
  }

  @override
  void dispose() {
    WatchProgressRepository.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final SeriesDetails? s = await CinemaRepository.instance.seriesDetails(widget.title);
    if (!mounted) return;
    final WatchEntry? last = WatchProgressRepository.instance.latestForSeries(widget.title.id);
    int? season = s?.seasons.isNotEmpty == true ? s!.seasons.first.number : null;
    if (last?.season != null && s?.episodes.containsKey(last!.season) == true) season = last!.season;
    setState(() {
      _s = s;
      _season = season;
      _loading = false;
    });
  }

  /// Épisode à lancer avec le gros bouton : celui en cours, sinon le suivant
  /// du dernier vu, sinon S1 · E1.
  CinemaEpisode? _primary() {
    final SeriesDetails? s = _s;
    if (s == null) return null;
    final List<CinemaEpisode> all = s.allInOrder;
    if (all.isEmpty) return null;
    final WatchEntry? last = WatchProgressRepository.instance.latestForSeries(widget.title.id);
    if (last != null) {
      for (final CinemaEpisode e in all) {
        if (e.id == last.id) return last.finished ? (s.nextAfter(e) ?? e) : e;
      }
    }
    return all.first;
  }

  void _play(CinemaEpisode e, {bool fromStart = false}) {
    unawaited(openVod(
      context,
      VodPlayItem.episode(e, widget.title),
      fromStart: fromStart,
      series: _s,
      seriesTitle: widget.title,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final CinemaTitle t = widget.title;
    final SeriesDetails? s = _s;
    final CinemaDetails d = s?.details ?? CinemaDetails.empty;
    final CinemaEpisode? primary = _primary();
    final WatchEntry? pw = primary == null ? null : WatchProgressRepository.instance.get(primary.id);
    final bool resumable = pw != null && pw.isResumable && !pw.upNext;
    final double? rating = d.rating ?? t.rating;
    final List<String> meta = <String>[
      if (t.year != null) t.year!,
      if (rating != null) '★ ${rating.toStringAsFixed(1)}',
      if (d.genre != null) d.genre!,
      if (s != null && s.seasons.length > 1) context.l10n.tvCinemaSeasons(s.seasons.length.toString()),
    ];
    return Stack(
      children: <Widget>[
        _Backdrop(url: d.backdropUrl ?? d.posterUrl ?? t.posterUrl),
        Padding(
          padding: const EdgeInsets.fromLTRB(TvDimens.contentMargin, 40, TvDimens.contentMargin, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 760,
                child: _Header(title: t.name, meta: meta, plot: d.plot ?? t.plot),
              ),
              const SizedBox(height: 18),
              if (primary != null)
                CinemaPill(
                  icon: Icons.play_arrow_rounded,
                  autofocus: true,
                  label: resumable
                      ? context.l10n.tvCinemaResumeEpisode(primary.season.toString(), primary.number.toString())
                      : context.l10n.tvCinemaPlayEpisode(primary.season.toString(), primary.number.toString()),
                  onSelect: () => _play(primary),
                ),
              const SizedBox(height: 18),
              Expanded(child: _buildEpisodes(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodes(BuildContext context) {
    if (_loading) return const CinemaLoading();
    final SeriesDetails? s = _s;
    if (s == null || s.seasons.isEmpty) {
      return Center(
        child: Text(context.l10n.tvCinemaNoEpisodes,
            style: const TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim)),
      );
    }
    final List<CinemaEpisode> eps = s.episodes[_season] ?? const <CinemaEpisode>[];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 250,
          child: ListView.builder(
            itemExtent: 46,
            itemCount: s.seasons.length,
            itemBuilder: (BuildContext context, int i) {
              final CinemaSeason se = s.seasons[i];
              return CinemaRailRow(
                label: se.number == 0
                    ? context.l10n.tvCinemaSpecials
                    : context.l10n.tvCinemaSeason(se.number.toString()),
                count: se.episodeCount,
                selected: se.number == _season,
                onSelect: () => setState(() => _season = se.number),
                onFocused: () {
                  if (_season != se.number) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _season = se.number);
                    });
                  }
                },
              );
            },
          ),
        ),
        const SizedBox(width: TvDimens.gutter),
        Expanded(
          child: ListView.builder(
            itemExtent: 112,
            itemCount: eps.length,
            itemBuilder: (BuildContext context, int i) => _EpisodeRow(
              episode: eps[i],
              series: widget.title,
              onPlay: () => _play(eps[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.series, required this.onPlay});
  final CinemaEpisode episode;
  final CinemaTitle series;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final CinemaEpisode e = episode;
    final WatchEntry? w = WatchProgressRepository.instance.get(e.id);
    final double? progress = w == null || w.upNext ? null : (w.finished ? 1.0 : w.fraction);
    final String title = e.title.isEmpty ? context.l10n.tvCinemaEpisode(e.number.toString()) : '${e.number}. ${e.title}';
    final String? dur = _durationLabel(context, e.durationSec);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TvFocusBuilder(
              scale: TvFocusScale.small,
              onSelect: onPlay,
              builder: (BuildContext context, bool focused) => Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: focused ? TvTokens.sel : TvTokens.card.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                  border: Border.all(
                    color: focused ? TvTokens.accent : TvTokens.lineSoft,
                    width: focused ? TvDimens.focusOutline : 1,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 150,
                        height: 84,
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            ColoredBox(
                              color: TvTokens.tile,
                              child: (e.stillUrl ?? series.posterUrl) == null
                                  ? const Icon(Icons.movie_rounded, color: TvTokens.mutedDim)
                                  : CachedNetworkImage(
                                      imageUrl: (e.stillUrl ?? series.posterUrl)!,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 240,
                                      errorWidget: (_, __, ___) =>
                                          const Icon(Icons.movie_rounded, color: TvTokens.mutedDim),
                                    ),
                            ),
                            if (progress != null && progress > 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 4,
                                  color: TvTokens.accent,
                                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TvTokens.ui(TvDimens.titleS,
                                        weight: FontWeight.w700,
                                        color: focused ? TvTokens.accentBright : TvTokens.text)),
                              ),
                              if (dur != null)
                                Text(dur, style: TvTokens.ui(TvDimens.caption, color: TvTokens.mutedDim)),
                            ],
                          ),
                          if (e.plot != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(e.plot!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TvTokens.ui(TvDimens.caption, color: TvTokens.muted)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _DownloadPill(item: VodPlayItem.episode(e, series), compact: true),
        ],
      ),
    );
  }
}
