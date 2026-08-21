// =========================================================
//  tv_recordings_screen.dart — « Mes enregistrements » (10-foot)
// =========================================================
//  Liste des vidéos enregistrées par le client (RecordingRepository). Chaque
//  ligne est focusable au D-pad : OK = LIRE EN INTERNE (lecteur dédié
//  TvRecordingPlayerScreen, moteur natif ExoPlayer — le MÊME que le direct),
//  bouton corbeille = SUPPRIMER.
//
//  IMPORTANT : on ne délègue PLUS à un lecteur externe (open_filex/intent VIEW).
//  Sur cette box, le .ts tombait sur la Galerie Android qui CRASHE (FATAL
//  EXCEPTION gallery3d) et tue l'app. La lecture interne supprime ce risque.
// =========================================================
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';

import '../../recordings/data/recording_repository.dart';
import '../../recordings/domain/recording.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';
import 'tv_recording_player_screen.dart';

class TvRecordingsScreen extends StatelessWidget {
  const TvRecordingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Recording>>(
      stream: RecordingRepository.instance.stream,
      initialData: RecordingRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<List<Recording>> snap) {
        final List<Recording> recs = snap.data ?? const <Recording>[];
        if (recs.isEmpty) {
          return TvEmptyState(
            icon: Icons.video_library_rounded,
            title: context.l10n.tvNoRecordings,
            subtitle: context.l10n.tvRecordingsEmpty,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: Text(context.l10n.recordingsTitle,
                  style: TextStyle(
                      fontSize: TvDimens.displayS,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text)),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(right: 6, bottom: 8),
                itemCount: recs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int i) =>
                    _RecordingRow(rec: recs[i], autofocus: i == 0),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({required this.rec, this.autofocus = false});
  final Recording rec;
  final bool autofocus;

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
    // Confirmation premium partagée (plus d'AlertDialog Android nu).
    final bool? ok = await showTvConfirm(
      context,
      title: context.l10n.tvRecDeleteTitle,
      message: context.l10n.tvRecDeleteConfirm(rec.channelName),
      confirmLabel: context.l10n.buttonDelete,
      danger: true,
    );
    if (ok != true) return;
    try {
      final File f = File(rec.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    try {
      await RecordingRepository.instance.delete(rec);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final String title =
        (rec.programTitle != null && rec.programTitle!.isNotEmpty)
            ? '${rec.channelName} · ${rec.programTitle}'
            : rec.channelName;
    return Row(
      children: <Widget>[
        Expanded(
          child: TvFocusable(
            autofocus: autofocus,
            scale: TvFocusScale.medium,
            baseColor: TvTokens.card,
            onSelect: () => _play(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.play_circle_fill_rounded,
                      color: TvTokens.gold, size: 38),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: TvDimens.title,
                                fontWeight: FontWeight.w700,
                                color: TvTokens.text)),
                        const SizedBox(height: 4),
                        Text(
                            '${rec.startedLabel}  ·  ${rec.durationLabel}  ·  ${rec.sizeLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: TvDimens.label,
                                color: TvTokens.muted)),
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
          scale: TvFocusScale.small,
          baseColor: TvTokens.card,
          onSelect: () => _delete(context),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Icon(Icons.delete_outline_rounded,
                color: TvTokens.muted, size: 28),
          ),
        ),
      ],
    );
  }
}
