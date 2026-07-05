// =========================================================
//  tv_downloads_screen.dart — « Mes téléchargements » (films hors-ligne)
// =========================================================
//  Vitrine du VodDownloadService : les films téléchargés pour regarder
//  SANS connexion (voyage, mauvaise ligne…). Chaque ligne montre l'état
//  (barre de progression / « Prêt » / « En pause ») et OK :
//    • terminé  → LECTURE HORS-LIGNE (fichier local → lecteur existant,
//      donc mêmes commandes Netflix ±10 s) ;
//    • en cours → met en pause ; en pause/erreur → reprend.
//  Un appui long / bouton supprime le fichier (libère la place).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../vod/data/vod_download_service.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_player_screen.dart';

class TvDownloadsScreen extends StatefulWidget {
  const TvDownloadsScreen({super.key});

  @override
  State<TvDownloadsScreen> createState() => _TvDownloadsScreenState();
}

class _TvDownloadsScreenState extends State<TvDownloadsScreen> {
  @override
  void initState() {
    super.initState();
    VodDownloadService.instance.load();
  }

  void _playOffline(VodDownload d) {
    final Channel c = Channel(
      id: 'dl_${d.id}',
      name: d.name,
      category: d.category,
      // Fichier LOCAL (file://) → lu par ExoPlayer, isLive:false → lecteur
      // film (barre + ±10 s). AUCUNE connexion requise.
      streamUrl: Uri.file(d.filePath).toString(),
      isLive: false,
      logoUrl: d.posterUrl,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: <Channel>[c], startIndex: 0),
      ),
    );
  }

  void _onSelect(VodDownload d) {
    switch (d.status) {
      case VodDownloadStatus.done:
        _playOffline(d);
      case VodDownloadStatus.downloading:
        VodDownloadService.instance.pause(d.id);
      case VodDownloadStatus.paused:
      case VodDownloadStatus.error:
      case VodDownloadStatus.queued:
        VodDownloadService.instance.resume(d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: VodDownloadService.instance,
        builder: (BuildContext context, _) {
          final List<VodDownload> items = VodDownloadService.instance.all;
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(context.l10n.tvDownloadsTitle,
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
                const SizedBox(height: 4),
                Text(context.l10n.tvDownloadsSubtitle,
                    style: const TextStyle(fontSize: 14, color: TvTokens.muted)),
                const SizedBox(height: 20),
                Expanded(
                  child: items.isEmpty
                      ? _empty(context)
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int i) =>
                              _DownloadRow(
                            d: items[i],
                            autofocus: i == 0,
                            onSelect: () => _onSelect(items[i]),
                            onDelete: () =>
                                VodDownloadService.instance.remove(items[i].id),
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

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.download_done_rounded,
                size: 48, color: TvTokens.mutedDim),
            const SizedBox(height: 14),
            Text(context.l10n.tvDownloadsEmpty,
                style: const TextStyle(fontSize: 18, color: TvTokens.text)),
            const SizedBox(height: 6),
            Text(context.l10n.tvDownloadsEmptyHelp,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: TvTokens.mutedDim)),
          ],
        ),
      );
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.d,
    required this.onSelect,
    required this.onDelete,
    this.autofocus = false,
  });

  final VodDownload d;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final bool autofocus;

  ({IconData icon, String label, Color color}) _state(BuildContext context) {
    final int pct = (d.progress * 100).round();
    switch (d.status) {
      case VodDownloadStatus.done:
        return (
          icon: Icons.play_circle_fill_rounded,
          label: context.l10n
              .tvDownloadReady(VodDownloadService.fmtBytes(d.totalBytes)),
          color: TvTokens.gold
        );
      case VodDownloadStatus.downloading:
        return (
          icon: Icons.pause_circle_filled_rounded,
          label: context.l10n.tvDownloadInProgress(pct),
          color: TvTokens.goldBright
        );
      case VodDownloadStatus.paused:
        return (
          icon: Icons.download_rounded,
          label: context.l10n.tvDownloadPausedAt(pct),
          color: TvTokens.muted
        );
      case VodDownloadStatus.error:
        return (
          icon: Icons.refresh_rounded,
          label: context.l10n.tvDownloadFailed,
          color: TvTokens.live
        );
      case VodDownloadStatus.queued:
        return (
          icon: Icons.hourglass_bottom_rounded,
          label: context.l10n.tvDownloadQueued,
          color: TvTokens.muted
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String label, Color color}) s = _state(context);
    final bool showBar = d.status == VodDownloadStatus.downloading ||
        d.status == VodDownloadStatus.paused;
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      onLongPress: onDelete,
      builder: (BuildContext context, bool focused) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: focused ? TvTokens.sel : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(
                color: focused ? TvTokens.gold : TvTokens.lineSoft,
                width: focused ? TvDimens.focusOutline : 1),
          ),
          child: Row(
            children: <Widget>[
              Icon(s.icon, color: s.color, size: 34),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: TvTokens.text)),
                    const SizedBox(height: 4),
                    Text(s.label,
                        style: TextStyle(fontSize: 14, color: TvTokens.muted)),
                    if (showBar) ...<Widget>[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(
                          children: <Widget>[
                            Container(height: 5, color: Colors.white24),
                            FractionallySizedBox(
                              widthFactor: d.progress,
                              child: Container(
                                height: 5,
                                decoration: const BoxDecoration(
                                    gradient: TvTokens.ctaGradient),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Rappel discret : appui LONG = supprimer.
              Icon(Icons.delete_outline_rounded,
                  size: 22,
                  color: focused ? TvTokens.muted : TvTokens.mutedDim),
            ],
          ),
        );
      },
    );
  }
}
