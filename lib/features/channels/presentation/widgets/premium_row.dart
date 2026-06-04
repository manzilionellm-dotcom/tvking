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

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/tv_focusable.dart';
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
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (onSeeAll != null)
                // Même refonte que SectionHeader : on perd le ripple
                // Material du TextButton mais on gagne le focus ring
                // ember visible à la télécommande (vs le focus système
                // gris invisible sur fond charbon).
                TvFocusable(
                  onTap: onSeeAll!,
                  borderRadius: BorderRadius.circular(8),
                  showGlow: false,
                  semanticsLabel: context.l10n.seeAllOf(title),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          context.l10n.buttonSeeAll,
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
                ),
            ],
          ),
        ),

        // ----- Liste horizontale -----
        // itemExtent + cacheExtent généreux → scroll fluide même
        // si la rangée contient les 20 chaînes max d'une section.
        SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: channels.length,
            itemExtent: PremiumChannelCard.cardWidth + 12,
            cacheExtent: 600,
            itemBuilder: (BuildContext context, int index) {
              final Channel ch = channels[index];
              return RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
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
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
