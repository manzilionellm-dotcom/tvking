// =========================================================
//  cinema_screen.dart — CINÉMA mobile (Films · Séries · Téléchargés)
// =========================================================
//  Le pendant TÉLÉPHONE du Cinéma TV refondu (2026-07-17) : même moteur
//  de données (VodRepository / SeriesRepository / PlaybackPositionRepository
//  / VodDownloadService — tous partagés), mais une UI TACTILE :
//    • onglet FILMS : rangée « Continuer à regarder », « Téléchargés »,
//      puis une rangée d'affiches par catégorie — tap = fiche film ;
//    • onglet SÉRIES : pareil, tap = fiche série (saisons/épisodes) ;
//    • onglet TÉLÉCHARGÉS : la file complète (lecture hors-ligne en un
//      tap, pause/reprise, interrupteur Téléchargements intelligents,
//      espace libre).
//
//  Avant cet écran, le mobile n'avait PAS de Cinéma : films et séries
//  étaient de simples catégories IPTV lancées brutes dans le lecteur.
//  Les textes réutilisent les clés l10n déjà traduites pour la TV (mêmes
//  libellés = même langage produit sur les deux mondes).
// =========================================================
import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/curation/title_curator.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../channels/domain/channel.dart';
import '../../player/presentation/play_channel.dart';
import '../data/playback_position_repository.dart';
import '../data/series_repository.dart';
import '../data/vod_download_service.dart';
import '../data/vod_novelty_service.dart';
import '../data/vod_repository.dart';
import '../data/vod_taste.dart';
import '../domain/vod_movie.dart';
import '../../tv/core/vod_titles.dart';
import '../domain/vod_series.dart';
import 'movie_detail_screen.dart';
import 'series_detail_screen.dart';

/// Largeur d'affiche ADAPTATIVE des rangées du Cinéma : 96 dp sur
/// téléphone (rendu portrait STRICTEMENT inchangé), 124 dp sur tablette
/// (shortestSide ≥ 600 dp) où 96 dp paraissait minuscule. La taille est
/// PLAFONNÉE (jamais proportionnelle à l'écran) : pas de jaquettes
/// géantes étirées en paysage — les rangées affichent simplement plus
/// d'affiches côte à côte.
double _posterWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600 ? 124.0 : 96.0;

/// Hauteur assortie : même ratio d'affiche 96×140 que le design portrait.
double _posterHeight(double width) => width * 140 / 96;

class CinemaScreen extends StatefulWidget {
  const CinemaScreen({super.key, this.initialTab = 0});

  /// 0 = Films, 1 = Séries, 2 = Téléchargés (le rayon tapé dans l'accueil
  /// ouvre directement le bon onglet).
  final int initialTab;

  @override
  State<CinemaScreen> createState() => _CinemaScreenState();
}

class _CinemaScreenState extends State<CinemaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
      length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));

  List<VodMovie> _movies = const <VodMovie>[];
  List<VodSeries> _series = const <VodSeries>[];
  bool _loading = true;
  // NOUVEAUTÉS (parité TV) : ids films/séries apparus depuis la dernière
  // visite → rangée « Nouveautés » + pastille NOUVEAU.
  Set<String> _newMovieIds = <String>{};
  Set<String> _newSeriesIds = <String>{};

  @override
  void initState() {
    super.initState();
    // Rafraîchissement silencieux (même règle que la TV) : cache disque
    // d'abord, mise à jour sans spinner quand le réseau répond.
    VodRepository.instance.addListener(_reload);
    SeriesRepository.instance.addListener(_reload);
    VodDownloadService.instance.addListener(_onDownloadsChanged);
    _load();
  }

  @override
  void dispose() {
    VodRepository.instance.removeListener(_reload);
    SeriesRepository.instance.removeListener(_reload);
    VodDownloadService.instance.removeListener(_onDownloadsChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) _load(silent: true);
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted && !silent) setState(() => _loading = true);
    final List<VodMovie> movies = await VodRepository.instance.fetchMovies();
    final List<VodSeries> series =
        await SeriesRepository.instance.fetchSeries();
    await PlaybackPositionRepository.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _movies = movies;
      _series = series;
      _loading = false;
    });
    // Nouveautés (films + séries) en arrière-plan — parité TV.
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    VodNoveltyService.instance
        .reconcileMovies(movies.map((VodMovie m) => m.id), nowMs: nowMs)
        .then((Set<String> f) {
      if (mounted) setState(() => _newMovieIds = f);
    });
    VodNoveltyService.instance
        .reconcileSeries(series.map((VodSeries s) => s.id), nowMs: nowMs)
        .then((Set<String> f) {
      if (mounted) setState(() => _newSeriesIds = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(context.l10n.catFilterMovies,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: <Widget>[
            Tab(text: context.l10n.catFilterMovies),
            Tab(text: context.l10n.catFilterSeries),
            Tab(text: context.l10n.tvDlRail),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[
          _FilmsTab(
              movies: _movies, loading: _loading, newIds: _newMovieIds),
          _SeriesTab(
              series: _series, loading: _loading, newIds: _newSeriesIds),
          const _DownloadsTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Onglet FILMS — rangées d'affiches façon Netflix (tactile)
// ---------------------------------------------------------------------------

class _FilmsTab extends StatelessWidget {
  const _FilmsTab(
      {required this.movies,
      required this.loading,
      this.newIds = const <String>{}});
  final List<VodMovie> movies;
  final bool loading;

  /// Ids des films NOUVEAUX (parité TV) → rangée « Nouveautés » + badge.
  final Set<String> newIds;

  @override
  Widget build(BuildContext context) {
    if (loading && movies.isEmpty) {
      return const _CinemaSkeleton();
    }
    if (movies.isEmpty) {
      return _EmptyState(text: context.l10n.tvFilmsEmpty);
    }

    // « Continuer à regarder » : positions de reprise croisées au catalogue.
    final PlaybackPositionRepository positions =
        PlaybackPositionRepository.instance;
    final Map<String, VodMovie> byId = <String, VodMovie>{
      for (final VodMovie m in movies) m.id: m,
    };
    final List<VodMovie> resume = <VodMovie>[
      for (final PlaybackPosition e in positions.entries)
        if (!e.isEpisode && byId.containsKey(e.key)) byId[e.key]!,
    ];

    // « Téléchargés » : contenus prêts hors-ligne (films uniquement ici —
    // les épisodes vivent dans l'onglet Téléchargés et la fiche série).
    final List<VodMovie> downloaded = <VodMovie>[
      for (final VodDownload d in VodDownloadService.instance.all)
        if (d.isComplete && !d.isEpisode && byId.containsKey(d.id))
          byId[d.id]!,
    ];

    // Rangées par catégorie (ordre d'apparition du catalogue).
    final List<String> cats = <String>[];
    final Map<String, List<VodMovie>> byCat = <String, List<VodMovie>>{};
    for (final VodMovie m in movies) {
      final String c = m.category.trim().isEmpty
          ? context.l10n.tvOthers
          : m.category.trim();
      (byCat[c] ??= (() {
        cats.add(c);
        return <VodMovie>[];
      })())
          .add(m);
    }

    // NOUVEAUTÉS (parité TV).
    final List<VodMovie> newMovies = newIds.isEmpty
        ? const <VodMovie>[]
        : <VodMovie>[
            for (final VodMovie m in movies)
              if (newIds.contains(m.id)) m,
          ].take(24).toList(growable: false);

    // AFFINITÉ (goût) depuis l'historique de reprise → score « % pour vous »
    // et rangée « Parce que vous avez regardé ».
    final Map<String, double> affinity =
        VodTaste.affinity(recent: resume, watchlist: const <VodMovie>[]);
    final double maxAffinity = affinity.isEmpty
        ? 0
        : affinity.values.reduce((double a, double b) => a > b ? a : b);
    List<VodMovie> because = const <VodMovie>[];
    String becauseTitle = '';
    if (resume.isNotEmpty) {
      final VodMovie seed = resume.first;
      final String cat = seed.category.trim();
      if (cat.isNotEmpty) {
        final Set<String> seen = resume.map((VodMovie m) => m.id).toSet();
        because = <VodMovie>[
          for (final VodMovie m in (byCat[cat] ?? const <VodMovie>[]))
            if (!seen.contains(m.id)) m,
        ].take(24).toList(growable: false);
        becauseTitle = context.l10n.tvRailBecause(VodTitles.clean(seed.name));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        if (resume.isNotEmpty)
          _PosterRail(
            title: context.l10n.tvRailContinueWatching,
            movies: resume,
            progressFor: (VodMovie m) => positions.progressFor(m.id),
          ),
        if (newMovies.isNotEmpty)
          _PosterRail(
              title: context.l10n.tvRailNew,
              movies: newMovies,
              newIds: newIds,
              affinity: affinity,
              maxAffinity: maxAffinity),
        if (because.isNotEmpty)
          _PosterRail(
              title: becauseTitle,
              movies: because,
              affinity: affinity,
              maxAffinity: maxAffinity),
        if (downloaded.isNotEmpty)
          _PosterRail(title: context.l10n.tvDlRail, movies: downloaded),
        for (final String c in cats)
          _PosterRail(
              title: c,
              movies: byCat[c]!,
              newIds: newIds,
              affinity: affinity,
              maxAffinity: maxAffinity),
      ],
    );
  }
}

/// Une rangée horizontale d'affiches. Tap = fiche film.
class _PosterRail extends StatelessWidget {
  const _PosterRail({
    required this.title,
    required this.movies,
    this.progressFor,
    this.newIds = const <String>{},
    this.affinity = const <String, double>{},
    this.maxAffinity = 0,
  });
  final String title;
  final List<VodMovie> movies;
  final double? Function(VodMovie)? progressFor;
  final Set<String> newIds;
  final Map<String, double> affinity;
  final double maxAffinity;

  @override
  Widget build(BuildContext context) {
    // Hauteur du rail = hauteur d'affiche (adaptative) + libellés (32 dp,
    // comme le 172 − 140 du design portrait d'origine).
    final double posterH = _posterHeight(_posterWidth(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Text(title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.textTertiary)),
        ),
        SizedBox(
          height: posterH + 32,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: movies.length,
            itemBuilder: (BuildContext context, int i) => _PosterCard(
              movie: movies[i],
              progress: progressFor?.call(movies[i]),
              isNew: newIds.contains(movies[i].id),
              matchPercent: VodTaste.matchPercent(movies[i],
                  affinity: affinity, maxAffinity: maxAffinity),
            ),
          ),
        ),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard(
      {required this.movie,
      this.progress,
      this.isNew = false,
      this.matchPercent});
  final VodMovie movie;
  final double? progress;
  final bool isNew;
  final int? matchPercent;

  @override
  Widget build(BuildContext context) {
    // Taille d'affiche adaptative (96 dp téléphone / 124 dp tablette,
    // plafonnée) — voir _posterWidth.
    final double posterW = _posterWidth(context);
    final double posterH = _posterHeight(posterW);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (_) => MovieDetailScreen(movie: movie)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: posterW,
                height: posterH,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _poster(movie.posterUrl,
                        title: movie.name,
                        memCacheWidth: posterW.round() * 2),
                    // Filet de progression (repère « entamé », comme la TV).
                    if (progress != null)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          height: 4,
                          child: Stack(children: <Widget>[
                            Container(color: Colors.white24),
                            FractionallySizedBox(
                              widthFactor: progress!.clamp(0.04, 1.0),
                              child: Container(color: AppColors.accent),
                            ),
                          ]),
                        ),
                      ),
                    // Pastille NOUVEAU (parité TV).
                    if (isNew)
                      Positioned(
                        top: 5,
                        left: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(context.l10n.tvBadgeNew,
                              style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (matchPercent != null)
              SizedBox(
                width: posterW,
                child: Text(context.l10n.tvMatchPercent(matchPercent!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent)),
              ),
            SizedBox(
              width: posterW,
              child: Text(VodTitles.clean(movie.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Affiche avec décodage BORNÉ ([memCacheWidth] px : 192 par défaut,
/// soit 2× les 96 dp du téléphone ; les affiches tablette passent 2× leur
/// largeur adaptative) — la même règle mémoire que partout ailleurs dans
/// l'app.
/// Affiche (ou repli LISIBLE quand la source n'a pas de jaquette) : au lieu
/// d'une carte grise anonyme, on écrit le TITRE dessus (comme la TV / Netflix
/// — corrige les rangées « Nouveautés » qui semblaient vides).
Widget _poster(String? url, {String? title, int memCacheWidth = 192}) {
  Widget fallback() => ColoredBox(
        color: AppColors.surface,
        child: (title == null || title.isEmpty)
            ? const Center(
                child: Icon(Icons.movie_outlined,
                    size: 28, color: AppColors.textMuted))
            : Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.movie_outlined,
                        size: 20, color: AppColors.textMuted),
                    const SizedBox(height: 6),
                    Text(VodTitles.clean(title),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
      );
  if (url == null || url.isEmpty) return fallback();
  return CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    memCacheWidth: memCacheWidth,
    fadeInDuration: const Duration(milliseconds: 150),
    placeholder: (_, __) => const ColoredBox(color: AppColors.surface),
    errorWidget: (_, __, ___) => fallback(),
  );
}

// ---------------------------------------------------------------------------
//  Onglet SÉRIES
// ---------------------------------------------------------------------------

class _SeriesTab extends StatelessWidget {
  const _SeriesTab(
      {required this.series,
      required this.loading,
      this.newIds = const <String>{}});
  final List<VodSeries> series;
  final bool loading;

  /// Ids des séries NOUVELLES (parité TV) → pastille NOUVEAU.
  final Set<String> newIds;

  @override
  Widget build(BuildContext context) {
    if (loading && series.isEmpty) return const _CinemaSkeleton();
    if (series.isEmpty) {
      return _EmptyState(text: context.l10n.tvNoSeries);
    }
    final List<String> cats = <String>[];
    final Map<String, List<VodSeries>> byCat = <String, List<VodSeries>>{};
    for (final VodSeries s in series) {
      final String c = s.category.trim().isEmpty
          ? context.l10n.tvOthers
          : s.category.trim();
      (byCat[c] ??= (() {
        cats.add(c);
        return <VodSeries>[];
      })())
          .add(s);
    }
    // Taille d'affiche adaptative (96 dp téléphone / 124 dp tablette,
    // plafonnée) — même règle que l'onglet Films, voir _posterWidth.
    final double posterW = _posterWidth(context);
    final double posterH = _posterHeight(posterW);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        for (final String c in cats)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                child: Text(TitleCurator.curateCategory(c).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: AppColors.textTertiary)),
              ),
              SizedBox(
                height: posterH + 32,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: byCat[c]!.length,
                  itemBuilder: (BuildContext context, int i) {
                    final VodSeries s = byCat[c]![i];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                SeriesDetailScreen(series: s)),
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: posterW,
                                height: posterH,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: <Widget>[
                                    _poster(s.posterUrl,
                                        title: s.name,
                                        memCacheWidth: posterW.round() * 2),
                                    if (newIds.contains(s.id))
                                      Positioned(
                                        top: 5,
                                        left: 5,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.accent,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(context.l10n.tvBadgeNew,
                                              style: const TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.white)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: posterW,
                              child: Text(VodTitles.clean(s.name),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Onglet TÉLÉCHARGÉS — la file complète + intelligence
// ---------------------------------------------------------------------------

class _DownloadsTab extends StatefulWidget {
  const _DownloadsTab();

  @override
  State<_DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends State<_DownloadsTab> {
  int? _freeBytes;

  @override
  void initState() {
    super.initState();
    VodDownloadService.instance.load();
    _refreshFree();
  }

  void _refreshFree() {
    VodDownloadService.instance.freeSpace().then((int? v) {
      if (mounted && v != _freeBytes) setState(() => _freeBytes = v);
    });
  }

  void _playOffline(VodDownload d) {
    unawaited(playChannel(
      context,
      Channel(
        id: d.id, // id d'ORIGINE : reprise partagée online/hors-ligne
        name: d.name,
        category: d.category,
        streamUrl: Uri.file(d.filePath).toString(),
        isLive: false,
        logoUrl: d.posterUrl,
      ),
    ));
  }

  void _onTap(VodDownload d) {
    final VodDownloadService dl = VodDownloadService.instance;
    switch (d.status) {
      case VodDownloadStatus.done:
        _playOffline(d);
      case VodDownloadStatus.downloading:
        unawaited(dl.pause(d.id));
      case VodDownloadStatus.paused:
      case VodDownloadStatus.error:
      case VodDownloadStatus.queued:
      case VodDownloadStatus.noSpace:
        unawaited(dl.resume(d.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VodDownloadService.instance,
      builder: (BuildContext context, _) {
        final VodDownloadService dl = VodDownloadService.instance;
        final List<VodDownload> items = dl.all;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            // Interrupteur Téléchargements intelligents + espace libre.
            SwitchListTile(
              value: dl.smartEnabled,
              onChanged: (bool v) => dl.setSmartEnabled(v),
              activeTrackColor: AppColors.accent,
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.tvDlSmart,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              subtitle: Text(
                  _freeBytes == null
                      ? context.l10n.tvDlSmartOn
                      : context.l10n
                          .tvDlFree(VodDownloadService.fmtBytes(_freeBytes!)),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textTertiary)),
            ),
            // « Télécharger pendant que je regarde » (façon YouTube) : OFF par
            // défaut car cela ouvre une 2ᵉ connexion réseau.
            SwitchListTile(
              value: dl.watchAndSaveEnabled,
              onChanged: (bool v) => dl.setWatchAndSaveEnabled(v),
              activeTrackColor: AppColors.accent,
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.tvDlWatchSave,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              subtitle: Text(
                  dl.watchAndSaveEnabled
                      ? context.l10n.tvDlWatchSaveOn
                      : context.l10n.tvDlWatchSaveOff,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textTertiary)),
            ),
            const Divider(color: AppColors.ash, height: 24),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: _EmptyState(text: context.l10n.tvDownloadsEmptyHelp),
              ),
            for (final VodDownload d in items)
              _DownloadTile(
                d: d,
                onTap: () => _onTap(d),
                onDelete: () {
                  unawaited(dl.remove(d.id));
                  _refreshFree();
                },
              ),
          ],
        );
      },
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile(
      {required this.d, required this.onTap, required this.onDelete});
  final VodDownload d;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final int pct = (d.progress * 100).round();
    final String sub = switch (d.status) {
      VodDownloadStatus.done => context.l10n
          .tvDownloadReady(VodDownloadService.fmtBytes(d.totalBytes)),
      VodDownloadStatus.downloading => context.l10n.tvDownloadInProgress(pct),
      VodDownloadStatus.paused => context.l10n.tvDownloadPausedAt(pct),
      VodDownloadStatus.error => context.l10n.tvDownloadFailed,
      VodDownloadStatus.queued => context.l10n.tvDownloadQueued,
      VodDownloadStatus.noSpace => context.l10n.tvDlNoSpace,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: 46, height: 64, child: _poster(d.posterUrl)),
      ),
      title: Text(
          d.isEpisode && d.groupName.isNotEmpty
              ? '${VodTitles.clean(d.groupName)} — ${d.name}'
              : VodTitles.clean(d.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(sub,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textTertiary)),
          if (d.status == VodDownloadStatus.downloading ||
              d.status == VodDownloadStatus.paused) ...<Widget>[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 4,
                child: Stack(children: <Widget>[
                  Container(color: Colors.white12),
                  FractionallySizedBox(
                    widthFactor: d.progress,
                    child: Container(color: AppColors.accent),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded,
            color: AppColors.textTertiary),
        onPressed: onDelete,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Communs
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.movie_outlined,
                size: 44, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}

/// Squelette « respirant » (aucun spinner — même règle que la TV).
class _CinemaSkeleton extends StatelessWidget {
  const _CinemaSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (int r = 0; r < 3; r++) ...<Widget>[
          Container(
              width: 120,
              height: 12,
              margin: const EdgeInsets.only(top: 18, bottom: 12),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6))),
          SizedBox(
            height: 150,
            child: Row(children: <Widget>[
              for (int i = 0; i < 4; i++)
                Container(
                    width: 96,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10))),
            ]),
          ),
        ],
      ],
    );
  }
}
