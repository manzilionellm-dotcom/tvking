// =========================================================
//  series_detail_screen.dart — Fiche SÉRIE mobile (saisons + épisodes)
// =========================================================
//  Le pendant téléphone de la fiche série TV : en-tête (affiche, titre,
//  synopsis), puces de SAISONS, bouton « Télécharger la saison » (mode
//  voyage), liste d'ÉPISODES avec vignette + progression + état de
//  téléchargement. Tap = lecture (la SAISON ENTIÈRE part en zapPlaylist →
//  l'« À suivre » du lecteur enchaîne les épisodes, et les téléchargements
//  intelligents recyclent l'espace en route). Appui long = télécharger /
//  pause / retirer l'épisode.
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
import '../data/series_repository.dart';
import '../data/vod_download_service.dart';
import '../domain/vod_series.dart';
import '../../tv/core/vod_titles.dart';

class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({super.key, required this.series});
  final VodSeries series;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  List<VodEpisode> _episodes = const <VodEpisode>[];
  bool _loading = true;
  bool _failed = false; // le chargement a échoué / expiré (≠ « 0 épisode »)
  int? _season;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  /// Charge les épisodes SANS JAMAIS rester bloqué : timeout dur + capture
  /// d'erreur. Avant, un `.then` sans `catchError`/timeout laissait la fiche
  /// figée sur le squelette si la source répondait mal (bug terrain
  /// 2026-07-18 : « ça bugue sur série »).
  Future<void> _loadEpisodes() async {
    if (mounted) setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final List<VodEpisode> eps = await SeriesRepository.instance
          .fetchEpisodes(widget.series.id)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _episodes = eps;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[SeriesDetail] fetchEpisodes: $e');
      if (!mounted) return;
      setState(() {
        _episodes = const <VodEpisode>[];
        _loading = false;
        _failed = true;
      });
    }
  }

  /// Épisode → Channel de lecture, fichier LOCAL substitué s'il est
  /// téléchargé (démarrage instantané, zéro connexion fournisseur).
  Channel _toChannel(VodEpisode e) {
    final String? local = VodDownloadService.instance.localFile(e.id);
    final String url = (local != null && File(local).existsSync())
        ? Uri.file(local).toString()
        : e.streamUrl;
    return Channel(
      id: e.id,
      name: '${e.tag} · ${e.title}',
      category: widget.series.name,
      streamUrl: url,
      isLive: false,
      logoUrl: e.posterUrl ?? widget.series.posterUrl,
    );
  }

  void _playEpisode(List<VodEpisode> seasonEps, int index) {
    // TOUTE la saison en zapPlaylist → l'« À suivre » du lecteur mobile
    // enchaîne le vrai épisode suivant (et la chaîne intelligente sait
    // quoi télécharger/supprimer à la fin de chaque épisode).
    final List<Channel> list = seasonEps
        .map(_toChannel)
        .toList(growable: false);
    unawaited(playChannel(context, list[index], zapPlaylist: list));
  }

  void _toggleEpisodeDownload(VodEpisode e) {
    final VodDownloadService dl = VodDownloadService.instance;
    final VodDownload? d = dl.byId(e.id);
    if (d == null) {
      unawaited(dl.enqueue(
        id: e.id,
        name: '${e.tag} · ${e.title}',
        streamUrl: e.streamUrl,
        posterUrl: e.posterUrl ?? widget.series.posterUrl,
        containerExt: e.containerExt,
        isEpisode: true,
        groupName: widget.series.name,
      ));
    } else if (d.isComplete) {
      unawaited(dl.remove(e.id));
    } else if (d.status == VodDownloadStatus.downloading ||
        d.status == VodDownloadStatus.queued) {
      unawaited(dl.pause(e.id));
    } else {
      unawaited(dl.resume(e.id));
    }
  }

  /// « Mode voyage » : toute la saison en file (idempotent, cf. TV).
  void _downloadSeason(List<VodEpisode> seasonEps) {
    final VodDownloadService dl = VodDownloadService.instance;
    for (final VodEpisode e in seasonEps) {
      final VodDownload? existing = dl.byId(e.id);
      final bool retryable = existing == null ||
          existing.status == VodDownloadStatus.paused ||
          existing.status == VodDownloadStatus.error ||
          existing.status == VodDownloadStatus.noSpace;
      if (!retryable) continue;
      unawaited(dl.enqueue(
        id: e.id,
        name: '${e.tag} · ${e.title}',
        streamUrl: e.streamUrl,
        posterUrl: e.posterUrl ?? widget.series.posterUrl,
        containerExt: e.containerExt,
        isEpisode: true,
        groupName: widget.series.name,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Saisons présentes, triées ; la saison affichée = choisie ou première.
    final List<int> seasons =
        _episodes.map((VodEpisode e) => e.season).toSet().toList()..sort();
    final int currentSeason =
        _season ?? (seasons.isEmpty ? 1 : seasons.first);
    final List<VodEpisode> seasonEps = _episodes
        .where((VodEpisode e) => e.season == currentSeason)
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(VodTitles.clean(widget.series.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ),
      body: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                // Squelette minimal (pas de spinner central géant) : trois
                // lignes fantômes le temps du get_series_info.
                child: _EpisodesSkeleton(),
              ),
            )
          : _episodes.isEmpty
              // ÉTAT VIDE / ÉCHEC (jamais figé sur le squelette) : message
              // clair + bouton Réessayer. _failed distingue une erreur
              // réseau d'une série réellement sans épisodes.
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                            _failed
                                ? Icons.wifi_off_rounded
                                : Icons.video_library_outlined,
                            size: 46,
                            color: AppColors.textMuted),
                        const SizedBox(height: 14),
                        Text(
                          _failed
                              ? context.l10n.tvSeriesLoadFailed
                              : context.l10n.tvNoSeries,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 15, color: AppColors.textSecondary),
                        ),
                        if (_failed) ...<Widget>[
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _loadEpisodes,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(context.l10n.tvRetry),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                if (widget.series.plot != null &&
                    widget.series.plot!.isNotEmpty) ...<Widget>[
                  Text(widget.series.plot!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 14),
                ],
                if (seasons.length > 1) ...<Widget>[
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: seasons.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 8),
                      itemBuilder: (BuildContext context, int i) {
                        final int s = seasons[i];
                        final bool sel = s == currentSeason;
                        return ChoiceChip(
                          label: Text(context.l10n.tvSeriesSeason(s)),
                          selected: sel,
                          selectedColor: AppColors.accent,
                          labelStyle: TextStyle(
                              color: sel
                                  ? Colors.white
                                  : AppColors.textSecondary),
                          onSelected: (_) =>
                              setState(() => _season = s),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // ----- MODE VOYAGE : la saison en un geste -----
                ListenableBuilder(
                  listenable: VodDownloadService.instance,
                  builder: (BuildContext context, _) {
                    final int remaining = seasonEps
                        .where((VodEpisode e) => !(VodDownloadService
                                .instance
                                .byId(e.id)
                                ?.isComplete ??
                            false))
                        .length;
                    final bool done = remaining == 0;
                    return OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: done
                            ? AppColors.textMuted
                            : AppColors.accent,
                        side: BorderSide(
                            color: done
                                ? AppColors.ash
                                : AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed:
                          done ? null : () => _downloadSeason(seasonEps),
                      icon: Icon(done
                          ? Icons.download_done_rounded
                          : Icons.download_for_offline_rounded),
                      label: Text(done
                          ? context.l10n.tvDlSeasonDone
                          : context.l10n.tvDlSeason(remaining)),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(context.l10n.tvDlEpisodeHint,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                // ----- Épisodes -----
                ListenableBuilder(
                  listenable: VodDownloadService.instance,
                  builder: (BuildContext context, _) => Column(
                    children: <Widget>[
                      for (int i = 0; i < seasonEps.length; i++)
                        _EpisodeTile(
                          episode: seasonEps[i],
                          fallbackPoster: widget.series.posterUrl,
                          progress: PlaybackPositionRepository.instance
                              .progressFor(seasonEps[i].id),
                          download: VodDownloadService.instance
                              .byId(seasonEps[i].id),
                          onTap: () => _playEpisode(seasonEps, i),
                          onLongPress: () =>
                              _toggleEpisodeDownload(seasonEps[i]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.onTap,
    required this.onLongPress,
    this.fallbackPoster,
    this.progress,
    this.download,
  });

  final VodEpisode episode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String? fallbackPoster;
  final double? progress;
  final VodDownload? download;

  @override
  Widget build(BuildContext context) {
    final String? poster = episode.posterUrl ?? fallbackPoster;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 54,
                child: (poster == null || poster.isEmpty)
                    ? const ColoredBox(
                        color: AppColors.surface,
                        child: Icon(Icons.movie_outlined,
                            size: 20, color: AppColors.textMuted))
                    : CachedNetworkImage(
                        imageUrl: poster,
                        fit: BoxFit.cover,
                        memCacheWidth: 192,
                        // Même fade que les tuiles du cinéma (150 ms) —
                        // uniformité V1, le défaut (500 ms) traînait.
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, __) =>
                            const ColoredBox(color: AppColors.surface),
                        errorWidget: (_, __, ___) => const ColoredBox(
                            color: AppColors.surface,
                            child: Icon(Icons.movie_outlined,
                                size: 20, color: AppColors.textMuted)),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${episode.tag} · ${episode.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  if (progress != null) ...<Widget>[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: Stack(children: <Widget>[
                          Container(color: Colors.white12),
                          FractionallySizedBox(
                            widthFactor: progress!.clamp(0.04, 1.0),
                            child: Container(color: AppColors.accent),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (download != null) _badge(),
            const SizedBox(width: 6),
            const Icon(Icons.play_circle_outline_rounded,
                size: 24, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _badge() {
    switch (download!.status) {
      case VodDownloadStatus.done:
        return const Icon(Icons.download_done_rounded,
            size: 20, color: AppColors.editorialCream);
      case VodDownloadStatus.downloading:
        return Text('${(download!.progress * 100).round()} %',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.editorialCream));
      case VodDownloadStatus.paused:
        return const Icon(Icons.pause_circle_outline_rounded,
            size: 20, color: AppColors.textTertiary);
      case VodDownloadStatus.queued:
        return const Icon(Icons.schedule_rounded,
            size: 20, color: AppColors.textTertiary);
      case VodDownloadStatus.error:
      case VodDownloadStatus.noSpace:
        return const Icon(Icons.error_outline_rounded,
            size: 20, color: AppColors.textTertiary);
    }
  }
}

/// Trois lignes fantômes pendant le get_series_info (pas de roue géante).
class _EpisodesSkeleton extends StatelessWidget {
  const _EpisodesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < 3; i++)
          Container(
            height: 54,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10)),
          ),
      ],
    );
  }
}
