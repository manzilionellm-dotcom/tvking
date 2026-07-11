// =========================================================
//  player_stats_overlay.dart — Overlay statistiques temps réel
// =========================================================
//  Petit panneau semi-transparent qui affiche en direct :
//    - Résolution × FPS
//    - Codec vidéo + audio
//    - Débit instantané (Mbps)
//    - Taux de buffering
//    - Frames perdues
//
//  Ces infos viennent de libmpv via les "properties" exposées
//  par media_kit (`player.platform?.observeProperty(...)`).
//
//  Utile pour diagnostiquer la qualité d'un flux en un coup
//  d'œil — équivalent du "Stats for Nerds" YouTube.
// =========================================================

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class PlayerStatsOverlay extends StatelessWidget {
  const PlayerStatsOverlay({
    required this.player,
    super.key,
  });

  final Player player;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.accentCyan.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: DefaultTextStyle(
        style: AppTextStyles.bodyMedium.copyWith(
          fontSize: 10,
          color: Colors.white,
          fontFamily: 'monospace',
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _statRow(context.l10n.statsTitle, '', isHeader: true),
            const SizedBox(height: 4),

            // Résolution
            StreamBuilder<int?>(
              stream: player.stream.width,
              initialData: player.state.width,
              builder: (_, AsyncSnapshot<int?> w) {
                return StreamBuilder<int?>(
                  stream: player.stream.height,
                  initialData: player.state.height,
                  builder: (_, AsyncSnapshot<int?> h) {
                    return _statRow(context.l10n.statsResolution,
                        '${w.data ?? '?'} × ${h.data ?? '?'}');
                  },
                );
              },
            ),

            // Codec vidéo
            StreamBuilder<Tracks>(
              stream: player.stream.tracks,
              initialData: player.state.tracks,
              builder: (_, AsyncSnapshot<Tracks> t) {
                final String codec = _videoCodec(player, t.data);
                return _statRow(context.l10n.statsVideoCodec, codec);
              },
            ),

            // Codec audio
            StreamBuilder<Tracks>(
              stream: player.stream.tracks,
              initialData: player.state.tracks,
              builder: (_, AsyncSnapshot<Tracks> t) {
                final String codec = _audioCodec(player, t.data);
                return _statRow(context.l10n.statsAudioCodec, codec);
              },
            ),

            // Buffer — « EN COURS » réutilise castInProgress (même
            // valeur française), « OK » réutilise buttonOk.
            StreamBuilder<bool>(
              stream: player.stream.buffering,
              initialData: player.state.buffering,
              builder: (_, AsyncSnapshot<bool> b) {
                return _statRow(
                    context.l10n.statsBuffer,
                    (b.data ?? false)
                        ? context.l10n.castInProgress
                        : context.l10n.buttonOk);
              },
            ),

            // Lecture
            StreamBuilder<bool>(
              stream: player.stream.playing,
              initialData: player.state.playing,
              builder: (_, AsyncSnapshot<bool> p) {
                return _statRow(
                    context.l10n.playerPlay,
                    (p.data ?? false)
                        ? context.l10n.statsActive
                        : context.l10n.statsPaused);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, {bool isHeader = false}) {
    if (isHeader) {
      return Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.accentCyan,
          fontSize: 10,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(value),
      ],
    );
  }

  String _videoCodec(Player p, Tracks? t) {
    final VideoTrack current = p.state.track.video;
    final String? codec = current.codec;
    if (codec != null && codec.isNotEmpty) return codec.toUpperCase();
    return '—';
  }

  String _audioCodec(Player p, Tracks? t) {
    final AudioTrack current = p.state.track.audio;
    final String? codec = current.codec;
    if (codec != null && codec.isNotEmpty) return codec.toUpperCase();
    return '—';
  }
}
