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
import '../../vod/data/playback_position_repository.dart';
import '../../vod/data/series_repository.dart';
import '../../vod/domain/vod_info.dart';
import '../../vod/domain/vod_series.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_poster_prefetch.dart';
import '../core/tv_cine_route.dart';
import '../core/tv_tokens.dart';
import '../data/cine_perf.dart';
import 'tv_components.dart';
import 'tv_player_screen.dart';

class TvSeriesScreen extends StatefulWidget {
  const TvSeriesScreen({super.key});

  @override
  State<TvSeriesScreen> createState() => _TvSeriesScreenState();
}

class _TvSeriesScreenState extends State<TvSeriesScreen> {
  // MÉMOIRE D'ÉTAT ENTRE ONGLETS — même pattern que TvFilmsScreen : scroll
  // (PageStorage sur bucket statique) + dernière affiche focusée, pour
  // retrouver l'onglet Séries EXACTEMENT où on l'a laissé.
  static final PageStorageBucket _bucket = PageStorageBucket();
  static String? _focusCat;
  static int _focusIndex = 0;

  bool _loading = true;
  List<VodSeries> _all = const <VodSeries>[];
  List<String> _cats = const <String>[];
  Map<String, List<VodSeries>> _byCat = const <String, List<VodSeries>>{};

  @override
  void initState() {
    super.initState();
    // Rafraîchissement SILENCIEUX (façon Netflix) : ouverture instantanée
    // depuis le cache disque, mise à jour sans spinner quand le réseau
    // rapporte du neuf (stale-while-revalidate du SeriesRepository).
    SeriesRepository.instance.addListener(_onCatalogRefreshed);
    _load();
  }

  @override
  void dispose() {
    SeriesRepository.instance.removeListener(_onCatalogRefreshed);
    super.dispose();
  }

  void _onCatalogRefreshed() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    // Libellé du rayon « Autres » capturé AVANT les await (contexte sûr).
    final String othersLabel = context.l10n.tvOthers;
    // [silent] = mise à jour arrière-plan : pas de squelette, l'écran actuel
    // reste affiché jusqu'au setState final.
    if (mounted && !silent) setState(() => _loading = true);
    final List<VodSeries> series =
        await SeriesRepository.instance.fetchSeries();
    if (!mounted) return;
    // Groupement UNE fois par catégorie (ordre d'apparition) → une rangée
    // horizontale par catégorie, façon Netflix. Mêmes objets référencés :
    // pas de duplication mémoire.
    final List<String> cats = <String>[];
    final Map<String, List<VodSeries>> byCat = <String, List<VodSeries>>{};
    for (final VodSeries s in series) {
      final String c =
          s.category.trim().isEmpty ? othersLabel : s.category.trim();
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
      TvCineRoute<void>(builder: (_) => TvSeriesDetailScreen(series: s)),
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
            Text(context.l10n.tvNoSeries,
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
    // Mémoire du focus par rangée (retour d'onglet) : index de la catégorie
    // qui portait le focus, -1 si aucune → autofocus sur la vedette.
    final int memCat = _cats.indexOf(_focusCat ?? '');
    return PageStorage(
      bucket: _bucket,
      child: ListView.builder(
        key: const PageStorageKey<String>('series-vertical'),
        addAutomaticKeepAlives: false,
        itemCount: 1 + _cats.length,
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return _SeriesHero(
              series: hero,
              autofocus: memCat < 0,
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
                    key: PageStorageKey<String>('series-rail-$cat'),
                    scrollDirection: Axis.horizontal,
                    addAutomaticKeepAlives: false,
                    itemExtent: 142,
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int j) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      // RepaintBoundary : le zoom de focus d'une affiche ne
                      // repeint qu'elle, pas la rangée (GPU des box modestes).
                      child: RepaintBoundary(
                        child: _SeriesPoster(
                          series: list[j],
                          autofocus: (i - 1) == memCat &&
                              j == _focusIndex.clamp(0, list.length - 1),
                          // Mémoire du focus + pré-chargement des jaquettes de
                          // la rangée SUIVANTE pendant la navigation de celle-ci.
                          onFocus: () {
                            _focusCat = cat;
                            _focusIndex = j;
                            if (i < _cats.length) {
                              TvPosterPrefetch.prefetchRow(
                                context,
                                <String?>[
                                  for (final VodSeries s in _byCat[_cats[i]] ??
                                      const <VodSeries>[])
                                    s.posterUrl,
                                ],
                              );
                            }
                          },
                          onSelect: () => _openSeries(list[j]),
                        ),
                      ),
                    ),
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
  const _SeriesPoster({
    required this.series,
    required this.onSelect,
    this.autofocus = false,
    this.onFocus,
  });
  final VodSeries series;
  final VoidCallback onSelect;

  /// Reprend le focus au retour sur l'onglet (mémoire du focus par rangée).
  final bool autofocus;

  /// Notifie la prise de focus (mémoire + pré-chargement rangée suivante).
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      autofocus: autofocus,
      onFocusChange: onFocus == null
          ? null
          : (bool focused) {
              if (focused) onFocus!();
            },
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
//  FICHE SÉRIE — en-tête enrichi (backdrop, synopsis, casting)
//  + saisons + épisodes
// =========================================================
//  L'en-tête est ENRICHI « gratuitement » : `get_series_info` (déjà appelé
//  pour les épisodes) renvoie aussi synopsis/casting/genre/backdrop —
//  SeriesRepository.fetchDetail livre les deux d'un SEUL appel réseau.
//  Le titre et le synopsis du catalogue (VodSeries.plot) s'affichent
//  IMMÉDIATEMENT ; la fiche riche complète dès que la réponse arrive.
class TvSeriesDetailScreen extends StatefulWidget {
  const TvSeriesDetailScreen({required this.series, super.key});
  final VodSeries series;

  @override
  State<TvSeriesDetailScreen> createState() => _TvSeriesDetailScreenState();
}

class _TvSeriesDetailScreenState extends State<TvSeriesDetailScreen> {
  late Future<({VodInfo? info, List<VodEpisode> episodes})> _future;
  int _season = 0; // 0 = pas encore choisi → on prend la 1re saison dispo

  @override
  void initState() {
    super.initState();
    _future = SeriesRepository.instance.fetchDetail(widget.series.id);
    // Reprise de lecture : les barres de progression des épisodes se mettent
    // à jour toutes seules (retour du lecteur, sauvegarde périodique). Le
    // ensureLoaded est un filet — le vrai load() est branché au démarrage.
    PlaybackPositionRepository.instance.addListener(_onPositionsChanged);
    PlaybackPositionRepository.instance
        .ensureLoaded()
        .then((_) => _onPositionsChanged());
  }

  @override
  void dispose() {
    PlaybackPositionRepository.instance.removeListener(_onPositionsChanged);
    super.dispose();
  }

  void _onPositionsChanged() {
    if (mounted) setState(() {}); // progress lu directement dans build()
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
    // Budget « Regarder → première frame < 2,5 s » : chrono depuis L'APPUI.
    CinePerf.start(CinePerf.playToFirstFrame);
    Navigator.of(context).push(
      TvCineRoute<void>(
        builder: (_) => TvPlayerScreen(channels: list, startIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvTokens.bg,
      body: FutureBuilder<({VodInfo? info, List<VodEpisode> episodes})>(
        future: _future,
        builder: (BuildContext context,
            AsyncSnapshot<({VodInfo? info, List<VodEpisode> episodes})> snap) {
          final VodInfo? info = snap.data?.info;
          final bool waiting = snap.connectionState == ConnectionState.waiting;
          // En-tête TOUJOURS affiché tout de suite : le catalogue connaît
          // déjà nom/synopsis/note (VodSeries) — get_series_info ne fait
          // qu'enrichir (casting, genre, backdrop). Jamais d'écran vide.
          final String? plot = info?.plot ?? widget.series.plot;
          final String? year = info?.year ?? widget.series.year;
          final String? rating = info?.rating ?? widget.series.rating;
          final String meta = <String>[
            if (year != null && year.isNotEmpty) year,
            if (info?.genre != null) info!.genre!,
            if (rating != null && rating.isNotEmpty) '★ $rating',
          ].join('   ·   ');

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // ----- BACKDROP plein écran (si le serveur en fournit un),
              //  décodage borné anti-OOM + scrim sombre : la liste des
              //  épisodes doit rester parfaitement lisible par-dessus. -----
              if (info?.backdropUrl != null)
                CachedNetworkImage(
                  imageUrl: info!.backdropUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 960,
                  fadeInDuration: const Duration(milliseconds: 250),
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              if (info?.backdropUrl != null)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0xD908080A), Color(0xF508080A)],
                    ),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 32, 48, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(widget.series.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TvTokens.display(28, color: TvTokens.text)),
                      if (meta.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TvTokens.ui(14,
                                weight: FontWeight.w600,
                                color: TvTokens.muted)),
                      ],
                      if (plot != null && plot.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 640, // colonne de lecture 10-foot
                          child: Text(plot,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TvTokens.ui(14, color: TvTokens.text)
                                  .copyWith(height: 1.45)),
                        ),
                      ],
                      if (info?.cast != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(context.l10n.tvDetailWithCast(info!.cast!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TvTokens.ui(13, color: TvTokens.muted)),
                      ],
                      const SizedBox(height: 14),
                      // ----- Zone saisons + épisodes -----
                      // Pendant get_series_info : SQUELETTE de rangées
                      // d'épisodes (jamais de roue centrale — la structure
                      // de la page « respire », perception premium).
                      Expanded(
                        child: waiting
                            ? const _EpisodesSkeleton()
                            : _episodesArea(
                                snap.data?.episodes ?? const <VodEpisode>[]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Sélecteur de saison + liste des épisodes (inchangé fonctionnellement —
  /// simplement extrait pour que l'en-tête enrichi reste lisible).
  Widget _episodesArea(List<VodEpisode> eps) {
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
                  label: context.l10n.tvSeriesSeason(s),
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
              // Fraction déjà vue (reprise) — null si jamais entamé.
              progress: PlaybackPositionRepository.instance
                  .progressFor(seasonEps[i].id),
              onPlay: () => _playEpisode(seasonEps, i),
            ),
          ),
        ),
      ],
    );
  }
}

/// Squelette de la zone épisodes : rangées fantômes « respirantes »
/// (même pattern que TvSkeletonRails — opacité douce, respecte
/// disableAnimations) pendant le get_series_info. Aucun spinner.
class _EpisodesSkeleton extends StatefulWidget {
  const _EpisodesSkeleton();

  @override
  State<_EpisodesSkeleton> createState() => _EpisodesSkeletonState();
}

class _EpisodesSkeletonState extends State<_EpisodesSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Accessibilité/perf : si les animations sont désactivées (réglage
    // système), les barres restent statiques — même règle que TvSkeletonRails.
    final bool animate = !MediaQuery.of(context).disableAnimations;
    Widget row() => Container(
          height: 64,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
          ),
        );
    final Widget rows = Column(
      children: <Widget>[for (int i = 0; i < 6; i++) row()],
    );
    if (!animate) return rows;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9)
          .animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut)),
      child: rows,
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
    this.progress,
    this.autofocus = false,
  });
  final VodEpisode episode;
  final VoidCallback onPlay;

  /// Fraction déjà vue (0..1) — null si l'épisode n'a pas de reprise en
  /// cours. Affiche un fin filet doré sous le titre (repère « entamé »).
  final double? progress;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: onPlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            // Vignette 16:9 de l'épisode (info.movie_image du panel) —
            // décodage borné, repli discret (pas d'image = pas de trou :
            // un cadre sombre avec l'icône lecture suffit).
            ClipRRect(
              borderRadius: BorderRadius.circular(TvTokens.rSmall),
              child: SizedBox(
                width: 96,
                height: 54,
                child: (episode.posterUrl == null || episode.posterUrl!.isEmpty)
                    ? const ColoredBox(
                        color: TvTokens.tile,
                        child: Icon(Icons.movie_outlined,
                            size: 20, color: TvTokens.mutedDim),
                      )
                    : CachedNetworkImage(
                        imageUrl: episode.posterUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 192,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, __) =>
                            const ColoredBox(color: TvTokens.tile),
                        errorWidget: (_, __, ___) => const ColoredBox(
                          color: TvTokens.tile,
                          child: Icon(Icons.movie_outlined,
                              size: 20, color: TvTokens.mutedDim),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: TvDimens.title,
                          fontWeight: FontWeight.w600,
                          color: TvTokens.text)),
                  // Barre de reprise (façon Netflix) : même pattern
                  // Stack + FractionallySizedBox que le lecteur — rien
                  // n'est construit quand il n'y a pas de reprise.
                  if (progress != null) ...<Widget>[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(
                          children: <Widget>[
                            Container(color: Colors.white24),
                            FractionallySizedBox(
                              // Jamais < 4 % : une reprise toute fraîche
                              // doit rester visible.
                              widthFactor: progress!.clamp(0.04, 1.0),
                              child: Container(
                                decoration: const BoxDecoration(
                                    gradient: TvTokens.ctaGradient),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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
