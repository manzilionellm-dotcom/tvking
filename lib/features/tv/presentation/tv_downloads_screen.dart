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
  /// Espace libre du volume (« 12,4 Go libres ») — lu une fois à l'entrée
  /// puis à chaque changement de liste (un fichier supprimé libère de la
  /// place). null = mesure indisponible (on n'affiche rien).
  int? _freeBytes;

  @override
  void initState() {
    super.initState();
    VodDownloadService.instance.load();
    _refreshFreeSpace();
    VodDownloadService.instance.addListener(_refreshFreeSpace);
  }

  @override
  void dispose() {
    VodDownloadService.instance.removeListener(_refreshFreeSpace);
    super.dispose();
  }

  void _refreshFreeSpace() {
    VodDownloadService.instance.freeSpace().then((int? v) {
      if (mounted && v != _freeBytes) setState(() => _freeBytes = v);
    });
  }

  void _playOffline(VodDownload d) {
    final Channel c = Channel(
      // Id D'ORIGINE (pas de préfixe) : la position de reprise et les
      // téléchargements intelligents sont clés sur cet id — le même film
      // repris en ligne ou hors-ligne continue EXACTEMENT où il en était.
      id: d.id,
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
      case VodDownloadStatus.noSpace:
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(context.l10n.tvDownloadsTitle,
                              style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: TvTokens.text)),
                          const SizedBox(height: 4),
                          Text(
                              _freeBytes == null
                                  ? context.l10n.tvDownloadsSubtitle
                                  : context.l10n.tvDlFree(
                                      VodDownloadService.fmtBytes(_freeBytes!)),
                              style: const TextStyle(
                                  fontSize: 14, color: TvTokens.muted)),
                        ],
                      ),
                    ),
                    // TÉLÉCHARGEMENTS INTELLIGENTS (Netflix) : épisode vu →
                    // supprimé, épisode suivant → téléchargé tout seul.
                    _SmartToggle(
                        enabled: VodDownloadService.instance.smartEnabled),
                  ],
                ),
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

/// Interrupteur « Téléchargements intelligents » — focusable D-pad, même
/// langage visuel que les rangées (carte, liseré doré au focus). OK bascule.
class _SmartToggle extends StatelessWidget {
  const _SmartToggle({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: () =>
          VodDownloadService.instance.setSmartEnabled(!enabled),
      builder: (BuildContext context, bool focused) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: focused ? TvTokens.sel : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(
                color: focused ? TvTokens.ember : TvTokens.lineSoft,
                width: focused ? TvDimens.focusOutline : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(enabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                  size: 18,
                  color: enabled ? TvTokens.ember : TvTokens.mutedDim),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(context.l10n.tvDlSmart,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.text)),
                  Text(
                      enabled
                          ? context.l10n.tvDlSmartOn
                          : context.l10n.tvDlSmartOff,
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              enabled ? TvTokens.ember : TvTokens.mutedDim)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
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
          color: TvTokens.ember
        );
      case VodDownloadStatus.downloading:
        return (
          icon: Icons.pause_circle_filled_rounded,
          label: context.l10n.tvDownloadInProgress(pct),
          color: TvTokens.emberBright
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
      case VodDownloadStatus.noSpace:
        return (
          icon: Icons.sd_storage_rounded,
          label: context.l10n.tvDlNoSpace,
          color: TvTokens.live
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
                color: focused ? TvTokens.ember : TvTokens.lineSoft,
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
                                    gradient: TvTokens.cineGradient),
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
