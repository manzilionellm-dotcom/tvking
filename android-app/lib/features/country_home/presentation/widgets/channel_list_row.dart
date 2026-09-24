// =========================================================
//  channel_list_row.dart — Ligne de chaîne (liste haute seniors)
// =========================================================
//  Ligne ≥ 76 px : logo 52, nom 17 gras (nettoyé), "En ce moment ·
//  {programme}" si EPG dispo (sinon masqué proprement), cœur favori 48.
//  Grande cible tactile. Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../channels/domain/channel.dart';
import '../../data/channel_curation.dart';
import 'channel_logo.dart';

class ChannelListRow extends StatelessWidget {
  const ChannelListRow({
    super.key,
    required this.channel,
    required this.isFav,
    required this.onTap,
    required this.onFav,
    this.scale = 1.0,
  });

  final Channel channel;
  final bool isFav;
  final VoidCallback onTap;
  final VoidCallback onFav;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final String? prog = channel.currentProgram;
    final bool hasEpg = prog != null && prog.trim().isNotEmpty;
    final double logo = 52 * scale;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: BoxConstraints(minHeight: 76 * scale),
          padding: EdgeInsets.symmetric(vertical: 8 * scale, horizontal: 10),
          child: Row(
            children: <Widget>[
              ChannelLogo(channel: channel, size: logo, radius: 13),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      cleanName(channel.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.maisonChannelName
                          .copyWith(fontSize: 17 * scale),
                    ),
                    if (hasEpg) ...<Widget>[
                      SizedBox(height: 3 * scale),
                      Row(
                        children: <Widget>[
                          Container(
                            width: 6 * scale,
                            height: 6 * scale,
                            margin: EdgeInsets.only(right: 6 * scale),
                            decoration: const BoxDecoration(
                              color: AppColors.liveRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'En ce moment · ${prog.trim()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.maisonProgram
                                  .copyWith(fontSize: 14.5 * scale),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8 * scale),
              // Cœur favori — cible 48.
              SizedBox(
                width: 48 * scale,
                height: 48 * scale,
                child: IconButton(
                  onPressed: onFav,
                  iconSize: 24 * scale,
                  tooltip: isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  icon: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFav ? AppColors.liveRed : AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
