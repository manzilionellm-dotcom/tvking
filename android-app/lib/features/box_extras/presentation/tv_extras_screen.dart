// =========================================================
//  tv_extras_screen.dart — Les fonctions en plus, une par ligne
// =========================================================
//  Chaque ligne ouvre UNE fonction, ou la coupe. Rien ici
//  n'ouvre un flux. La télécommande, les profils et la voix
//  ont leur propre entrée (Réglages, accueil) : on ne les
//  redouble pas ici.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../core/i18n/l10n_extension.dart';

import '../../../core/blackbox/black_box_upload_flag.dart';
import '../box_flag.dart';
import '../../followed/data/followed_flag.dart';
import '../../followed/data/followed_lead.dart';
import '../../followed/domain/show_clock.dart';
import '../../followed/domain/show_lines.dart';
import '../../missed_show/data/missed_flag.dart';
import '../../panel_board/data/panel_board_flags.dart';
import '../../time_picks/data/time_pick_flag.dart';
import '../../player/data/clear_voice_flag.dart';
import '../../player/data/image_prefs.dart';
import '../../player/data/video_quality_prefs.dart';
import '../../player/presentation/video_quality_setting.dart';
import '../../player/domain/image_engine.dart';
import '../../subtitles/data/subtitle_flag.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_focusable.dart';
import '../../tv/core/tv_tokens.dart';

class TvExtrasScreen extends StatefulWidget {
  const TvExtrasScreen({super.key});

  @override
  State<TvExtrasScreen> createState() => _TvExtrasScreenState();
}

class _TvExtrasScreenState extends State<TvExtrasScreen> {
  int _lead = kLeadDefault;

  @override
  void initState() {
    super.initState();
    missedShowFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    timePicksFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    subtitlesFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    blackBoxUploadFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    ClearVoiceFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    VideoQualityPrefs.load();
    ImagePrefs.load().then((_) {
      if (mounted) setState(() {});
    });
    followedFlag.load().then((_) {
      if (mounted) setState(() {});
    });
    FollowedLead.load().then((int minutes) {
      if (mounted) setState(() => _lead = minutes);
    });
    for (final BoxFlag flag in <BoxFlag>[
      panelNoticeFlag,
      featuredFlag,
      promoBannerFlag,
    ]) {
      flag.load().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// Les trois cartes du panel (annonce, favori du jour, bannières) :
  /// chacune se coupe seule. Coupée, elle disparaît de l'accueil, rien
  /// d'autre ne change.
  Future<void> _togglePanel(BoxFlag flag) async {
    await flag.load();
    await flag.set(!flag.value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleMissed() async {
    await missedShowFlag.load();
    await missedShowFlag.set(!missedShowFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleTime() async {
    await timePicksFlag.load();
    await timePicksFlag.set(!timePicksFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSubs() async {
    await subtitlesFlag.load();
    await subtitlesFlag.set(!subtitlesFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _cycleEngine() async {
    await ImagePrefs.load();
    final EngineStep step = EngineStep.next(
      ImagePrefs.engine,
      ffmpegVideo: false,
    );
    await ImagePrefs.setEngine(step.engine);
    if (mounted) setState(() {});
  }

  Future<void> _toggleFps() async {
    await ImagePrefs.load();
    await ImagePrefs.setFrameRateMatch(!ImagePrefs.frameRateMatch);
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoice() async {
    await ClearVoiceFlag.load();
    await ClearVoiceFlag.set(!ClearVoiceFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleBlackBox() async {
    await blackBoxUploadFlag.load();
    await blackBoxUploadFlag.set(!blackBoxUploadFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _toggleFollowed() async {
    await followedFlag.load();
    await followedFlag.set(!followedFlag.value);
    if (mounted) setState(() {});
  }

  Future<void> _cycleLead() async {
    final int next = nextLead(_lead);
    await FollowedLead.set(next);
    if (mounted) setState(() => _lead = FollowedLead.value);
  }

  @override
  Widget build(BuildContext context) {
    final bool on = missedShowFlag.value;
    final bool timeOn = timePicksFlag.value;
    final bool subsOn = subtitlesFlag.value;
    final bool voiceOn = ClearVoiceFlag.value;
    final bool boxOn = blackBoxUploadFlag.value;
    final bool fpsOn = ImagePrefs.frameRateMatch;
    final String engine = switch (ImagePrefs.engine) {
      ImageEngine.software => context.l10n.tvSoftware,
      ImageEngine.ffmpeg => 'FFmpeg',
      ImageEngine.hardware => context.l10n.tvHardware,
    };
    final bool followOn = followedFlag.value;
    final String code = Localizations.localeOf(context).languageCode;
    return ListView(
      children: <Widget>[
        Text(
          context.l10n.tvExtras,
          style: TextStyle(
            fontSize: TvDimens.displayM,
            fontWeight: FontWeight.w800,
            color: TvTokens.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.tvExtrasHelp,
          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
        ),
        const SizedBox(height: 18),
        if (defaultTargetPlatform == TargetPlatform.android)
          const VideoQualitySetting(autofocus: true),
        ExtrasRow(
          autofocus: defaultTargetPlatform != TargetPlatform.android,
          title: context.l10n.tvMissedTitle,
          subtitle: on ? context.l10n.tvMissedOn : context.l10n.tvMissedOff,
          onSelect: _toggleMissed,
        ),
        const SizedBox(height: 4),
        ExtrasRow(
          title: context.l10n.tvAtThisHour,
          subtitle: timeOn
              ? context.l10n.tvTimePicksOn
              : context.l10n.tvTimePicksOff,
          onSelect: _toggleTime,
        ),
        ExtrasRow(
          title: followedWord(code, 'row'),
          subtitle: followOn
              ? followedWord(code, 'setOn')
              : followedWord(code, 'setOff'),
          onSelect: _toggleFollowed,
        ),
        ExtrasRow(
          title: leadLine(code, _lead),
          subtitle: leadHint(code),
          onSelect: _cycleLead,
        ),
        ExtrasRow(
          title: context.l10n.tvServiceNotices,
          subtitle: panelNoticeFlag.value
              ? context.l10n.tvNoticesOn
              : context.l10n.tvNoticesOff,
          onSelect: () => _togglePanel(panelNoticeFlag),
        ),
        ExtrasRow(
          title: context.l10n.tvPickOfDay,
          subtitle: featuredFlag.value
              ? context.l10n.tvFeaturedOn
              : context.l10n.tvFeaturedOff,
          onSelect: () => _togglePanel(featuredFlag),
        ),
        ExtrasRow(
          title: context.l10n.tvBanners,
          subtitle: promoBannerFlag.value
              ? context.l10n.tvBannersOn
              : context.l10n.tvBannersOff,
          onSelect: () => _togglePanel(promoBannerFlag),
        ),
        ExtrasRow(
          title: context.l10n.tracksSubtitles,
          subtitle: subsOn
              ? context.l10n.tvSubtitlesOnHelp
              : context.l10n.tvSubtitlesOffHelp,
          onSelect: _toggleSubs,
        ),
        ExtrasRow(
          title: context.l10n.tvClearVoice,
          subtitle: voiceOn
              ? context.l10n.tvClearVoiceOn
              : context.l10n.tvClearVoiceOff,
          onSelect: _toggleVoice,
        ),
        ExtrasRow(
          title: context.l10n.tvLogToSupport,
          subtitle: boxOn
              ? context.l10n.tvLogToSupportOn
              : context.l10n.tvLogToSupportOff,
          onSelect: _toggleBlackBox,
        ),
        ExtrasRow(
          title: context.l10n.tvPictureEngine,
          subtitle: context.l10n.tvPictureEngineHelp(engine),
          onSelect: _cycleEngine,
        ),
        ExtrasRow(
          title: context.l10n.tvScreenRefresh,
          subtitle: fpsOn
              ? context.l10n.tvScreenRefreshOn
              : context.l10n.tvScreenRefreshOff,
          onSelect: _toggleFps,
        ),
        ExtrasRow(
          title: context.l10n.tvContrast,
          subtitle: context.l10n.tvContrastUnavailable,
          onSelect: () {},
        ),
      ],
    );
  }
}

class ExtrasRow extends StatelessWidget {
  const ExtrasRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSelect,
    this.autofocus = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TvFocusable(
        autofocus: autofocus,
        onSelect: onSelect,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: TvDimens.titleS,
                  fontWeight: FontWeight.w700,
                  color: TvTokens.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: TvDimens.label,
                  color: TvTokens.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
