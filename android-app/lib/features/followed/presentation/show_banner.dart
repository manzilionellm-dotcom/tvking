// =========================================================
//  show_banner.dart — Bandeau discret sur l'accueil
// =========================================================
//  Pas une fenêtre. Pas de focus volé : la télécommande
//  continue sur les tuiles, et on MONTE jusqu'aux boutons
//  si on veut agir. Rien ne se lance tout seul.
//
//  Il vit sur l'accueil, jamais sur l'image en plein écran :
//  pendant une lecture, ce bandeau n'est pas là.
// =========================================================

import 'package:flutter/material.dart';

import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_focusable.dart';
import '../../tv/core/tv_tokens.dart';
import '../domain/show_clock.dart';
import '../domain/show_lines.dart';

class ShowBanner extends StatelessWidget {
  const ShowBanner({
    super.key,
    required this.cue,
    required this.languageCode,
    required this.canRewind,
    required this.onWatch,
    required this.onLive,
    required this.onRewind,
    required this.onReplay,
    required this.onLater,
  });

  final ShowCue cue;
  final String languageCode;

  /// L'adresse de rattrapage a vraiment été construite.
  /// Sinon on cache « Reprendre depuis le début ».
  final bool canRewind;

  final VoidCallback onWatch;
  final VoidCallback onLive;
  final VoidCallback onRewind;
  final VoidCallback onReplay;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final List<Widget> buttons = <Widget>[];
    void add(String label, VoidCallback onSelect) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 10));
      buttons.add(_BannerButton(label: label, onSelect: onSelect));
    }

    switch (cue.moment) {
      case ShowMoment.soon:
        add(followedWord(languageCode, 'watch'), onWatch);
        break;
      case ShowMoment.started:
      case ShowMoment.onAir:
        add(followedWord(languageCode, 'live'), onLive);
        if (canRewind) add(followedWord(languageCode, 'start'), onRewind);
        break;
      case ShowMoment.finished:
        if (cue.hasReplay) add(followedWord(languageCode, 'replay'), onReplay);
        if (canRewind) add(followedWord(languageCode, 'start'), onRewind);
        break;
    }
    add(followedWord(languageCode, 'later'), onLater);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvTokens.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                cueLine(languageCode, cue),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.ui(
                  TvDimens.titleS,
                  weight: FontWeight.w800,
                  color: TvTokens.text,
                ),
              ),
              if (cue.channelName.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  cue.channelName.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(TvDimens.caption, color: TvTokens.muted),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 0, runSpacing: 8, children: buttons),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerButton extends StatelessWidget {
  const _BannerButton({required this.label, required this.onSelect});

  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: TvTokens.sel,
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border: Border.all(color: TvTokens.line),
        ),
        child: Text(
          label,
          style: TvTokens.ui(
            TvDimens.label,
            weight: FontWeight.w700,
            color: TvTokens.text,
          ),
        ),
      ),
    );
  }
}
