// =========================================================
//  premium_channel_card.dart — Vignette landscape style Apple TV
// =========================================================
//  Carte 16:9 utilisée pour les rangées horizontales de
//  l'accueil ("Continue Watching", "Favoris", "Live Now", etc.)
//
//  Design :
//    - Card sombre élégante, bords arrondis 12px
//    - Logo centré (avec fallback uniforme)
//    - Badge LIVE en surimpression haut-gauche (si live)
//    - Badge qualité (4K / HD) haut-droite si pertinent
//    - Footer compact : nom de chaîne sur 1 ligne
//    - Au focus : bordure or fine + élévation subtile
//
//  Pas de dégradés colorés, pas de surcharge. La carte sert
//  le logo de la chaîne (la "marque") — pas l'inverse.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/channel.dart';
import 'channel_logo.dart';

class PremiumChannelCard extends StatefulWidget {
  const PremiumChannelCard({
    required this.channel,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Largeur recommandée pour les rangées horizontales.
  static const double cardWidth = 168;

  @override
  State<PremiumChannelCard> createState() => _PremiumChannelCardState();
}

class _PremiumChannelCardState extends State<PremiumChannelCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final Channel ch = widget.channel;

    return Focus(
      onFocusChange: (bool f) => setState(() => _focused = f),
      child: MouseRegion(
        onEnter: (_) => setState(() => _focused = true),
        onExit: (_) => setState(() => _focused = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: _focused
                ? (Matrix4.identity()..scale(1.04))
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ----- Card visuelle 16:9 -----
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _focused
                            ? AppColors.accent
                            : AppColors.border,
                        width: _focused ? 1.5 : 1,
                      ),
                      boxShadow: _focused
                          ? <BoxShadow>[
                              BoxShadow(
                                color: AppColors.accent.withValues(
                                  alpha: 0.25,
                                ),
                                blurRadius: 16,
                                spreadRadius: 0,
                              ),
                            ]
                          : <BoxShadow>[],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: <Widget>[
                          // Logo centré (ou fallback)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: ChannelLogo(
                                channel: ch,
                                size: ChannelLogoSize.medium,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),

                          // Badge LIVE haut-gauche
                          if (ch.isLive)
                            const Positioned(
                              top: 8,
                              left: 8,
                              child: _LivePill(),
                            ),

                          // Badge qualité haut-droite
                          if (ch.quality != ChannelQuality.sd)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: ChannelQualityBadge(
                                quality: ch.quality,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ----- Footer texte sous la card -----
                const SizedBox(height: 8),
                Text(
                  ch.cleanName,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Icon(
                      ch.genre.icon,
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        ch.country != null
                            ? '${ch.country!.flag} ${ch.genre.label}'
                            : ch.genre.label,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill rouge "LIVE" compact pour les vignettes.
class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.live,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'LIVE',
        style: AppTextStyles.labelSmall.copyWith(
          color: Colors.white,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
