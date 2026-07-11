// =========================================================
//  search_result_card.dart — Card riche pour résultats search
// =========================================================
//  Plus dense que `ChannelCard` : on affiche logo + nom + un
//  trio de badges (genre, qualité, pays) pour permettre à
//  l'utilisateur de différencier visuellement deux chaînes qui
//  ont le même nom sur un même provider (Sky Sport HD vs
//  Sky Sport 4K vs Sky Sport UK).
//
//  Touch : tap = play, long-press = sheet détail (cohérent avec
//  le reste de l'app).
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../domain/channel.dart';
import '../../domain/channel_genre.dart';
import '../genre_l10n.dart';
import 'channel_logo.dart';

class SearchResultCard extends StatelessWidget {
  const SearchResultCard({
    required this.channel,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ChannelGenre genre = channel.genre;
    final ChannelQuality quality = channel.quality;
    final CountryInfo? country = channel.country;

    // Hardening TV : on remplace Material+InkWell par TvFocusable
    // pour le focus ring ember télécommande. Mais l'InkWell d'origine
    // gérait aussi `onLongPress` (= ouvrir la sheet détail). On le
    // remet via un GestureDetector EXTERNE — le long-press ne crée pas
    // de conflit avec le tap car le framework dispatche selon le type
    // de geste. La télécommande ne déclenche que onTap (OK/Enter →
    // ActivateIntent) ; le long-press reste un raccourci doigt uniquement.
    return GestureDetector(
      onLongPress: onLongPress,
      child: TvFocusable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        showGlow: false,
        semanticsLabel: channel.cleanName,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ----- Logo + scrim + badges overlay -----
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ChannelLogo(
                      channel: channel,
                      size: ChannelLogoSize.large,
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.cardScrim,
                        ),
                      ),
                    ),
                    // Badge LIVE en haut à gauche
                    if (channel.isLive)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _LiveBadge(),
                      ),
                    // Badge qualité en haut à droite (si pas SD)
                    if (quality != ChannelQuality.sd)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _QualityBadge(quality: quality),
                      ),
                  ],
                ),
              ),
              // ----- Texte sous le visual -----
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      channel.cleanName,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Icon(
                          genre.icon,
                          size: 11,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            genre.localizedLabel(context.l10n),
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (country != null) ...<Widget>[
                          const SizedBox(width: 4),
                          Text(
                            country.flag,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.live,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            context.l10n.badgeLive,
            style: AppTextStyles.labelSmall.copyWith(
              color: Colors.white,
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.quality});
  final ChannelQuality quality;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.voidSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        quality.badge,
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.accent,
          fontSize: 9,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
