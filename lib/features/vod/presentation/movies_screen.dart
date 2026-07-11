// =========================================================
//  movies_screen.dart — Films (catalogue VOD + téléchargés)
// =========================================================
//  2 onglets :
//   1. « Films »      → catalogue VOD du serveur. Chaque film : lecture
//                       en streaming + bouton Télécharger (hors-ligne).
//   2. « Téléchargés » → bibliothèque hors-ligne : progression,
//                       pause/reprise, lecture sans connexion, suppression.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/domain/channel.dart';
import '../../player/presentation/play_channel.dart';
import '../data/download_repository.dart';
import '../data/vod_repository.dart';
import '../domain/vod_movie.dart';

class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  late Future<List<VodMovie>> _moviesFuture;

  @override
  void initState() {
    super.initState();
    DownloadsRepository.instance.initialize();
    _moviesFuture = VodRepository.instance.fetchMovies();
  }

  void _reloadCatalogue() {
    setState(() {
      _moviesFuture = VodRepository.instance.fetchMovies(forceRefresh: true);
    });
  }

  // Lance la lecture (streaming) d'un film VOD.
  void _playMovie(VodMovie m) {
    playChannel(
      context,
      Channel(
        id: m.id,
        name: m.name,
        category: m.category,
        streamUrl: m.streamUrl,
        isLive: false,
        logoUrl: m.posterUrl,
      ),
      overrideTitle: m.name,
    );
  }

  // Lance la lecture HORS-LIGNE d'un film déjà téléchargé (fichier local).
  void _playOffline(Download d) {
    playChannel(
      context,
      Channel(
        id: d.id,
        name: d.name,
        // Catégorie purement décorative (affichée dans le player) —
        // on réutilise la clé existante moviesDownloaded.
        category: context.l10n.moviesDownloaded,
        streamUrl: d.filePath, // chemin local — media_kit l'ouvre direct
        isLive: false,
        logoUrl: d.posterUrl,
      ),
      overrideTitle: d.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: Text(context.l10n.moviesTitle),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: context.l10n.moviesTabMovies),
              Tab(text: context.l10n.moviesTabDownloads),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: context.l10n.moviesReloadTooltip,
              onPressed: _reloadCatalogue,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: TabBarView(
          children: <Widget>[
            _buildCatalogue(),
            _buildDownloads(),
          ],
        ),
      ),
    );
  }

  // ----- Onglet 1 : catalogue VOD -----
  Widget _buildCatalogue() {
    return FutureBuilder<List<VodMovie>>(
      future: _moviesFuture,
      builder: (BuildContext context, AsyncSnapshot<List<VodMovie>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<VodMovie> movies = snap.data ?? const <VodMovie>[];
        if (movies.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                context.l10n.moviesEmptyCatalogue,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        return StreamBuilder<List<Download>>(
          stream: DownloadsRepository.instance.stream,
          initialData: DownloadsRepository.instance.current,
          builder: (BuildContext context, AsyncSnapshot<List<Download>> dsnap) {
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: movies.length,
              itemBuilder: (BuildContext context, int i) {
                final VodMovie m = movies[i];
                final Download? d = DownloadsRepository.instance.byId(m.id);
                return _MovieRow(
                  movie: m,
                  download: d,
                  onPlay: () => _playMovie(m),
                  onDownload: () => DownloadsRepository.instance.start(m),
                );
              },
            );
          },
        );
      },
    );
  }

  // ----- Onglet 2 : téléchargés / en cours -----
  Widget _buildDownloads() {
    return StreamBuilder<List<Download>>(
      stream: DownloadsRepository.instance.stream,
      initialData: DownloadsRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<List<Download>> snap) {
        final List<Download> items = snap.data ?? const <Download>[];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                context.l10n.moviesEmptyDownloads,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (BuildContext context, int i) {
            final Download d = items[i];
            return _DownloadRow(
              download: d,
              onPlay: d.isDone ? () => _playOffline(d) : null,
              onPause: () => DownloadsRepository.instance.pause(d.id),
              onResume: () => DownloadsRepository.instance.resume(d.id),
              onDelete: () => DownloadsRepository.instance.delete(d.id),
            );
          },
        );
      },
    );
  }
}

class _MovieRow extends StatelessWidget {
  const _MovieRow({
    required this.movie,
    required this.download,
    required this.onPlay,
    required this.onDownload,
  });

  final VodMovie movie;
  final Download? download;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final bool done = download?.status == DownloadStatus.done;
    final bool busy = download?.status == DownloadStatus.downloading;
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 44,
            height: 60,
            child: movie.posterUrl != null
                ? Image.network(movie.posterUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _posterFallback())
                : _posterFallback(),
          ),
        ),
        title: Text(movie.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyLarge.copyWith(fontSize: 14)),
        subtitle: Text(movie.category,
            style: AppTextStyles.bodyMedium
                .copyWith(fontSize: 11, color: AppColors.textTertiary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: context.l10n.moviesPlayTooltip,
              onPressed: onPlay,
              icon: const Icon(Icons.play_circle_fill_rounded),
              color: AppColors.accent,
            ),
            IconButton(
              tooltip: done
                  ? context.l10n.moviesDownloaded
                  : busy
                      ? context.l10n.moviesDownloading
                      : context.l10n.moviesDownload,
              onPressed: (done || busy) ? null : onDownload,
              icon: Icon(
                done
                    ? Icons.download_done_rounded
                    : busy
                        ? Icons.downloading_rounded
                        : Icons.download_rounded,
              ),
            ),
          ],
        ),
        onTap: onPlay,
      ),
    );
  }

  Widget _posterFallback() => ColoredBox(
        color: AppColors.surfaceHigh,
        child: Icon(Icons.movie_outlined,
            color: AppColors.textTertiary, size: 22),
      );
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.download,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onDelete,
  });

  final Download download;
  final VoidCallback? onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onDelete;

  String _human(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final Download d = download;
    final String status;
    switch (d.status) {
      case DownloadStatus.done:
        status = context.l10n.moviesStatusDownloaded(_human(d.receivedBytes));
        break;
      case DownloadStatus.downloading:
        status = d.totalBytes > 0
            ? '${(d.progress * 100).toStringAsFixed(0)}% · ${_human(d.receivedBytes)} / ${_human(d.totalBytes)}'
            : context.l10n.moviesStatusDownloading(_human(d.receivedBytes));
        break;
      case DownloadStatus.paused:
        status = context.l10n.moviesStatusPaused(_human(d.receivedBytes));
        break;
      case DownloadStatus.error:
        status = context.l10n.moviesStatusError;
        break;
    }
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLarge.copyWith(fontSize: 14)),
                ),
                if (d.isDone)
                  IconButton(
                    tooltip: context.l10n.moviesPlayOfflineTooltip,
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    color: AppColors.accent,
                  )
                else if (d.status == DownloadStatus.downloading)
                  IconButton(
                    tooltip: context.l10n.moviesPauseTooltip,
                    onPressed: onPause,
                    icon: const Icon(Icons.pause_circle_filled_rounded),
                  )
                else
                  IconButton(
                    tooltip: context.l10n.moviesResumeTooltip,
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                IconButton(
                  tooltip: context.l10n.moviesDeleteTooltip,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.live,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (!d.isDone)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: d.totalBytes > 0 ? d.progress : null,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
            const SizedBox(height: 4),
            Text(status,
                style: AppTextStyles.bodyMedium
                    .copyWith(fontSize: 11, color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}
