// =========================================================
//  tv_recordings_screen.dart — « Mes enregistrements » (10-foot)
// =========================================================
//  Liste des vidéos enregistrées par le client (RecordingRepository). Chaque
//  ligne est focusable au D-pad : OK = LIRE EN INTERNE (lecteur dédié
//  TvRecordingPlayerScreen, moteur natif ExoPlayer — le MÊME que le direct),
//  bouton corbeille = SUPPRIMER ; export MP4 vers la galerie après la fin.
//
//  IMPORTANT : on ne délègue PLUS à un lecteur externe (open_filex/intent VIEW).
//  Sur cette box, le .ts tombait sur la Galerie Android qui CRASHE (FATAL
//  EXCEPTION gallery3d) et tue l'app. La lecture interne supprime ce risque.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import 'tv_localized_format.dart';

import '../../recordings/data/recording_repository.dart';
import '../../recordings/data/gallery_exporter.dart';
import '../../recordings/domain/recording.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_recording_messages.dart';
import 'tv_recording_player_screen.dart';

class TvRecordingsScreen extends StatelessWidget {
  const TvRecordingsScreen({super.key, this.repository});
  final RecordingRepository? repository;

  @override
  Widget build(BuildContext context) {
    final RecordingRepository repo = repository ?? RecordingRepository.instance;
    return StreamBuilder<List<Recording>>(
      stream: repo.stream,
      initialData: repo.current,
      builder: (BuildContext context, AsyncSnapshot<List<Recording>> snap) {
        final List<Recording> recs = snap.data ?? const <Recording>[];
        if (recs.isEmpty) {
          return TvEmptyState(
            icon: Icons.video_library_rounded,
            title: context.l10n.tvNoRecordings,
            subtitle: context.l10n.tvNoRecordingsBody,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: Text(
                context.l10n.tvMyRecordings,
                style: TextStyle(
                  fontSize: TvDimens.displayS,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.text,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(right: 6, bottom: 8),
                itemCount: recs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int i) => _RecordingRow(
                  key: ValueKey<String>(
                    'novatube-recording-${recs[i].id ?? recs[i].filePath}',
                  ),
                  rec: recs[i],
                  repository: repo,
                  autofocus: i == 0,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecordingRow extends StatefulWidget {
  const _RecordingRow({
    super.key,
    required this.rec,
    required this.repository,
    this.autofocus = false,
  });
  final Recording rec;
  final RecordingRepository repository;
  final bool autofocus;

  @override
  State<_RecordingRow> createState() => _RecordingRowState();
}

class _RecordingRowState extends State<_RecordingRow> {
  bool _exporting = false;
  bool _deleting = false;
  String? _feedback;
  bool _feedbackError = false;

  Recording get rec => widget.rec;
  bool get _inProgress => rec.endedAt == null;
  bool get _canChangeFile =>
      !_inProgress &&
      !_exporting &&
      !_deleting &&
      GalleryExporter.pendingExportFor(rec.filePath) == null;

  @override
  void initState() {
    super.initState();
    final Future<GalleryExportResult>? pending =
        GalleryExporter.pendingExportFor(rec.filePath);
    if (pending != null) {
      _exporting = true;
      unawaited(_waitForExport(pending));
    }
  }

  Future<void> _exportToGallery() async {
    if (!_canChangeFile) return;
    setState(() {
      _exporting = true;
      _feedback = null;
    });
    await _waitForExport(GalleryExporter.exportVideo(
      srcPath: rec.filePath,
      displayName: GalleryExporter.displayNameFor(rec.filePath),
    ));
  }

  Future<void> _waitForExport(Future<GalleryExportResult> operation) async {
    try {
      final GalleryExportResult result = await operation;
      if (!mounted) return;
      setState(() {
        _feedbackError = !result.success;
        _feedback = tvGalleryExportMessage(context, result);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feedbackError = true;
        _feedback = context.l10n.tvRecordingExportFailed;
      });
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // LECTURE EN INTERNE (plus de lecteur externe qui crashait la box) : on
  // pousse le lecteur d'enregistrement dédié, qui rejoue le .ts via le MÊME
  // moteur natif (ExoPlayer/Media3) que le direct. Voir
  // tv_recording_player_screen.dart pour le « pourquoi » détaillé.
  void _play(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TvRecordingPlayerScreen(recording: rec),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    if (!_canChangeFile) return;
    setState(() => _deleting = true);
    try {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          backgroundColor: TvTokens.card,
          title: Text(
            context.l10n.tvDeleteQuestion,
            style: TextStyle(color: TvTokens.text),
          ),
          content: Text(
            context.l10n.tvDeleteRecordingConfirm(rec.channelName),
            style: TextStyle(color: TvTokens.muted),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                context.l10n.tvCancel,
                style: TextStyle(color: TvTokens.muted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                context.l10n.tvDelete,
                style: TextStyle(color: TvTokens.live),
              ),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await widget.repository.delete(rec);
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedbackError = true;
          _feedback = context.l10n.tvRecordingDeleteFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title =
        (rec.programTitle != null && rec.programTitle!.isNotEmpty)
            ? '${rec.channelName} · ${rec.programTitle}'
            : rec.channelName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TvFocusable(
                autofocus: widget.autofocus,
                scale: TvFocusScale.medium,
                baseColor: TvTokens.card,
                onSelect: () => _play(context),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        color: TvTokens.accent,
                        size: 38,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: TvDimens.title,
                                fontWeight: FontWeight.w700,
                                color: TvTokens.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${tvDateTime(context, DateTime.fromMillisecondsSinceEpoch(rec.startedAt))}  ·  ${tvDuration(context, rec.duration)}  ·  ${tvBytes(context, rec.fileSizeBytes)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: TvDimens.label,
                                color: TvTokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TvFocusable(
              key: ValueKey<String>('novatube-recording-delete-${rec.id}'),
              scale: TvFocusScale.small,
              baseColor: TvTokens.card,
              enabled: _canChangeFile,
              onSelect: _canChangeFile ? () => _delete(context) : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: TvTokens.muted,
                  size: 28,
                  semanticLabel: context.l10n.tvDelete,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: TvDimens.touchGap / 2),
        OutlinedButton.icon(
          key: ValueKey<String>('novatube-recording-export-${rec.id}'),
          onPressed: _canChangeFile ? _exportToGallery : null,
          icon: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_alt_rounded),
          label: Text(
            _exporting
                ? context.l10n.tvRecordingExporting
                : context.l10n.tvRecordingSaveGallery,
            textAlign: TextAlign.center,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: TvTokens.accentBright,
            minimumSize: const Size.fromHeight(TvDimens.touchTarget),
            padding: const EdgeInsets.all(TvDimens.touchGap),
          ),
        ),
        if (_inProgress || _feedback != null)
          Padding(
            padding: const EdgeInsets.only(top: TvDimens.touchGap / 2),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _inProgress
                    ? context.l10n.tvRecordingFinishBeforeExport
                    : _feedback!,
                style: TvTokens.ui(TvDimens.caption,
                    color: _feedbackError ? TvTokens.live : TvTokens.muted),
              ),
            ),
          ),
      ],
    );
  }
}
