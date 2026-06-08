// =========================================================
//  hero_card.dart — HERO "Pour vous" (chaîne #1 populaire live)
// =========================================================
//  L'élément pour qui ne veut pas chercher : gros visuel, badge
//  POUR VOUS + LIVE qui pulse, titre 26, programme en cours, GROS
//  bouton blanc "Regarder" pleine largeur (56) + cœur 56.
//  Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../channels/domain/channel.dart';
import '../../data/channel_curation.dart';
import 'channel_logo.dart';

class HeroCard extends StatefulWidget {
  const HeroCard({
    super.key,
    required this.channel,
    required this.isFav,
    required this.onWatch,
    required this.onFav,
    this.scale = 1.0,
    this.label = 'POUR VOUS',
    this.note,
  });

  final Channel channel;
  final bool isFav;
  final VoidCallback onWatch;
  final VoidCallback onFav;
  final double scale;

  /// Libellé du badge (ex. 'POUR VOUS' ou 'FAVORI DU JOUR').
  final String label;

  /// Sous-titre forcé (ex. la note du favori du jour). Sinon EPG.
  final String? note;

  @override
  State<HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<HeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Channel ch = widget.channel;
    final double s = widget.scale;
    final Color base = logoFallbackColor(ch.name);
    final String? prog = ch.currentProgram;
    final bool hasEpg = prog != null && prog.trim().isNotEmpty;
    // Sous-titre : la note (favori du jour) prime sur l'EPG.
    final String? subtitle =
        (widget.note != null && widget.note!.trim().isNotEmpty)
            ? widget.note!.trim()
            : (hasEpg ? prog.trim() : null);

    return Container(
      height: 220 * s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.maisonBorder),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.lerp(base, AppColors.maisonSurfaceHigh, 0.25) ?? base,
            AppColors.maisonBg,
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          // Logo géant en filigrane (coin haut-droit).
          Positioned(
            right: -18 * s,
            top: -18 * s,
            child: Opacity(
              opacity: 0.14,
              child: ChannelLogo(channel: ch, size: 150 * s, radius: 0),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Badges.
                Row(
                  children: <Widget>[
                    _Badge(
                      label: widget.label,
                      fg: AppColors.maisonBg,
                      bg: AppColors.black7Red,
                      scale: s,
                    ),
                    if (ch.isLive) ...<Widget>[
                      SizedBox(width: 8 * s),
                      _livePulse(s),
                    ],
                  ],
                ),
                const Spacer(),
                Text(
                  cleanName(ch.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.maisonHeroTitle.copyWith(fontSize: 26 * s),
                ),
                if (subtitle != null) ...<Widget>[
                  SizedBox(height: 4 * s),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.maisonProgram.copyWith(fontSize: 16 * s),
                  ),
                ],
                SizedBox(height: 12 * s),
                Row(
                  children: <Widget>[
                    // GROS bouton blanc "Regarder".
                    Expanded(
                      child: SizedBox(
                        height: 56 * s,
                        child: ElevatedButton.icon(
                          onPressed: widget.onWatch,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.maisonInk,
                            foregroundColor: AppColors.maisonBg,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: Icon(Icons.play_arrow_rounded, size: 26 * s),
                          label: Text(
                            'Regarder',
                            style: AppTextStyles.maisonCta
                                .copyWith(fontSize: 17 * s),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10 * s),
                    // Cœur 56.
                    SizedBox(
                      width: 56 * s,
                      height: 56 * s,
                      child: Material(
                        color: AppColors.maisonSurfaceHigh,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: widget.onFav,
                          child: Icon(
                            widget.isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: widget.isFav
                                ? AppColors.liveRed
                                : AppColors.maisonInk,
                            size: 26 * s,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _livePulse(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9 * s, vertical: 5 * s),
      decoration: BoxDecoration(
        color: AppColors.liveRed.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FadeTransition(
            opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_pulse),
            child: Container(
              width: 7 * s,
              height: 7 * s,
              decoration: const BoxDecoration(
                color: AppColors.liveRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(width: 6 * s),
          Text('LIVE',
              style: AppTextStyles.maisonLabel
                  .copyWith(color: AppColors.liveRed, fontSize: 11.5 * s)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(
      {required this.label,
      required this.fg,
      required this.bg,
      required this.scale});
  final String label;
  final Color fg;
  final Color bg;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9 * scale, vertical: 5 * scale),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: AppTextStyles.maisonLabel
              .copyWith(color: fg, fontSize: 11.5 * scale)),
    );
  }
}
