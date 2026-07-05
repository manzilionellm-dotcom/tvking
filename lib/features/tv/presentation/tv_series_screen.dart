// =========================================================
//  tv_series_screen.dart — Séries (VOD) 10-foot
// =========================================================
//  Onglet SÉRIES : catalogue de séries du compte Xtream. Catégories à gauche,
//  grille d'AFFICHES à droite. OK sur une série → fiche SÉRIE (saisons +
//  épisodes). OK sur un épisode → lecteur plein écran (ExoPlayer).
//
//  Données : SeriesRepository (cache mémoire plafonné RAM = anti-OOM). Les
//  ÉPISODES d'une série sont chargés À LA DEMANDE à l'ouverture de la fiche.
// =========================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../vod/data/series_repository.dart';
import '../../vod/domain/vod_series.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_player_screen.dart';

class TvSeriesScreen extends StatefulWidget {
  const TvSeriesScreen({super.key});

  @override
  State<TvSeriesScreen> createState() => _TvSeriesScreenState();
}

class _TvSeriesScreenState extends State<TvSeriesScreen> {
  bool _loading = true;
  List<VodSeries> _all = const <VodSeries>[];
  List<String> _cats = const <String>[];
  Map<String, List<VodSeries>> _byCat = const <String, List<VodSeries>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final List<VodSeries> series =
        await SeriesRepository.instance.fetchSeries();
    if (!mounted) return;
    // Groupement UNE fois par catégorie (ordre d'apparition) → une rangée
    // horizontale par catégorie, façon Netflix. Mêmes objets référencés :
    // pas de duplication mémoire.
    final List<String> cats = <String>[];
    final Map<String, List<VodSeries>> byCat = <String, List<VodSeries>>{};
    for (final VodSeries s in series) {
      final String c = s.category.trim().isEmpty ? 'Autres' : s.category.trim();
      final List<VodSeries>? existing = byCat[c];
      if (existing == null) {
        cats.add(c);
        byCat[c] = <VodSeries>[s];
      } else {
        existing.add(s);
      }
    }
    setState(() {
      _all = series;
      _cats = cats;
      _byCat = byCat;
      _loading = false;
    });
  }

  void _openSeries(VodSeries s) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TvSeriesDetailScreen(series: s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Squelette « respirant » (structure de la page) plutôt qu'une roue.
    if (_loading) return const TvSkeletonRails(withHero: true, rails: 2);
    if (_all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.video_library_outlined,
                size: 52, color: TvTokens.mutedDim),
            const SizedBox(height: 14),
            Text(context.l10n.tvNavSeries,
                style: TvTokens.display(26, color: TvTokens.text)),
            const SizedBox(height: 8),
            Text(
                context.l10n.tvNoSeries,
                textAlign: TextAlign.center,
                style: TvTokens.ui(15, color: TvTokens.mutedDim)),
          ],
        ),
      );
    }
    // PRÉSENTATION « NETFLIX » : une SÉRIE VEDETTE en haut, puis une rangée
    // horizontale par catégorie. Tout est paresseux (builder vertical +
    // builder horizontal) → sûr sur box à RAM limitée.
    final VodSeries hero = _all.first;
    return ListView.builder(
      addAutomaticKeepAlives: false,
      itemCount: 1 + _cats.length,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return _SeriesHero(
            series: hero,
            autofocus: true,
            onOpen: () => _openSeries(hero),
          );
        }
        final String cat = _cats[i - 1];
        final List<VodSeries> list = _byCat[cat] ?? const <VodSeries>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  cat.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(13,
                      weight: FontWeight.w700,
                      color: TvTokens.mutedDim,
                      spacing: 1.6),
                ),
              ),
              SizedBox(
                height: 218,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  addAutomaticKeepAlives: false,
                  itemExtent: 142,
                  itemCount: list.length,
                  itemBuilder: (BuildContext context, int j) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _SeriesPoster(
                      series: list[j],
                      onSelect: () => _openSeries(list[j]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Grande vignette vedette (haut de l'onglet Séries) : visuel + titre + méta
/// + bouton « Voir la série » (ouvre la fiche saisons/épisodes).
class _SeriesHero extends StatelessWidget {
  const _SeriesHero({
    required this.series,
    required this.onOpen,
    this.autofocus = false,
  });

  final VodSeries series;
  final VoidCallback onOpen;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final String meta = <String>[
      if (series.year != null && series.year!.isNotEmpty) series.year!,
      if (series.rating != null && series.rating!.isNotEmpty)
        '★ ${series.rating}',
      if (series.category.trim().isNotEmpty) series.category.trim(),
    ].join('   ·   ');

    final Widget fallback = Container(
      color: TvTokens.tile,
      child: Center(
        child: Icon(Icons.live_tv_rounded, size: 44, color: TvTokens.mutedDim),
      ),
    );

    return Container(
      height: 210,
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[TvTokens.sel, TvTokens.card],
        ),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    series.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.display(28, color: TvTokens.text),
                  ),
                  if (meta.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(14, color: TvTokens.muted)),
                  ],
                  const SizedBox(height: 18),
                  TvFocusBuilder(
                    autofocus: autofocus,
                    scale: TvFocusScale.small,
                    onSelect: onOpen,
                    builder: (BuildContext context, bool focused) {
                      final Color bg =
                          focused ? TvTokens.gold : TvTokens.badgeBg;
                      final Color fg = focused
                          ? const Color(0xFF1A1206)
                          : TvTokens.goldBright;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius:
                              BorderRadius.circular(TvDimens.cardRadius),
                          border: Border.all(color: TvTokens.gold),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.play_arrow_rounded, color: fg, size: 24),
                            const SizedBox(width: 8),
                            Text(context.l10n.tvViewSeries,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: fg)),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 340,
            child: (series.posterUrl == null || series.posterUrl!.isEmpty)
                ? fallback
                : CachedNetworkImage(
                    imageUrl: series.posterUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 480,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, __) => fallback,
                    errorWidget: (_, __, ___) => fallback,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SeriesPoster extends StatelessWidget {
  const _SeriesPoster({required this.series, required this.onSelect});
  final VodSeries series;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: onSelect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _poster(),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(series.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: TvDimens.caption,
                    fontWeight: FontWeight.w600,
                    color: TvTokens.text)),
          ),
        ],
      ),
    );
  }

  Widget _poster() {
    final Widget fallback = Container(
      color: TvTokens.tile,
      child: Center(
        child: Icon(Icons.live_tv_rounded, size: 30, color: TvTokens.mutedDim),
      ),
    );
    final String? url = series.posterUrl;
    if (url == null || url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 300,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

// =========================================================
//  FICHE SÉRIE — saisons + épisodes
// =========================================================
class TvSeriesDetailScreen extends StatefulWidget {
  const TvSeriesDetailScreen({required this.series, super.key});
  final VodSeries series;

  @override
  State<TvSeriesDetailScreen> createState() => _TvSeriesDetailScreenState();
}

class _TvSeriesDetailScreenState extends State<TvSeriesDetailScreen> {
  late Future<List<VodEpisode>> _future;
  int _season = 0; // 0 = pas encore choisi → on prend la 1re saison dispo

  @override
  void initState() {
    super.initState();
    _future = SeriesRepository.instance.fetchEpisodes(widget.series.id);
  }

  void _playEpisode(List<VodEpisode> seasonEps, int index) {
    final List<Channel> list = seasonEps
        .map((VodEpisode e) => Channel(
              id: e.id,
              name: '${e.tag} · ${e.title}',
              category: widget.series.name,
              streamUrl: e.streamUrl,
              isLive: false,
              logoUrl: widget.series.posterUrl,
            ))
        .toList(growable: false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: list, startIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvTokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 32, 48, 24),
          child: FutureBuilder<List<VodEpisode>>(
            future: _future,
            builder: (BuildContext context,
                AsyncSnapshot<List<VodEpisode>> snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final List<VodEpisode> eps = snap.data ?? const <VodEpisode>[];
              if (eps.isEmpty) {
                return Center(
                  child: Text(context.l10n.tvNoEpisodes,
                      style: TvTokens.ui(16, color: TvTokens.mutedDim)),
                );
              }
              // Saisons disponibles (triées).
              final List<int> seasons =
                  eps.map((VodEpisode e) => e.season).toSet().toList()..sort();
              final int currentSeason =
                  seasons.contains(_season) ? _season : seasons.first;
              final List<VodEpisode> seasonEps = eps
                  .where((VodEpisode e) => e.season == currentSeason)
                  .toList(growable: false);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.series.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.display(28, color: TvTokens.text)),
                  const SizedBox(height: 14),
                  // ----- Sélecteur de saison (si plusieurs) -----
                  if (seasons.length > 1)
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: seasons.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (BuildContext context, int i) {
                          final int s = seasons[i];
                          return _SeasonChip(
                            label: 'Saison $s',
                            selected: s == currentSeason,
                            autofocus: i == 0,
                            onSelect: () => setState(() => _season = s),
                          );
                        },
                      ),
                    ),
                  if (seasons.length > 1) const SizedBox(height: 14),
                  // ----- Épisodes de la saison -----
                  Expanded(
                    child: ListView.separated(
                      addAutomaticKeepAlives: false,
                      itemCount: seasonEps.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int i) => _EpisodeRow(
                        episode: seasonEps[i],
                        autofocus: seasons.length <= 1 && i == 0,
                        onPlay: () => _playEpisode(seasonEps, i),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onSelect,
  });
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final bool active = selected && !focused;
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: (focused || active) ? TvTokens.sel : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: focused
                ? Border.all(color: TvTokens.gold, width: TvDimens.focusOutline)
                : null,
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: TvDimens.body,
                  fontWeight: FontWeight.w700,
                  color: focused
                      ? TvTokens.goldBright
                      : (active ? TvTokens.text : TvTokens.muted))),
        );
      },
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.onPlay,
    this.autofocus = false,
  });
  final VodEpisode episode;
  final VoidCallback onPlay;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: onPlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 64,
              alignment: Alignment.center,
              child: Text(episode.tag,
                  style: TextStyle(
                      fontSize: TvDimens.label,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.gold)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: TvDimens.title,
                      fontWeight: FontWeight.w600,
                      color: TvTokens.text)),
            ),
            const SizedBox(width: 12),
            Icon(Icons.play_circle_outline_rounded,
                size: 26, color: TvTokens.mutedDim),
          ],
        ),
      ),
    );
  }
}
