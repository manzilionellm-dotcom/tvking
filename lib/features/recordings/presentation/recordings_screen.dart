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

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/recording_repository.dart';
import '../domain/recording.dart';

class RecordingsScreen extends StatelessWidget {
  const RecordingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mes enregistrements'),
      ),
      body: StreamBuilder<List<Recording>>(
        stream: RecordingRepository.instance.stream,
        initialData: RecordingRepository.instance.current,
        builder:
            (BuildContext context, AsyncSnapshot<List<Recording>> snap) {
          final List<Recording> recs = snap.data ?? <Recording>[];
          if (recs.isEmpty) return _empty();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            physics: const BouncingScrollPhysics(),
            itemCount: recs.length,
            separatorBuilder: (BuildContext _, int __) =>
                const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              return _RecordingTile(recording: recs[index]);
            },
          );
        },
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.movie_filter_outlined,
              size: 56,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              'Aucun enregistrement',
              style: AppTextStyles.bodyLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Pendant la lecture, appuie sur REC pour capturer le flux en direct.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({required this.recording});
  final Recording recording;

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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: inProgress
                      ? AppColors.live.withValues(alpha: 0.18)
                      : AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  inProgress
                      ? Icons.fiber_manual_record_rounded
                      : Icons.movie_creation_outlined,
                  color:
                      inProgress ? AppColors.live : AppColors.accent,
                  size: 22,
                ),
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
                        if (inProgress)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.live,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'EN COURS',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          )
                        else ...<Widget>[
                          _miniTag(recording.durationLabel),
                          const SizedBox(width: 6),
                          _miniTag(recording.sizeLabel),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                tooltip: 'Supprimer',
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
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
        title: const Text('Supprimer cet enregistrement ?'),
        content: Text(
          'Le fichier "${recording.filePath.split('/').last}" sera effacé.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.live),
            child: const Text('Supprimer'),
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

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.recording.filePath));
  }

  @override
  void dispose() {
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
      body: Center(
        child: Video(controller: _controller),
      ),
    );
  }
}
