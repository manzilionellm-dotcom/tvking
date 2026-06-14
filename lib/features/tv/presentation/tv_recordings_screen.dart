// =========================================================
//  tv_recordings_screen.dart — « Mes enregistrements » (10-foot)
// =========================================================
//  Liste des vidéos enregistrées par le client (RecordingRepository). Chaque
//  ligne est focusable au D-pad : OK = LIRE (via le lecteur système, open_filex
//  — on ne touche PAS au lecteur live de l'app), bouton corbeille = SUPPRIMER.
//
//  Robuste : aucune exception ne fait planter l'écran (try/catch partout) ;
//  si aucun lecteur externe n'est installé, on l'explique au lieu de crasher.
// =========================================================
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../recordings/data/recording_repository.dart';
import '../../recordings/domain/recording.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_components.dart';

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
          return const TvEmptyState(
            icon: Icons.video_library_rounded,
            title: 'Aucun enregistrement',
            subtitle:
                'Tes enregistrements apparaîtront ici. Pendant la lecture d\'une chaîne, appuie sur le bouton REC pour enregistrer.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: Text('Mes enregistrements',
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

  Future<void> _play(BuildContext context) async {
    try {
      final OpenResult res = await OpenFilex.open(rec.filePath);
      if (res.type != ResultType.done && context.mounted) {
        await _info(
          context,
          'Lecture impossible',
          "Aucune application capable de lire ce fichier (.ts) n'est installée "
              'sur cette TV. Installe un lecteur comme VLC ou MX Player.',
        );
      }
    } catch (_) {
      if (context.mounted) {
        await _info(context, 'Lecture impossible',
            "Ce fichier n'a pas pu être ouvert.");
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: TvTokens.card,
        title: Text('Supprimer ?', style: TextStyle(color: TvTokens.text)),
        content: Text('Supprimer définitivement « ${rec.channelName} » ?',
            style: TextStyle(color: TvTokens.muted)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: TextStyle(color: TvTokens.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Supprimer', style: TextStyle(color: TvTokens.live))),
        ],
      ),
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

  Future<void> _info(BuildContext context, String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: TvTokens.card,
        title: Text(title, style: TextStyle(color: TvTokens.text)),
        content: Text(body, style: TextStyle(color: TvTokens.muted)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK', style: TextStyle(color: TvTokens.gold))),
        ],
      ),
    );
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
