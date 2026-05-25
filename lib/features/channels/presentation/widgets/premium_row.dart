// =========================================================
//  premium_row.dart — Rangée horizontale style Apple TV
// =========================================================
//  Remplace l'ancien `channel_row.dart` pour le nouveau design.
//
//  Structure :
//    [Titre de section] [count] ───────────────── [Voir tout >]
//    ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ...
//    │ logo │ │ logo │ │ logo │ │ logo │
//    └──────┘ └──────┘ └──────┘ └──────┘
//     Nom      Nom      Nom      Nom
//
//  Performances :
//    - ListView.builder (lazy)
//    - itemExtent fixe → pas de mesure pendant le scroll
//    - cards en RepaintBoundary
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/channel.dart';
import 'premium_channel_card.dart';

class PremiumRow extends StatelessWidget {
  const PremiumRow({
    required this.title,
    required this.channels,
    required this.onChannelTap,
    this.onChannelLongPress,
    this.onSeeAll,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Channel> channels;
  final void Function(Channel) onChannelTap;
  final void Function(Channel)? onChannelLongPress;
  final VoidCallback? onSeeAll;

  /// Hauteur totale (card + footer + padding).
  static const double rowHeight = 158;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ----- En-tête -----
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: AppTextStyles.headlineMedium.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Voir tout',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: AppColors.accent,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // ----- Liste horizontale -----
        SizedBox(
          height: rowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: channels.length,
            separatorBuilder: (BuildContext _, int __) =>
                const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              final Channel ch = channels[index];
              return RepaintBoundary(
                child: SizedBox(
                  width: PremiumChannelCard.cardWidth,
                  child: PremiumChannelCard(
                    channel: ch,
                    onTap: () => onChannelTap(ch),
                    onLongPress: onChannelLongPress != null
                        ? () => onChannelLongPress!(ch)
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
