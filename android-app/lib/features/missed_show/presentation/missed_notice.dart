// Carte du guide isolée pour mesurer son affichage sans démarrer la vidéo.
// Cette première extraction conserve le comportement historique.
import 'package:flutter/material.dart';

import '../domain/missed_summary.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_tokens.dart';

class MissedNotice extends StatelessWidget {
  const MissedNotice({
    super.key,
    required this.summary,
    this.suppressed = false,
  });

  final MissedSummary summary;
  final bool suppressed;

  @override
  Widget build(BuildContext context) {
    if (suppressed) return const SizedBox.shrink();
    return ExcludeFocus(child: _legacyCard(context));
  }

  Widget _legacyCard(BuildContext context) {
    final MissedSummary missed = summary;
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
