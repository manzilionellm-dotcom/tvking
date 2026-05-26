// =========================================================
//  channel_logo.dart — Logo de chaîne avec fallback élégant
// =========================================================
//  Composant clé du nouveau design.
//
//  Priorité :
//    1. Si on a un logoUrl valide → on le télécharge via
//       `cached_network_image` (cache disque automatique,
//        placeholder pendant le chargement, errorWidget si 404).
//    2. Sinon → on affiche un FALLBACK ÉLÉGANT et UNIFORME :
//       une carte sombre avec une icône de catégorie + les
//       initiales en typo monospace tabulaire.
//
//  Le fallback est délibérément SOBRE — pas de dégradés
//  aléatoires multicolores. Tous les fallbacks se ressemblent,
//  ce qui donne une cohérence visuelle même sur 20 000 chaînes.
//
//  3 tailles préréglées :
//    - .compact  : 48px (utilisé dans les listes denses)
//    - .medium   : 64-72px (vignettes mobiles)
//    - .large    : 96-120px (hero / detail)
// =========================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/channel.dart';

enum ChannelLogoSize { compact, medium, large }

class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    required this.channel,
    this.size = ChannelLogoSize.medium,
    this.borderRadius,
    super.key,
  });

  final Channel channel;
  final ChannelLogoSize size;
  final BorderRadius? borderRadius;

  double get _dimension {
    switch (size) {
      case ChannelLogoSize.compact:
        return 48;
      case ChannelLogoSize.medium:
        return 72;
      case ChannelLogoSize.large:
        return 120;
    }
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        borderRadius ?? BorderRadius.circular(_dimension * 0.18);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: _dimension,
        height: _dimension,
        child: channel.hasLogo
            ? _buildNetworkLogo(radius)
            : _buildFallback(),
      ),
    );
  }

  Widget _buildNetworkLogo(BorderRadius radius) {
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.all(_dimension * 0.08),
      child: CachedNetworkImage(
        imageUrl: channel.logoUrl!,
        fit: BoxFit.contain,
        // Pendant le chargement → fallback discret (pas de spinner
        // 20 000 spinners qui tournent en même temps = lag).
        placeholder: (BuildContext context, String url) => _buildFallback(),
        // Si l'URL 404 / DNS fail / format invalide → fallback.
        errorWidget: (BuildContext context, String url, dynamic error) =>
            _buildFallback(),
        memCacheWidth: (_dimension * 2).toInt(),
        memCacheHeight: (_dimension * 2).toInt(),
        fadeInDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  /// Fallback uniforme : carte sombre + icône genre + initiales.
  /// Pas de couleur aléatoire — cohérence sur 20k chaînes.
  Widget _buildFallback() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: AppColors.border,
          width: 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Icône de genre, très discrète en arrière-plan
          Positioned(
            right: _dimension * 0.08,
            bottom: _dimension * 0.08,
            child: Icon(
              channel.genre.icon,
              color: AppColors.textMuted.withValues(alpha: 0.4),
              size: _dimension * 0.28,
            ),
          ),
          // Initiales — la signature texte de la chaîne
          Text(
            channel.initials,
            style: TextStyle(
              fontSize: _dimension * 0.32,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: -0.5,
              fontFeatures: const <FontFeature>[
                FontFeature.tabularFigures(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge "Qualité" (HD / FHD / 4K / 8K) à afficher en surimpression
/// d'un logo. Style : pill discrète, lisible mais pas tape-à-l'œil.
class ChannelQualityBadge extends StatelessWidget {
  const ChannelQualityBadge({required this.quality, super.key});

  final ChannelQuality quality;

  @override
  Widget build(BuildContext context) {
    // On n'affiche pas la SD (par défaut) pour ne pas polluer.
    if (quality == ChannelQuality.sd) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _badgeColor.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Text(
        quality.badge,
        style: AppTextStyles.labelSmall.copyWith(
          color: _badgeColor,
          fontSize: 9,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color get _badgeColor {
    switch (quality) {
      case ChannelQuality.q8K:
        return AppColors.accent;
      case ChannelQuality.q4K:
        return AppColors.accent;
      case ChannelQuality.fhd:
        return AppColors.textSecondary;
      case ChannelQuality.hd:
        return AppColors.textSecondary;
      case ChannelQuality.sd:
        return AppColors.textMuted;
    }
  }
}
