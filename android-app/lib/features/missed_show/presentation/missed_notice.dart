// Notification discrète du guide : deux secondes, sans toucher à la vidéo.
// Le résumé reste dans le lecteur pour le retour au début et dans le Guide.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app/repair_flags.dart';
import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/missed_summary.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_tokens.dart';

class MissedNotice extends StatefulWidget {
  const MissedNotice({
    super.key,
    required this.summary,
    this.suppressed = false,
  });

  final MissedSummary summary;

  /// Le lecteur masque la carte pendant le zap ou le replay sans la démonter.
  /// Revenir au direct ne doit pas réafficher un bandeau déjà expiré.
  final bool suppressed;

  @override
  State<MissedNotice> createState() => _MissedNoticeState();
}

class _MissedNoticeState extends State<MissedNotice> {
  static const Duration _duration = Duration(seconds: 2);
  late final bool _legacy = RepairFlags.missedNoticeLegacy;
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    if (!_legacy) {
      // Une minuterie par carte : un rebuild (barre, buffer, focus) ne
      // prolonge pas le délai. La clé du lecteur change au prochain zap.
      _elapsed.start();
      _timer = Timer(_duration, () {
        if (!mounted) return;
        _elapsed.stop();
        setState(() => _expired = true);
        BlackBox.instance.info('GUIDE',
            'notification masquée après ${_elapsed.elapsedMilliseconds} ms');
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suppressed || _expired) return const SizedBox.shrink();
    return ExcludeFocus(
      child: _legacy ? _legacyCard(context) : _briefCard(context),
    );
  }

  Widget _briefCard(BuildContext context) => IgnorePointer(
        child: Padding(
          padding: EdgeInsets.only(
              top: TvDimens.safeV + 8, left: 48, right: 48),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Text(
                context.l10n.tvProgramStartedMinutesAgo(
                    widget.summary.missedMinutes),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.tvNotice,
              ),
            ),
          ),
        ),
      );

  // Carte historique conservée à l'identique pour le repli de diagnostic.
  Widget _legacyCard(BuildContext context) {
    final MissedSummary missed = widget.summary;
    final bool en = Localizations.localeOf(context).languageCode == 'en';
    final String lateLine = en
        ? 'You missed ${missed.missedMinutes} min'
        : 'Tu as raté ${missed.missedMinutes} min';
    final String hint = missed.canRewind
        ? (en
            ? 'Right, then OK: from the start.'
            : 'Droite, puis OK : depuis le début.')
        : (en
            ? 'The guide has the text, not the video. Live stays as it is.'
            : 'Le guide a le texte, pas la vidéo. Le direct ne bouge pas.');
    return Padding(
      padding: EdgeInsets.only(top: TvDimens.safeV + 8, left: 48, right: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE6141418),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TvTokens.line),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  missed.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TvDimens.titleS,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  lateLine,
                  style: TextStyle(
                    fontSize: TvDimens.label,
                    fontWeight: FontWeight.w700,
                    color: TvTokens.accentBright,
                  ),
                ),
                if (missed.description != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    missed.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.label, color: TvTokens.muted),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: TextStyle(
                      fontSize: TvDimens.label, color: TvTokens.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
