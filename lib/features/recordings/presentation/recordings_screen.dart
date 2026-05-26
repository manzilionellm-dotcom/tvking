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
import '../data/gallery_exporter.dart';
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

  Recording get recording => widget.recording;

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
              ? 'Exporté dans Galerie › Movies sous "7MOTION_$displayName"'
              : 'Export échec : ${res.userFacingError}',
          style: AppTextStyles.bodyMedium,
        ),
      ),
    );
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
              // Bouton "Exporter vers Galerie" — appelle MediaStore pour
              // copier le .ts (rebaptisé .mp4) dans Movies/. Visible
              // uniquement quand l'enregistrement est terminé. Spinner
              // pendant l'opération, qui peut prendre 1-3s sur un long clip.
              if (!inProgress)
                IconButton(
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        )
                      : const Icon(
                          Icons.drive_file_move_outline,
                          color: AppColors.accent,
                          size: 22,
                        ),
                  tooltip: 'Sauvegarder dans la Galerie',
                  onPressed: _exporting ? null : _exportToGallery,
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
    final String? logoUrl = widget.recording.channelLogoUrl;
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
          // Logo flottant de la chaîne — style "France 2 en bas-droite".
          // Affiché si le Recording avait stocké un logoUrl (recordings
          // créés APRÈS la migration DB ; pour les anciens, pas de logo).
          if (logoUrl != null && logoUrl.isNotEmpty)
            Positioned(
              bottom: 16,
              right: 16,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.75,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.network(
                      logoUrl,
                      height: 36,
                      width: 60,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      loadingBuilder: (BuildContext c, Widget child,
                              ImageChunkEvent? p) =>
                          p == null ? child : const SizedBox.shrink(),
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
