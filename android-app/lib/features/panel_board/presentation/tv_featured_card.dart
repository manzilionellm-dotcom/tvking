// =========================================================
//  tv_featured_card.dart — « Favori du jour » du panel, sur l'accueil
// =========================================================
//  Le revendeur met une chaîne en avant (« TF1 — Mondial ce soir ⚽ »).
//  On ne la montre que si elle existe dans la liste de CETTE box
//  (voir matchChannelByName) : la carte ouvre une vraie chaîne, à la
//  demande, jamais toute seule.
// =========================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';

import '../../channels/domain/channel.dart';
import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_tokens.dart';
import '../../tv/core/tv_app_tokens.dart';
import 'panel_button.dart';

class TvFeaturedCard extends StatelessWidget {
  const TvFeaturedCard({
    super.key,
    required this.channel,
    required this.note,
    required this.onWatch,
  });

  final Channel channel;
  final String note;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final String? logo = channel.logoUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TvAppTokens.of(context).card,
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvAppTokens.of(context).line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: TvDimens.channelLogo,
                height: TvDimens.channelLogo,
                child: (logo != null && logo.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: logo,
                        fit: BoxFit.contain,
                        memCacheWidth: (TvDimens.channelLogo * 3).round(),
                        errorWidget: (_, __, ___) => _Initials(channel),
                        placeholder: (_, __) => _Initials(channel),
                      )
                    : _Initials(channel),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: TvAppTokens.of(context).accentBright,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.tvPickOfDay.toUpperCase(),
                          style: TvAppTokens.of(context).ui(
                            TvDimens.caption,
                            weight: FontWeight.w700,
                            color: TvAppTokens.of(context).accentBright,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      channel.cleanName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvAppTokens.of(context).ui(
                        TvDimens.titleS,
                        weight: FontWeight.w800,
                        color: TvAppTokens.of(context).text,
                      ),
                    ),
                    if (note.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        note.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TvAppTokens.of(context).ui(
                          TvDimens.label,
                          color: TvAppTokens.of(context).muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              PanelButton(
                label: context.l10n.buttonWatch,
                icon: Icons.play_arrow_rounded,
                onSelect: onWatch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials(this.channel);
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TvAppTokens.of(context).tile,
        borderRadius: BorderRadius.circular(TvTokens.rSmall),
      ),
      child: Center(
        child: Text(
          channel.initials,
          style: TvAppTokens.of(context).ui(
            TvDimens.label,
            weight: FontWeight.w800,
            color: TvAppTokens.of(context).muted,
          ),
        ),
      ),
    );
  }
}
