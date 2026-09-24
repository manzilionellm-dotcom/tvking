// =========================================================
//  resume_card.dart — Carte "Reprendre" (récemment regardé)
// =========================================================
//  Vignette + barre de progression or. NOTE : la position de reprise
//  réelle n'est pas encore stockée → la barre est cosmétique (fraction
//  déterministe), à brancher sur la vraie progression plus tard.
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../channels/domain/channel.dart';
import '../../data/channel_curation.dart';
import 'channel_logo.dart';

class ResumeCard extends StatelessWidget {
  const ResumeCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.scale = 1.0,
  });

  final Channel channel;
  final VoidCallback onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final double s = scale;
    // Fraction déterministe (cosmétique) — stable par chaîne.
    final double frac =
        0.25 + (channel.id.hashCode.abs() % 55) / 100.0; // 0.25–0.80

    return SizedBox(
      width: 150 * s,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 150 * s,
                height: 90 * s,
                child: Stack(
                  children: <Widget>[
                    Container(
                      width: 150 * s,
                      height: 90 * s,
                      decoration: BoxDecoration(
                        color: AppColors.maisonSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.maisonBorder),
                      ),
                      alignment: Alignment.center,
                      child: ChannelLogo(channel: channel, size: 56 * s),
                    ),
                    // Petit rond "play".
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          width: 34 * s,
                          height: 34 * s,
                          decoration: BoxDecoration(
                            color: AppColors.maisonBg.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.play_arrow_rounded,
                              color: AppColors.maisonInk, size: 22 * s),
                        ),
                      ),
                    ),
                    // Barre de progression or (bas).
                    Positioned(
                      left: 8 * s,
                      right: 8 * s,
                      bottom: 8 * s,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 4 * s,
                          backgroundColor:
                              AppColors.maisonInk.withValues(alpha: 0.18),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.black7Red),
                        ),
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
            ],
          ),
        ),
      ),
    );
  }
}
