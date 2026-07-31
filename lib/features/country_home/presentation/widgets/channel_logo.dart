// =========================================================
//  channel_logo.dart — Logo de chaîne + fallback initiales
// =========================================================
//  Affiche `tvg-logo` s'il charge (contain, fond neutre). Sinon (vide
//  ou erreur), génère une vignette à initiales avec une couleur
//  déterministe (cf. channel_curation). Fallback INSTANTANÉ (pas de
//  flash, pas de spinner). Aucune dépendance au cast.
// =========================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../channels/domain/channel.dart';
import '../../data/channel_curation.dart';

class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.channel,
    this.size = 52,
    this.radius = 14,
  });

  final Channel channel;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String? url = channel.logoUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: (url == null || url.isEmpty)
            ? _fallback()
            // CachedNetworkImage : cache DISQUE en plus du borné mémoire.
            // useOldImageOnUrlChange = l'équivalent du gaplessPlayback
            // d'Image.network ; placeholder = fallback (zéro flash, zéro
            // spinner, construit PARESSEUSEMENT — pas à chaque frame de
            // scroll quand le logo est déjà en cache) ; imageBuilder =
            // même fond neutre qu'avant.
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.contain,
                memCacheWidth: (size * 3).round(),
                // Borne les DEUX axes : un logo très haut (400×2000)
                // n'explose plus la mémoire malgré le contain.
                memCacheHeight: (size * 3).round(),
                useOldImageOnUrlChange: true,
                // Apparition VIVE : le fondu par défaut (500 ms) donnait une
                // impression de lenteur pendant le défilement.
                fadeInDuration: const Duration(milliseconds: 150),
                errorWidget: (_, __, ___) => _fallback(),
                placeholder: (_, __) => _fallback(),
                imageBuilder:
                    (BuildContext c, ImageProvider<Object> provider) {
                  // Image prête → on la pose sur un fond neutre.
                  return Container(
                    color: AppColors.maisonSurfaceHigh,
                    alignment: Alignment.center,
                    padding: EdgeInsets.all(size * 0.12),
                    child: Image(
                        image: provider,
                        fit: BoxFit.contain,
                        gaplessPlayback: true),
                  );
                },
              ),
      ),
    );
  }

  Widget _fallback() {
    final Color base = logoFallbackColor(channel.name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            base,
            Color.lerp(base, Colors.black, 0.5) ?? base,
          ],
        ),
      ),
      child: Text(
        logoInitials(channel.name),
        style: AppTextStyles.maisonInitials.copyWith(fontSize: size * 0.32),
      ),
    );
  }
}
