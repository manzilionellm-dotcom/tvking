// =========================================================
//  recordings_screen.dart — Mes enregistrements
// =========================================================
//  Liste tous les .ts capturés par le bouton REC du player.
//  Chaque ligne :
//    - logo générique
//    - nom de la chaîne + (programme si EPG)
//    - date + durée + taille
//    - actions : Lecture / Supprimer
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// Ouvre un fichier avec l'app externe choisie par l'utilisateur
// (ex. VLC, MX Player). C'est le moyen le plus fiable de LIRE un
// enregistrement .ts : on délègue au lecteur système qui sait
// décoder le MPEG-TS, sans rien ré-encoder côté app.
import 'package:open_filex/open_filex.dart';
// Feuille de partage Android (« Partager via… ») : envoie le fichier
// d'enregistrement vers WhatsApp, Drive, Gmail, etc. Fournit aussi
// le type XFile utilisé pour joindre le fichier.
import 'package:share_plus/share_plus.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/friendly_error_view.dart';
import '../../epg/domain/epg_program.dart';
import '../../epg/presentation/epg_format.dart';
import '../../player/data/local_stream_relay.dart';
import '../../vod/data/vod_download_service.dart';
import '../data/gallery_exporter.dart';
import '../data/http_recording_downloader.dart';
import '../data/native_recording_scheduler.dart';
import '../data/recording_repository.dart';
import '../data/recording_scheduler.dart';
import '../data/recording_service.dart';
import '../data/recording_storage_policy.dart';
import '../data/scheduled_recording_repository.dart';
import '../domain/recording.dart';
import '../domain/scheduled_recording.dart';

class RecordingsScreen extends StatelessWidget {
  const RecordingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.recordingsTitle),
      ),
      body: StreamBuilder<List<Recording>>(
        stream: RecordingRepository.instance.stream,
        initialData: RecordingRepository.instance.current,
        builder:
            (BuildContext context, AsyncSnapshot<List<Recording>> snap) {
          final List<Recording> recs = snap.data ?? <Recording>[];
          // Enregistrements PROGRAMMÉS (depuis le guide) : section « Prévus »
          // au-dessus des vidéos, + carte stockage (usage / limite).
          return StreamBuilder<List<ScheduledRecording>>(
            stream: ScheduledRecordingRepository.instance.stream,
            initialData: ScheduledRecordingRepository.instance.current,
            builder: (BuildContext context,
                AsyncSnapshot<List<ScheduledRecording>> ssnap) {
              final List<ScheduledRecording> planned =
                  (ssnap.data ?? const <ScheduledRecording>[])
                      .where((ScheduledRecording s) =>
                          s.status != ScheduledRecordingStatus.done)
                      .toList(growable: false);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                physics: const BouncingScrollPhysics(),
                children: <Widget>[
                  const _StorageCard(),
                  const SizedBox(height: 16),
                  _sectionTitle(context, context.l10n.tvRecPlannedHeader),
                  if (planned.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(context.l10n.tvRecPlannedEmpty,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textMuted)),
                    )
                  else
                    for (final ScheduledRecording s in planned) ...<Widget>[
                      _ScheduledTile(entry: s),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 16),
                  _sectionTitle(
                      context, context.l10n.recordingsTitle.toUpperCase()),
                  if (recs.isEmpty)
                    SizedBox(height: 320, child: _empty(context))
                  else
                    for (final Recording r in recs) ...<Widget>[
                      _RecordingTile(recording: r),
                      const SizedBox(height: 8),
                    ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary, letterSpacing: 1.4)),
    );
  }

  Widget _empty(BuildContext context) {
    // Écran d'erreur convivial partagé (V9), variante « vide » : ce n'est
    // pas une panne, juste « rien à afficher pour l'instant ». On garde
    // l'icône métier (pellicule) plutôt que la boîte générique.
    return FriendlyErrorView.mobile(
      kind: FriendlyErrorKind.empty,
      icon: Icons.movie_filter_outlined,
      title: context.l10n.recordingsEmptyTitle,
      message: context.l10n.recordingsEmptySubtitle,
    );
  }
}

/// Carte STOCKAGE (mobile) : usage / libre, limite d'espace (menu), note
/// de purge automatique. Même politique que la TV (RecordingStoragePolicy).
class _StorageCard extends StatefulWidget {
  const _StorageCard();

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  int? _free;

  @override
  void initState() {
    super.initState();
    RecordingStoragePolicy.instance.addListener(_onChange);
    RecordingStoragePolicy.instance.freeBytes().then((int? v) {
      if (mounted) setState(() => _free = v);
    });
  }

  @override
  void dispose() {
    RecordingStoragePolicy.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final RecordingStoragePolicy p = RecordingStoragePolicy.instance;
    final String used = VodDownloadService.fmtBytes(p.usedBytes());
    final String free = _free == null ? '…' : VodDownloadService.fmtBytes(_free!);
    String label(int gb) => gb == 0
        ? context.l10n.tvRecStorageUnlimited
        : context.l10n.tvRecStorageLimitGb(gb);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.storage_rounded, color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.l10n.tvRecStorageUsed(used, free),
                    style: AppTextStyles.bodyLarge
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              PopupMenuButton<int>(
                initialValue: p.limitGb,
                onSelected: (int gb) => p.setLimitGb(gb),
                itemBuilder: (BuildContext _) => <PopupMenuEntry<int>>[
                  for (final int gb in RecordingStoragePolicy.limitChoicesGb)
                    PopupMenuItem<int>(value: gb, child: Text(label(gb))),
                ],
                child: Chip(
                  label: Text(
                      '${context.l10n.tvRecStorageLimit} : ${label(p.limitGb)}',
                      style: AppTextStyles.labelSmall),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(context.l10n.tvRecStorageAutoDeleteNote,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textMuted, fontSize: 11)),
          if (NativeRecordingScheduler.instance.isSupported &&
              !RecordingScheduler.instance.exactAlarmsOk) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(context.l10n.tvRecExactAlarmHint,
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary, fontSize: 11)),
                ),
                TextButton(
                  onPressed: () =>
                      NativeRecordingScheduler.instance.openExactAlarmSettings(),
                  child: Text(context.l10n.tvRecExactAlarmOpen),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Tuile d'un enregistrement PROGRAMMÉ (mobile). Appui = annuler.
class _ScheduledTile extends StatelessWidget {
  const _ScheduledTile({required this.entry});
  final ScheduledRecording entry;

  String _status(BuildContext context) => switch (entry.status) {
        ScheduledRecordingStatus.planned => context.l10n.tvRecStatusPlanned,
        ScheduledRecordingStatus.recording =>
          context.l10n.tvRecStatusRecording,
        ScheduledRecordingStatus.done => context.l10n.tvRecStatusDone,
        ScheduledRecordingStatus.missed => context.l10n.tvRecStatusMissed,
        ScheduledRecordingStatus.failed => context.l10n.tvRecStatusFailed,
        ScheduledRecordingStatus.cancelled => context.l10n.buttonCancel,
      };

  Future<void> _onTap(BuildContext context) async {
    if (!entry.isActive) {
      await ScheduledRecordingRepository.instance.delete(entry.id);
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.l10n.tvRecScheduleCancel),
        content: Text(entry.programTitle ?? entry.channelName),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.buttonCancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.l10n.buttonOk)),
        ],
      ),
    );
    if (ok == true) await RecordingScheduler.instance.cancel(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final bool rec = entry.status == ScheduledRecordingStatus.recording;
    final Color c = rec
        ? AppColors.live
        : (entry.isActive ? AppColors.accent : AppColors.textMuted);
    final EpgProgram asProgram = EpgProgram(
      channelId: entry.channelId,
      startTime: entry.startMs,
      stopTime: entry.stopMs,
      title: entry.programTitle ?? entry.channelName,
    );
    final DateTime d = entry.startDateTime;
    String two(int n) => n.toString().padLeft(2, '0');
    final String size = entry.bytes > 0
        ? ' · ${VodDownloadService.fmtBytes(entry.bytes)}'
        : '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onTap(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: <Widget>[
              Icon(rec ? Icons.fiber_manual_record_rounded : Icons.schedule_rounded,
                  color: c, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${entry.channelName} · ${entry.programTitle ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyLarge.copyWith(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${two(d.day)}/${two(d.month)} · '
                      '${epgTimeRange(context, asProgram)} · '
                      '${durationText(context.l10n, entry.duration)}$size',
                      style: AppTextStyles.bodyMedium
                          .copyWith(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(_status(context),
                  style: AppTextStyles.labelSmall.copyWith(color: c)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tuile d'enregistrement — version StatefulWidget pour gérer l'état
/// de loading pendant l'export vers la Galerie. Affiche un spinner
/// sur l'icône "Exporter" tant que la copie MediaStore tourne.
class _RecordingTile extends StatefulWidget {
  const _RecordingTile({required this.recording});
  final Recording recording;

  @override
  State<_RecordingTile> createState() => _RecordingTileState();
}

class _RecordingTileState extends State<_RecordingTile> {
  bool _exporting = false;
  bool _stopping = false;
  // Garde anti double-tap pendant qu'on ouvre le sélecteur d'app
  // externe (l'appel natif peut prendre une fraction de seconde).
  bool _opening = false;

  /// Timer qui ticke chaque seconde sur les recordings EN COURS pour
  /// rafraîchir l'affichage du compteur de bytes live. Null sur les
  /// recordings finalisés (pas besoin de rebuild).
  Timer? _liveTicker;

  Recording get recording => widget.recording;

  @override
  void initState() {
    super.initState();
    if (recording.endedAt == null) {
      _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    super.dispose();
  }

  /// Arrête un enregistrement "EN COURS" depuis la liste.
  /// Reproduit la séquence du player :
  ///   1. flush + close du downloader HTTP (singleton)
  ///   2. kill du ForegroundService (retire la notif persistante)
  ///   3. marque le Recording comme `endedAt = now` dans la DB
  /// Si ce n'est pas LE recording actif (cas d'un orphelin laissé
  /// par un crash / fermeture brutale), les 2 premières étapes
  /// sont des no-op et on passe directement au step 3 → la tuile
  /// se transforme en card finalisée (durée + taille + export).
  Future<void> _stopRecording() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    try {
      // Stoppe UNIQUEMENT le job de ce recording (par filePath).
      // Best-effort : si le job n'existe pas (orphelin DB), no-op.
      try {
        await HttpRecordingDownloader.instance
            .stop(filePath: recording.filePath);
      } catch (_) {}
      // AUDIT 19/08 : un enregistrement LIVE démarré depuis le lecteur passe
      // par le RELAIS (tee), pas par le téléchargeur HTTP — l'arrêter d'ici
      // laissait sa session relais enregistrer (recordSink non nul), donc
      // préservée par closeOtherPlaybacks : la connexion amont survivait
      // indéfiniment. stopRecording est idempotent (0 si pas de session).
      final String? recUrl = recording.streamUrl;
      if (recUrl != null && recUrl.isNotEmpty) {
        try {
          await LocalStreamRelay.instance.stopRecording(recUrl);
        } catch (_) {}
      }
      // ForegroundService : on l'arrête seulement si plus aucun
      // recording n'est actif (cas multi-recordings parallèles).
      if (HttpRecordingDownloader.instance.activeCount == 0) {
        try {
          await RecordingService.instance.stop();
        } catch (_) {}
      }
      await RecordingRepository.instance.finishRecording(recording);
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceHigh,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
          content: Text(
            context.l10n.recordingStopped,
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.recordingStopError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  Future<void> _exportToGallery() async {
    if (_exporting) return;
    // Vérifie que le fichier existe vraiment avant d'appeler le natif.
    // Si pas → message clair sans même tenter MediaStore.
    setState(() => _exporting = true);
    final String fileName = recording.filePath.split('/').last;
    final String displayName = fileName.replaceAll('.ts', '.mp4');
    final GalleryExportResult res = await GalleryExporter.exportVideo(
      srcPath: recording.filePath,
      displayName: displayName,
    );
    if (!mounted) return;
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceHigh,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: res.success ? 4 : 8),
        content: Text(
          res.success
              ? context.l10n.recordingExported(displayName)
              : context.l10n.recordingExportFailed(res.userFacingError),
          style: AppTextStyles.bodyMedium,
        ),
      ),
    );
  }

  /// Ouvre l'enregistrement avec une app externe (VLC, MX Player…).
  /// Les enregistrements finalisés sont des .mp4 universels (type
  /// `video/mp4` → tous les lecteurs se proposent). Pour un .ts pas
  /// encore converti (conversion en cours, ou échouée sur un codec
  /// exotique), on force `video/mp2t` pour que VLC & co. se proposent.
  Future<void> _openExternally(BuildContext context) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final OpenResult res = await OpenFilex.open(
        recording.filePath,
        type: recording.filePath.toLowerCase().endsWith('.mp4')
            ? 'video/mp4'
            : 'video/mp2t',
      );
      if (!mounted) return;
      // ResultType.done = une app a pris le relais. Sinon (aucune app
      // capable / fichier introuvable) on prévient l'utilisateur.
      if (res.type != ResultType.done) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surfaceHigh,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            content: Text(
              context.l10n.recordingNoPlayer,
              style: AppTextStyles.bodyMedium,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Ouvre la feuille de partage Android pour envoyer le fichier
  /// d'enregistrement vers une autre app (Drive, WhatsApp, Gmail…).
  Future<void> _shareRecording() async {
    await Share.shareXFiles(<XFile>[XFile(recording.filePath)]);
  }

  @override
  Widget build(BuildContext context) {
    final bool inProgress = recording.endedAt == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: inProgress ? null : () => _play(context),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: inProgress
                  ? AppColors.live.withValues(alpha: 0.6)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: <Widget>[
              // Logo de la chaîne (CachedNetworkImage) avec fallback
              // sur l'icône movie si pas de logo en DB. Sur les
              // recordings EN COURS, on superpose un petit point rouge
              // clignotant en haut-droite pour le côté "REC live".
              _RecordingThumb(
                logoUrl: recording.channelLogoUrl,
                inProgress: inProgress,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      recording.programTitle ?? recording.channelName,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      recording.programTitle != null
                          ? '${recording.channelName} · ${recording.startedLabel}'
                          : recording.startedLabel,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        if (inProgress) ...<Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.live,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              context.l10n.castInProgress,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          ),
                          // Compteur de bytes live — rafraîchi chaque
                          // seconde par _liveTicker. Lit la taille
                          // directement depuis le job actif du downloader
                          // (si présent), sinon 0 (cas orphelin).
                          const SizedBox(width: 6),
                          _miniTag(_liveBytesLabel()),
                        ] else ...<Widget>[
                          // Durée localisée via le helper presentation
                          // (mêmes clés duration* que l'EPG).
                          _miniTag(durationText(context.l10n, recording.duration)),
                          const SizedBox(width: 6),
                          _miniTag(recording.sizeLabel),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Bouton STOP — visible uniquement pour les recordings
              // "EN COURS". Permet d'arrêter sans devoir rouvrir le
              // player de la chaîne d'origine (utile pour les orphelins
              // laissés par un crash, ou quand le user veut juste finir
              // un enregistrement long depuis cet écran).
              if (inProgress)
                IconButton(
                  icon: _stopping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.live,
                          ),
                        )
                      : Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.live,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.stop_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                  tooltip: context.l10n.recordingStopTooltip,
                  onPressed: _stopping ? null : _stopRecording,
                ),
              // Bouton "Ouvrir" — délègue la lecture à une app externe
              // (VLC, MX Player…) qui sait décoder le MPEG-TS. C'est la
              // façon la plus sûre de LIRE un enregistrement, sans
              // dépendre du player interne ni d'un export.
              if (!inProgress)
                IconButton(
                  icon: _opening
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        )
                      : Icon(
                          Icons.open_in_new,
                          color: AppColors.accent,
                          size: 22,
                        ),
                  tooltip: context.l10n.recordingOpenWith,
                  onPressed: _opening ? null : () => _openExternally(context),
                ),
              // Bouton "Partager" — feuille de partage Android pour
              // envoyer le fichier vers une autre app.
              if (!inProgress)
                IconButton(
                  icon: Icon(
                    Icons.share_outlined,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                  tooltip: context.l10n.recordingShare,
                  onPressed: _shareRecording,
                ),
              // Bouton "Exporter vers Galerie" — appelle MediaStore pour
              // copier le .ts (rebaptisé .mp4) dans Movies/. Visible
              // uniquement quand l'enregistrement est terminé. Spinner
              // pendant l'opération, qui peut prendre 1-3s sur un long clip.
              if (!inProgress)
                IconButton(
                  icon: _exporting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        )
                      : Icon(
                          Icons.drive_file_move_outline,
                          color: AppColors.accent,
                          size: 22,
                        ),
                  tooltip: context.l10n.recordingSaveTooltip,
                  onPressed: _exporting ? null : _exportToGallery,
                ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                tooltip: context.l10n.buttonDelete,
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Convertit bytesWritten du downloader (live) en label lisible.
  /// Affiche "0 B" si pas de job actif (cas d'un orphelin laissé par
  /// un crash : la card reste EN COURS mais le downloader n'a plus
  /// de _Job pour ce filePath).
  String _liveBytesLabel() {
    final int bytes =
        HttpRecordingDownloader.instance.bytesWrittenFor(recording.filePath);
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _miniTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 9,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: Text(context.l10n.recordingDeleteConfirmTitle),
        content: Text(
          context.l10n.recordingDeleteConfirmBody(
              recording.filePath.split('/').last),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.buttonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.live),
            child: Text(context.l10n.buttonDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await RecordingRepository.instance.delete(recording);
    }
  }

  void _play(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _RecordingPlayer(recording: recording),
      ),
    );
  }
}

/// Petit lecteur minimal pour relire un fichier local .ts.
class _RecordingPlayer extends StatefulWidget {
  const _RecordingPlayer({required this.recording});
  final Recording recording;

  @override
  State<_RecordingPlayer> createState() => _RecordingPlayerState();
}

class _RecordingPlayerState extends State<_RecordingPlayer> {
  late final Player _player;
  late final VideoController _controller;

  /// Message d'erreur lisible (null = lecture OK). Évite l'écran NOIR
  /// muet quand le fichier est vide, manquant ou illisible.
  String? _errorMsg;
  StreamSubscription<String>? _errSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _errSub = _player.stream.error.listen((String e) {
      if (mounted && _errorMsg == null) {
        setState(() => _errorMsg = context.l10n.recordingUnreadable);
      }
    });
    _openOrFail();
  }

  /// Vérifie que le fichier existe ET n'est pas vide AVANT d'ouvrir, pour
  /// donner un message clair plutôt qu'un écran noir.
  Future<void> _openOrFail() async {
    try {
      final File f = File(widget.recording.filePath);
      final bool ok = await f.exists();
      final int size = ok ? await f.length() : 0;
      if (!ok || size == 0) {
        if (mounted) {
          setState(() => _errorMsg = ok
              ? context.l10n.recordingEmpty
              : context.l10n.recordingNotFound);
        }
        return;
      }
      await _player.open(Media(widget.recording.filePath));
    } catch (e) {
      if (mounted) setState(() => _errorMsg = context.l10n.recordingPlayError('$e'));
    }
  }

  @override
  void dispose() {
    _errSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        title: Text(
          widget.recording.programTitle ?? widget.recording.channelName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Stack(
        children: <Widget>[
          Center(
            child: Video(controller: _controller),
          ),
          // Message clair en cas de fichier vide / illisible (au lieu
          // d'un écran noir muet). On passe par l'écran d'erreur convivial
          // partagé (V9) : icône selon le type + message humain + bouton
          // « Retour ». Le fichier illisible n'est PAS « réessayable » (il
          // ne se réparera pas tout seul) → une seule action, Retour.
          if (_errorMsg != null)
            FriendlyErrorView.mobile(
              kind: FriendlyErrorKind.unknown,
              title: context.l10n.tvRecPlayErrorTitle,
              message: _errorMsg,
              secondaryLabel: context.l10n.buttonBack,
              onSecondary: () => Navigator.of(context).pop(),
            ),
          // Watermark "THE FEWS" — marque de l'app par-dessus la vidéo
          // (coin bas-droite, style logo chaîne). Affiché EN PERMANENCE :
          // il recouvre le logo de la chaîne d'origine et brande
          // l'enregistrement aux couleurs de l'app.
          Positioned(
            bottom: 16,
            right: 16,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.9,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'THE ',
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'FEWS',
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppColors.accent,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vignette d'enregistrement — affiche le LOGO de la chaîne (cached)
/// avec un padding sombre derrière, et un petit point rouge clignotant
/// en haut-droite si le recording est encore EN COURS.
///
/// Fallback gracieux : si pas de logoUrl en DB, on retombe sur
/// l'icône movie/REC d'origine.
class _RecordingThumb extends StatefulWidget {
  const _RecordingThumb({
    required this.logoUrl,
    required this.inProgress,
  });

  final String? logoUrl;
  final bool inProgress;

  @override
  State<_RecordingThumb> createState() => _RecordingThumbState();
}

class _RecordingThumbState extends State<_RecordingThumb>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.inProgress) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _RecordingThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si le recording passe de EN COURS → fini, on arrête la pulsation.
    if (oldWidget.inProgress && !widget.inProgress) {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? logo = widget.logoUrl;
    final bool hasLogo = logo != null && logo.isNotEmpty;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: <Widget>[
          // Fond + logo (ou fallback icon)
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: widget.inProgress
                  ? AppColors.live.withValues(alpha: 0.18)
                  : AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(6),
            child: hasLogo
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: logo,
                      fit: BoxFit.contain,
                      // Décodage BORNÉ : vignette ~36 px utiles — décoder le
                      // PNG 1000×1000 du panel gaspillait ~4 Mo RAM par logo
                      // (seul site non borné du dépôt, revue images).
                      memCacheWidth: 96,
                      memCacheHeight: 96,
                      fadeInDuration: const Duration(milliseconds: 200),
                      errorWidget: (_, __, ___) => Icon(
                        Icons.movie_creation_outlined,
                        color: widget.inProgress
                            ? AppColors.live
                            : AppColors.accent,
                        size: 22,
                      ),
                    ),
                  )
                : Icon(
                    widget.inProgress
                        ? Icons.fiber_manual_record_rounded
                        : Icons.movie_creation_outlined,
                    color: widget.inProgress
                        ? AppColors.live
                        : AppColors.accent,
                    size: 22,
                  ),
          ),
          // Point rouge clignotant en haut-droite (uniquement EN COURS).
          // Tap visuel "REC live" — exactement le pattern caméra/Twitch.
          if (widget.inProgress && _pulse != null)
            Positioned(
              top: 4,
              right: 4,
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulse!),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.live,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.live.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
