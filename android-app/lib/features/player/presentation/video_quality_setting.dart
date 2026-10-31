import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_focusable.dart';
import '../../tv/core/tv_tokens.dart';
import '../data/video_quality_prefs.dart';

/// Choix réel de piste vidéo. Le texte décrit la source, sans promettre de
/// transformer un flux SD en HD. Le parent charge la préférence à son ouverture.
class VideoQualitySetting extends StatelessWidget {
  const VideoQualitySetting({super.key, this.autofocus = false});

  final bool autofocus;

  Future<void> _toggle() async {
    await VideoQualityPrefs.load();
    await VideoQualityPrefs.set(VideoQualityPrefs.value == VideoQuality.auto
        ? VideoQuality.maximum
        : VideoQuality.auto);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoQuality>(
        valueListenable: VideoQualityPrefs.changes,
        builder: (context, quality, child) {
          final maximum = quality == VideoQuality.maximum;
          return Padding(
            padding: const EdgeInsets.only(bottom: TvDimens.gutter),
            child: TvFocusable(
              autofocus: autofocus,
              onSelect: _toggle,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(TvDimens.gutter),
                decoration: BoxDecoration(
                  color: TvTokens.card,
                  borderRadius: BorderRadius.circular(TvTokens.rCard),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(context.l10n.tvVideoQuality,
                        style: TextStyle(fontSize: TvDimens.titleS,
                            fontWeight: FontWeight.w700, color: TvTokens.text)),
                    const SizedBox(height: TvDimens.rowGap),
                    Text(maximum ? context.l10n.tvVideoQualityMaximum : context.l10n.tvVideoQualityAuto,
                        style: TextStyle(fontSize: TvDimens.body,
                            fontWeight: FontWeight.w700, color: TvTokens.accent)),
                    const SizedBox(height: TvDimens.rowGap),
                    Text(maximum ? context.l10n.tvVideoQualityMaximumHelp : context.l10n.tvVideoQualityAutoHelp,
                        style: TextStyle(fontSize: TvDimens.label, color: TvTokens.muted)),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
