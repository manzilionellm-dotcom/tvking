// =========================================================
//  channel_logo.dart — Logo de chaîne + fallback initiales
// =========================================================
//  Affiche `tvg-logo` s'il charge (contain, fond neutre). Sinon (vide
//  ou erreur), génère une vignette à initiales avec une couleur
//  déterministe (cf. channel_curation). Fallback INSTANTANÉ (pas de
//  flash, pas de spinner). Aucune dépendance au cast.
// =========================================================

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
    final Widget fallback = _fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: (url == null || url.isEmpty)
            ? fallback
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.contain,
                cacheWidth: (size * 3).round(),
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => fallback,
                frameBuilder: (BuildContext c, Widget child, int? frame,
                    bool wasSync) {
                  // Image prête → on la pose sur un fond neutre. Sinon, on
                  // montre le fallback (zéro flash, zéro spinner).
                  if (wasSync || frame != null) {
                    return Container(
                      color: AppColors.maisonSurfaceHigh,
                      alignment: Alignment.center,
                      padding: EdgeInsets.all(size * 0.12),
                      child: child,
                    );
                  }
                  return fallback;
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
