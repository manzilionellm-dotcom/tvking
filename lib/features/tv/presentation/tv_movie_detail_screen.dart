// =========================================================
//  tv_movie_detail_screen.dart — FICHE FILM 10-foot, façon Netflix
// =========================================================
//  La fiche qui s'ouvre quand on fait OK sur un film : backdrop plein
//  écran assombri, titre, métadonnées (année · durée · genre · note),
//  synopsis, casting, et les ACTIONS au D-pad (▶ Lecture / Reprendre,
//  Ma Liste, Télécharger). Retour = ferme la fiche.
//
//  DEUX TEMPS, JAMAIS D'ÉCRAN BLANC :
//    1. la fiche s'affiche IMMÉDIATEMENT avec les infos de la vignette
//       (nom, affiche, année, note) — celles du catalogue ;
//    2. `get_vod_info` (VodRepository.fetchInfo, cache LRU) arrive en
//       arrière-plan et ENRICHIT la fiche (synopsis, casting, backdrop…).
//       Serveur muet / source M3U / erreur → la fiche reste telle quelle
//       (fail-open), on ne bloque ni ne plante jamais.
//
//  REPRISE DE LECTURE : si PlaybackPositionRepository connaît une position
//  pour ce film, le bouton principal devient « Reprendre à 42:15 » et un
//  bouton secondaire « Reprendre du début » efface la position avant de
//  lancer (le lecteur, qui consulte le repo à l'ouverture, repart de 0).
//
//  ANTI-OOM (box 1 Go) : UNE seule image plein écran, décodée BORNÉE
//  (memCacheWidth) ; le repli sans backdrop est l'affiche FLOUTÉE décodée
//  toute petite (le flou masque la basse définition — literalement gratuit
//  en RAM), sinon le dégradé TvTokens. Aucun cache disque ajouté.
// =========================================================
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../vod/data/playback_position_repository.dart';
import '../../vod/data/recent_vod_repository.dart';
import '../../vod/data/vod_download_service.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/data/vod_watchlist_repository.dart';
import '../../vod/domain/vod_info.dart';
import '../../vod/domain/vod_movie.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_cine_route.dart';
import '../core/tv_tokens.dart';
import '../data/cine_perf.dart';
import 'tv_player_screen.dart';

class TvMovieDetailScreen extends StatefulWidget {
  const TvMovieDetailScreen({required this.movie, super.key});

  final VodMovie movie;

  @override
  State<TvMovieDetailScreen> createState() => _TvMovieDetailScreenState();
}

class _TvMovieDetailScreenState extends State<TvMovieDetailScreen> {
  /// Fiche riche (get_vod_info) — null tant que pas reçue / indisponible.
  VodInfo? _info;

  /// `true` tant que le fetch est en route → petites lignes squelette à la
  /// place du synopsis (la structure de la fiche, elle, est déjà là).
  bool _loadingInfo = true;

  /// Films de la MÊME catégorie (rail « Similaires ») — servis depuis le
  /// cache mémoire du VodRepository : zéro réseau, fiche toujours < 300 ms.
  List<VodMovie> _similar = const <VodMovie>[];

  @override
  void initState() {
    super.initState();
    // Budget « ouverture fiche < 300 ms (données en cache) » : chrono arrêté
    // à la première frame réellement affichée (cf. build).
    CinePerf.start(CinePerf.detailOpen);
    // Reprise : le bouton « Reprendre à 42:15 » se met à jour tout seul si
    // la position change (retour du lecteur). Filet ensureLoaded — le vrai
    // load() est branché au démarrage (main_tv).
    PlaybackPositionRepository.instance.addListener(_onExternalChange);
    PlaybackPositionRepository.instance.ensureLoaded();
    // « Ma Liste » : le ✓ du bouton suit le repo (toggle ici ou ailleurs).
    VodWatchlistRepository.instance.addListener(_onExternalChange);
    // Enrichissement en ARRIÈRE-PLAN : la fiche est déjà affichée avec les
    // infos de la vignette — get_vod_info ne fait que la compléter.
    VodRepository.instance.fetchInfo(widget.movie.id).then((VodInfo? info) {
      if (!mounted) return;
      setState(() {
        _info = info;
        _loadingInfo = false;
      });
    });
    // Rail « Similaires » : films de la même catégorie, depuis le CACHE du
    // catalogue (fetchMovies répond de mémoire — l'accueil vient d'y passer).
    _loadSimilar();
  }

  Future<void> _loadSimilar() async {
    final String cat = widget.movie.category.trim();
    if (cat.isEmpty) return;
    final List<VodMovie> all = await VodRepository.instance.fetchMovies();
    if (!mounted) return;
    setState(() {
      _similar = <VodMovie>[
        for (final VodMovie m in all)
          if (m.id != widget.movie.id && m.category.trim() == cat) m,
      ].take(15).toList(growable: false);
    });
  }

  @override
  void dispose() {
    CinePerf.cancel(CinePerf.detailOpen);
    PlaybackPositionRepository.instance.removeListener(_onExternalChange);
    VodWatchlistRepository.instance.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) setState(() {}); // les données sont relues dans build()
  }

  /// Adapte le film en Channel pour le lecteur — même logique HORS-LIGNE que
  /// l'onglet Films : si le film est téléchargé, on lit le FICHIER LOCAL
  /// (file://) au lieu du flux réseau (lecture en avion, démarrage instant).
  Channel _asChannel(VodMovie m) {
    final String? local = VodDownloadService.instance.localFile(m.id);
    final String url =
        (local != null) ? File(local).uri.toString() : m.streamUrl;
    return Channel(
      id: m.id,
      name: m.name,
      category: m.category,
      streamUrl: url,
      isLive: false,
      logoUrl: m.posterUrl,
    );
  }

  /// Lance la lecture. [fromStart] = « Reprendre du début » : on EFFACE la
  /// position mémorisée AVANT de pousser le lecteur — celui-ci consulte
  /// PlaybackPositionRepository à l'ouverture, donc sans entrée il part de
  /// zéro (aucune modif du lecteur nécessaire).
  Future<void> _play({bool fromStart = false}) async {
    if (fromStart) {
      await PlaybackPositionRepository.instance.markFinished(widget.movie.id);
    }
    if (!mounted) return;
    RecentVodRepository.instance.add(widget.movie);
    // Budget « Regarder → première frame < 2,5 s » : le chrono part de
    // L'APPUI (ici), le lecteur l'arrête à la première image affichée.
    CinePerf.start(CinePerf.playToFirstFrame);
    Navigator.of(context).push(
      TvCineRoute<void>(
        builder: (_) => TvPlayerScreen(
          channels: <Channel>[_asChannel(widget.movie)],
          startIndex: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VodMovie m = widget.movie;
    final VodInfo? info = _info;

    // Budget « ouverture fiche < 300 ms » : la fiche s'affiche dès la
    // première frame (structure + infos vignette) — c'est CETTE frame
    // qu'on mesure, pas l'enrichissement réseau qui suit en silence.
    if (CinePerf.isRunning(CinePerf.detailOpen)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CinePerf.end(CinePerf.detailOpen, detail: m.name);
      });
    }

    // Position de reprise éventuelle → bouton « Reprendre à 42:15 ».
    final PlaybackPosition? resume =
        PlaybackPositionRepository.instance.entryFor(m.id);
    final bool inList = VodWatchlistRepository.instance.contains(m.id);

    // Ligne de MÉTADONNÉES : année · durée · genre · ★ note — chaque champ
    // vient de la fiche riche si dispo, sinon de la vignette du catalogue.
    final String? year = info?.year ?? m.year;
    final String? rating = info?.rating ?? m.rating;
    final String meta = <String>[
      if (year != null && year.isNotEmpty) year,
      if (info?.durationSecs != null)
        VodInfo.formatDurationShort(info!.durationSecs!),
      if (info?.genre != null) info!.genre!,
      if (m.category.trim().isNotEmpty && info?.genre == null)
        m.category.trim(),
      if (rating != null && rating.isNotEmpty) '★ $rating',
    ].join('   ·   ');

    return Scaffold(
      backgroundColor: TvTokens.bg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // ----- FOND : backdrop plein écran (ou repli) -----
          _Backdrop(backdropUrl: info?.backdropUrl, posterUrl: m.posterUrl),
          // ----- SCRIM : dégradé sombre gauche→droite + bas, pour que le
          //  texte reste lisible sur n'importe quel backdrop (10-foot). -----
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Color(0xF208080A), // quasi opaque côté texte
                  Color(0xB008080A),
                  Color(0x3308080A), // le backdrop respire à droite
                ],
                stops: <double>[0.0, 0.45, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x0008080A), Color(0xCC08080A)],
                stops: <double>[0.55, 1.0],
              ),
            ),
          ),
          // ----- CONTENU (safe area 10-foot) -----
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: TvDimens.safeH, vertical: TvDimens.safeV),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                // Titre — gros, lisible à 3 m (TvTokens.display).
                Text(
                  m.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.display(TvDimens.displayM,
                      color: TvTokens.text),
                ),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(15,
                          weight: FontWeight.w600, color: TvTokens.muted)),
                ],
                const SizedBox(height: 14),
                // Synopsis (3-5 lignes) OU lignes squelette pendant le fetch.
                SizedBox(
                  width: 560, // colonne de lecture — jamais du bord au bord
                  child: _loadingInfo
                      ? const _SkeletonLines()
                      : (info?.plot != null
                          ? Text(
                              info!.plot!,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TvTokens.ui(15, color: TvTokens.text)
                                  .copyWith(height: 1.5),
                            )
                          : const SizedBox.shrink()),
                ),
                // Casting + réalisateur (une ligne chacun).
                if (info?.cast != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(context.l10n.tvDetailWithCast(info!.cast!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(14, color: TvTokens.muted)),
                ],
                if (info?.director != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(context.l10n.tvDetailByDirector(info!.director!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(14, color: TvTokens.muted)),
                ],
                const SizedBox(height: 22),
                // ----- ACTIONS (D-pad) — focus initial sur ▶ Lecture -----
                Row(
                  children: <Widget>[
                    _ActionButton(
                      icon: Icons.play_arrow_rounded,
                      label: resume != null
                          ? context.l10n
                              .tvResumeAt(VodInfo.formatClock(resume.position))
                          : context.l10n.tvWatch,
                      primary: true,
                      autofocus: true,
                      onSelect: _play,
                    ),
                    if (resume != null) ...<Widget>[
                      const SizedBox(width: 12),
                      _ActionButton(
                        icon: Icons.replay_rounded,
                        label: context.l10n.tvStartOver,
                        onSelect: () => _play(fromStart: true),
                      ),
                    ],
                    const SizedBox(width: 12),
                    _ActionButton(
                      icon: inList ? Icons.check_rounded : Icons.add_rounded,
                      label: inList
                          ? context.l10n.tvInMyList
                          : context.l10n.tvMyList,
                      onSelect: () =>
                          VodWatchlistRepository.instance.toggle(m),
                    ),
                    const SizedBox(width: 12),
                    _DownloadButton(movie: m),
                  ],
                ),
                // ----- SIMILAIRES (même catégorie, depuis le cache) -----
                //  Bande compacte façon Netflix sous les actions : flèche
                //  BAS depuis ▶ Lecture → premières affiches similaires.
                //  OK sur une affiche → nouvelle fiche (retour = celle-ci).
                if (_similar.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 20),
                  Text(
                    context.l10n.tvSimilar.toUpperCase(),
                    style: TvTokens.ui(12,
                        weight: FontWeight.w700,
                        color: TvTokens.mutedDim,
                        spacing: 1.6),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 128,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      addAutomaticKeepAlives: false,
                      itemExtent: 86,
                      itemCount: _similar.length,
                      itemBuilder: (BuildContext context, int i) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _SimilarCard(
                          movie: _similar[i],
                          onOpen: () {
                            // Remplace la fiche (pas d'empilement infini de
                            // routes en butinant de similaire en similaire).
                            Navigator.of(context).pushReplacement(
                              TvCineRoute<void>(
                                builder: (_) => TvMovieDetailScreen(
                                    movie: _similar[i]),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Petite affiche du rail « Similaires » (2:3 compacte, focusable).
class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.movie, required this.onOpen});
  final VodMovie movie;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    const Widget fallback = ColoredBox(
      color: TvTokens.tile,
      child: Icon(Icons.movie_rounded, size: 22, color: TvTokens.mutedDim),
    );
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TvTokens.rSmall),
        child: (movie.posterUrl == null || movie.posterUrl!.isEmpty)
            ? fallback
            : CachedNetworkImage(
                imageUrl: movie.posterUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 160,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

// =========================================================
//  FOND — backdrop plein écran, repli affiche floutée, repli dégradé
// =========================================================
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.backdropUrl, required this.posterUrl});

  final String? backdropUrl;
  final String? posterUrl;

  @override
  Widget build(BuildContext context) {
    // Dernier repli : le dégradé « cathédrale » du design system — la fiche
    // reste belle même sans aucune image (source M3U pauvre).
    const Widget gradientFallback =
        DecoratedBox(decoration: BoxDecoration(gradient: TvTokens.bgGradient));

    // Repli n°2 : l'AFFICHE floutée en fond (façon écran musique). Décodée
    // TOUTE PETITE (memCacheWidth 160) : le flou gomme la basse définition,
    // et on ne paie jamais un décodage plein écran pour un fond flou.
    Widget posterBlur() {
      final String? p = posterUrl;
      if (p == null || p.isEmpty) return gradientFallback;
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: CachedNetworkImage(
          imageUrl: p,
          fit: BoxFit.cover,
          memCacheWidth: 160,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (_, __) => gradientFallback,
          errorWidget: (_, __, ___) => gradientFallback,
        ),
      );
    }

    final String? b = backdropUrl;
    if (b == null || b.isEmpty) return posterBlur();
    // Backdrop plein écran : décodage BORNÉ à ~960 px de large (anti-OOM,
    // même règle que partout dans l'app) — largement net pour un fond.
    return CachedNetworkImage(
      imageUrl: b,
      fit: BoxFit.cover,
      memCacheWidth: 960,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, __) => posterBlur(),
      errorWidget: (_, __, ___) => posterBlur(),
    );
  }
}

// =========================================================
//  Squelette du synopsis — 3 lignes « fantômes » pendant get_vod_info
// =========================================================
//  Version minimale du pattern TvSkeletonRails : la fiche est déjà là
//  (titre, affiche, boutons), seul le synopsis « arrive » — pas besoin
//  d'animer, des barres translucides suffisent à dire « ça charge ».
class _SkeletonLines extends StatelessWidget {
  const _SkeletonLines();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => Container(
          width: width,
          height: 13,
          margin: const EdgeInsets.only(bottom: 9),
          decoration: BoxDecoration(
            color: TvTokens.card.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[bar(540), bar(500), bar(380)],
    );
  }
}

// =========================================================
//  Bouton d'action focusable (▶ Lecture / Ma Liste / Télécharger…)
//  Même langage visuel que les boutons de la vedette de l'onglet Films.
// =========================================================
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.primary = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? TvTokens.gold
            : (primary ? TvTokens.badgeBg : TvTokens.card);
        final Color fg = focused
            ? const Color(0xFF1A1206)
            : (primary ? TvTokens.goldBright : TvTokens.text);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border:
                Border.all(color: primary ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: fg)),
            ],
          ),
        );
      },
    );
  }
}

/// Bouton « Télécharger » : écoute VodDownloadService pour refléter l'état
/// en direct (Télécharger → % → ✓ Téléchargé) — même comportement que le
/// bouton de la vedette de l'onglet Films (OK : démarre / pause / reprend).
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.movie});
  final VodMovie movie;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VodDownloadService.instance,
      builder: (BuildContext context, _) {
        final VodDownload? d = VodDownloadService.instance.byId(movie.id);
        IconData icon = Icons.download_rounded;
        String label = context.l10n.tvDownload;
        VoidCallback onSelect =
            () => VodDownloadService.instance.downloadMovie(movie);
        if (d != null) {
          switch (d.status) {
            case VodDownloadStatus.done:
              icon = Icons.download_done_rounded;
              label = context.l10n.tvDownloaded;
              onSelect = () {};
            case VodDownloadStatus.downloading:
              icon = Icons.pause_rounded;
              label = context.l10n.tvPercent((d.progress * 100).round());
              onSelect = () => VodDownloadService.instance.pause(movie.id);
            case VodDownloadStatus.paused:
            case VodDownloadStatus.error:
            case VodDownloadStatus.queued:
            case VodDownloadStatus.noSpace:
              icon = Icons.download_rounded;
              label = context.l10n.tvResume;
              onSelect = () => VodDownloadService.instance.resume(movie.id);
          }
        }
        return _ActionButton(icon: icon, label: label, onSelect: onSelect);
      },
    );
  }
}
