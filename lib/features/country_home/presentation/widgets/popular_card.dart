// =========================================================
//  popular_card.dart — Carte "Populaires en ce moment"
// =========================================================
//  Carte 132 px : grand chiffre de rang en filigrane, logo, badge LIVE,
//  compteur "X regardent" (effet vivant). Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../channels/domain/channel.dart';
import '../../data/channel_curation.dart';
import 'channel_logo.dart';

class PopularCard extends StatelessWidget {
  const PopularCard({
    super.key,
    required this.channel,
    required this.rank,
    required this.watchers,
    required this.onTap,
    this.scale = 1.0,
  });

  final Channel channel;
  final int rank;
  final int watchers;
  final VoidCallback onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final double s = scale;
    return SizedBox(
      width: 132 * s,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Vignette logo + rang en filigrane + LIVE.
              SizedBox(
                width: 132 * s,
                height: 88 * s,
                child: Stack(
                  children: <Widget>[
                    Container(
                      width: 132 * s,
                      height: 88 * s,
                      decoration: BoxDecoration(
                        color: AppColors.maisonSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.maisonBorder),
                      ),
                      alignment: Alignment.center,
                      child: ChannelLogo(channel: channel, size: 58 * s),
                    ),
                    // Grand chiffre de rang en filigrane (bas-gauche).
                    Positioned(
                      left: 6 * s,
                      bottom: -6 * s,
                      child: Text(
                        '$rank',
                        style: AppTextStyles.maisonRank.copyWith(
                          fontSize: 52 * s,
                          color: AppColors.black7Red.withValues(alpha: 0.28),
                        ),
                      ),
                    ),
                    if (channel.isLive)
                      Positioned(
                        top: 6 * s,
                        right: 6 * s,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 6 * s, vertical: 3 * s),
                          decoration: BoxDecoration(
                            color: AppColors.liveRed,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('LIVE',
                              style: AppTextStyles.maisonLabel.copyWith(
                                  color: AppColors.maisonInk,
                                  fontSize: 9.5 * s)),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 8 * s),
              Text(
                cleanName(channel.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.maisonChannelName.copyWith(fontSize: 15 * s),
              ),
              SizedBox(height: 2 * s),
              Row(
                children: <Widget>[
                  Icon(Icons.visibility_rounded,
                      size: 13 * s, color: AppColors.textTertiary),
                  SizedBox(width: 4 * s),
                  Text(
                    '$watchers regardent',
                    style: AppTextStyles.maisonProgram.copyWith(
                        fontSize: 12.5 * s, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
