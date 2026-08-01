// =========================================================
//  movie_detail_screen.dart — Fiche FILM mobile (tactile)
// =========================================================
//  Le pendant téléphone de tv_movie_detail_screen : l'affiche en héros,
//  titre + année/note, synopsis (get_vod_info, cache LRU du repo),
//  REGARDER / REPRENDRE (position exacte), TÉLÉCHARGER (moteur partagé
//  VodDownloadService — file sérielle + intelligence), et la rangée
//  « Dans le même genre » (même catégorie). Zéro logique nouvelle :
//  100 % branché sur les briques déjà testées côté TV.
// =========================================================
import 'dart:async' show unawaited;
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../channels/domain/channel.dart';
import '../../player/presentation/play_channel.dart';
import '../data/playback_position_repository.dart';
import '../data/recent_vod_repository.dart';
import '../data/vod_download_service.dart';
import '../data/vod_repository.dart';
import '../domain/vod_info.dart';
import '../domain/vod_movie.dart';
import '../../tv/core/vod_titles.dart';

class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movie});
  final VodMovie movie;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  VodInfo? _info;
  List<VodMovie> _similar = const <VodMovie>[];

  @override
  void initState() {
    super.initState();
    // Fiche enrichie (synopsis/backdrop/casting) en arrière-plan — l'écran
    // s'affiche IMMÉDIATEMENT avec ce que le catalogue sait déjà.
    VodRepository.instance.fetchInfo(widget.movie.id).then((VodInfo? info) {
      if (mounted && info != null) setState(() => _info = info);
    });
    _loadSimilar();
  }

  Future<void> _loadSimilar() async {
    // Même catégorie, sans le film courant (fetchMovies répond de mémoire).
    final List<VodMovie> all = await VodRepository.instance.fetchMovies();
    if (!mounted) return;
    setState(() {
      _similar = all
          .where((VodMovie m) =>
              m.category == widget.movie.category && m.id != widget.movie.id)
          .take(12)
          .toList(growable: false);
    });
  }

  void _play() {
    RecentVodRepository.instance.add(widget.movie);
    // HORS-LIGNE D'ABORD : film téléchargé → fichier local (démarrage
    // instantané, zéro connexion fournisseur). Sinon URL distante.
    final String? local =
        VodDownloadService.instance.localFile(widget.movie.id);
    final String url = (local != null && File(local).existsSync())
        ? Uri.file(local).toString()
        : widget.movie.streamUrl;
    unawaited(playChannel(
      context,
      Channel(
        id: widget.movie.id,
        name: widget.movie.name,
        category: widget.movie.category,
        streamUrl: url,
        isLive: false,
        logoUrl: widget.movie.posterUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final VodMovie m = widget.movie;
    final String? plot = _info?.plot;
    final String meta = <String>[
      if ((_info?.year ?? m.year) != null) (_info?.year ?? m.year)!,
      if (_info?.genre != null) _info!.genre!,
      if ((_info?.rating ?? m.rating) != null)
        '★ ${(_info?.rating ?? m.rating)!}',
    ].join('   ·   ');

    // Position de reprise → le bouton principal devient « Reprendre ».
    final Duration? resume =
        PlaybackPositionRepository.instance.positionFor(m.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          // ----- Héros : backdrop paysage si dispo, sinon l'affiche -----
          Stack(
            children: <Widget>[
              AspectRatio(
                aspectRatio: 16 / 9,
                child: (_info?.backdropUrl != null &&
                        _info!.backdropUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: _info!.backdropUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 960,
                        // Le DISQUE aussi est borné : sans ça, la box stocke l'affiche
                        // en taille d'origine (2000 px) alors qu'on ne l'affiche jamais
                        // au-delà de 960 px — sur un catalogue de 100 000 titres, c'est
                        // des gigaoctets pour rien.
                        maxWidthDiskCache: 960,
                        placeholder: (_, __) =>
                            const ColoredBox(color: AppColors.surface),
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: AppColors.surface),
                      )
                    : (m.posterUrl == null || m.posterUrl!.isEmpty)
                        ? const ColoredBox(color: AppColors.surface)
                        : CachedNetworkImage(
                            imageUrl: m.posterUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 960,
                            // Le DISQUE aussi est borné : sans ça, la box stocke l'affiche
                            // en taille d'origine (2000 px) alors qu'on ne l'affiche jamais
                            // au-delà de 960 px — sur un catalogue de 100 000 titres, c'est
                            // des gigaoctets pour rien.
                            maxWidthDiskCache: 960,
                            placeholder: (_, __) =>
                                const ColoredBox(color: AppColors.surface),
                            errorWidget: (_, __, ___) =>
                                const ColoredBox(color: AppColors.surface),
                          ),
              ),
              // Voile bas → le titre reste lisible sur toute image.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.transparent,
                        AppColors.background.withValues(alpha: 0.85),
                        AppColors.background,
                      ],
                      stops: const <double>[0.4, 0.85, 1.0],
                    ),
                  ),
                ),
              ),
              // Retour.
              Positioned(
                top: MediaQuery.paddingOf(context).top + 4,
                left: 4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.textPrimary),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(VodTitles.clean(m.name),
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(meta,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textTertiary)),
                ],
                const SizedBox(height: 16),
                // ----- REGARDER / REPRENDRE + TÉLÉCHARGER -----
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _play,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          resume != null
                              ? context.l10n.tvResume
                              : context.l10n.tvWatch,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _DownloadButton(movie: m),
                  ],
                ),
                if (plot != null && plot.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 18),
                  Text(plot,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppColors.textSecondary)),
                ],
                if (_info?.cast != null && _info!.cast!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(_info!.cast!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textTertiary)),
                ],
                // ----- Dans le même genre -----
                if (_similar.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  Text(context.l10n.tvSimilar.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: AppColors.textTertiary)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 168,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _similar.length,
                      itemBuilder: (BuildContext context, int i) {
                        final VodMovie s = _similar[i];
                        return GestureDetector(
                          onTap: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    MovieDetailScreen(movie: s)),
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 96,
                                height: 140,
                                child: (s.posterUrl == null ||
                                        s.posterUrl!.isEmpty)
                                    ? const ColoredBox(
                                        color: AppColors.surface)
                                    : CachedNetworkImage(
                                        imageUrl: s.posterUrl!,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 192,
                                        // Le DISQUE aussi est borné : sans ça, la box stocke l'affiche
                                        // en taille d'origine (2000 px) alors qu'on ne l'affiche jamais
                                        // au-delà de 192 px — sur un catalogue de 100 000 titres, c'est
                                        // des gigaoctets pour rien.
                                        maxWidthDiskCache: 192,
                                        placeholder: (_, __) =>
                                            const ColoredBox(
                                                color: AppColors.surface),
                                        errorWidget: (_, __, ___) =>
                                            const ColoredBox(
                                                color: AppColors.surface),
                                      ),
                              ),
                            ),
                          ),
                        );
                      },
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

/// Bouton Télécharger contextuel — mêmes états que la TV (le moteur est
/// LE MÊME singleton : un téléchargement lancé au téléphone se retrouve
/// dans les mêmes états/écrans).
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
        VoidCallback onTap =
            () => VodDownloadService.instance.downloadMovie(movie);
        if (d != null) {
          switch (d.status) {
            case VodDownloadStatus.done:
              icon = Icons.download_done_rounded;
              label = context.l10n.tvDownloaded;
              onTap = () {};
            case VodDownloadStatus.downloading:
              icon = Icons.pause_rounded;
              label = '${(d.progress * 100).round()} %';
              onTap = () => VodDownloadService.instance.pause(movie.id);
            case VodDownloadStatus.paused:
            case VodDownloadStatus.error:
            case VodDownloadStatus.queued:
            case VodDownloadStatus.noSpace:
              icon = Icons.download_rounded;
              label = context.l10n.tvResume;
              onTap = () => VodDownloadService.instance.resume(movie.id);
          }
        }
        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.ash),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 20),
          label: Text(label),
        );
      },
    );
  }
}
