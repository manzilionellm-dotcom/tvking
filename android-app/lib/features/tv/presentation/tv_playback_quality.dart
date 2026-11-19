import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:native_video_player/video_quality.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_app_tokens.dart';
import '../core/tv_dimens.dart';

/// Indicateur passif de la lecture locale. Le nom de chaîne n'entre jamais
/// dans ce widget : seuls les événements du décodeur peuvent le renseigner.
/// La sortie du lecteur, le format du flux et la cadence comptée sont distincts.
class TvPlaybackQuality extends StatelessWidget {
  const TvPlaybackQuality({
    super.key,
    required this.quality,
    this.compact = false,
  });

  final NativeVideoQuality quality;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final palette = TvAppTokens.playbackOf(context);
    final String size = quality.hasOutputSize
        ? '${quality.outputWidth} × ${quality.outputHeight} px'
        : l.tvQualityUnknown;
    final String codec = switch (quality.sourceMimeType) {
      'video/avc' => 'H.264',
      'video/hevc' => 'HEVC',
      'video/dolby-vision' => 'Dolby Vision',
      'video/x-vnd.on2.vp9' => 'VP9',
      'video/x-vnd.on2.vp8' => 'VP8',
      'video/av01' => 'AV1',
      'video/mpeg2' => 'MPEG-2',
      'video/mp4v-es' => 'MPEG-4',
      _ => l.tvQualityCodecUnknown,
    };
    final String range = switch (quality.sourceDynamicRange) {
      'sdr' => 'SDR',
      'pq' => 'HDR (PQ)',
      'hlg' => 'HDR (HLG)',
      'dolbyVision' => 'Dolby Vision',
      _ => l.tvQualityRangeUnknown,
    };
    final String source = quality.sourceWidth > 0 && quality.sourceHeight > 0
        ? '${quality.sourceWidth} × ${quality.sourceHeight} px · $codec'
        : codec;
    // Même l'aperçu indique la source si un traitement agrandit la sortie.
    final bool showSource = !compact ||
        (quality.sourceWidth > 0 &&
            quality.sourceHeight > 0 &&
            (quality.sourceWidth != quality.outputWidth ||
                quality.sourceHeight != quality.outputHeight));
    final NativeVideoCadence? cadence = quality.cadence;
    final NumberFormat decimal =
        NumberFormat('0.0', Localizations.localeOf(context).toString());
    final NativeAiPictureStatus? ai = quality.aiPicture;
    final String aiLabel = ai == null
        ? l.tvAiUnknown
        : ai.active ? l.tvAiActive : l.tvAiNative;
    final String? aiReason = ai == null || ai.active
        ? null
        : switch (ai.fallback) {
            NativeAiFallback.fluidity => l.tvAiReasonFluidity,
            NativeAiFallback.source => l.tvAiReasonSource,
            NativeAiFallback.verification => l.tvAiReasonVerification,
            NativeAiFallback.unavailable => l.tvAiReasonUnavailable,
          };
    final Widget aiText = Text(
      aiLabel,
      style: palette.ui(TvDimens.caption, color: palette.muted),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.tvQualityOutput(size),
          style: palette.ui(compact ? TvDimens.caption : TvDimens.label,
              color: palette.text),
        ),
        if (showSource)
          Text(
            l.tvQualitySource(source, range),
            style: palette.ui(TvDimens.caption, color: palette.muted),
          ),
        if (!compact && cadence != null)
          Text(
            l.tvQualityCadence(
              decimal.format(cadence.framesPerSecond),
              cadence.droppedFrames,
              decimal.format(cadence.windowMs / 1000),
            ),
            style: palette.ui(TvDimens.caption, color: palette.muted),
          ),
        if (aiReason == null) aiText else Tooltip(message: aiReason, child: aiText),
      ],
    );
  }
}
