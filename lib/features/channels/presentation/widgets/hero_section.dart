// =========================================================
//  hero_section.dart — Bannière vedette de l'accueil
// =========================================================
//  Grand panneau en haut de l'écran d'accueil qui met en
//  valeur UNE chaîne (la première de la playlist, ou la
//  dernière regardée plus tard, ou la chaîne avec le
//  programme le plus populaire — au choix).
//
//  Quand la Phase 1.3 (lecteur vidéo) sera là, ce panneau
//  affichera un APERÇU VIDÉO en arrière-plan (mute par
//  défaut, comme YouTube/Netflix). Pour l'instant, dégradé
//  + initiales géantes en placeholder.
//
//  Boutons d'action :
//    - "Regarder" → ouvre la chaîne en plein écran (à brancher)
//    - "Plus d'infos" → ouvre la fiche détaillée (à brancher)
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/live_badge.dart';
import '../../domain/channel.dart';

class HeroSection extends StatelessWidget {
  const HeroSection({
    required this.channel,
    required this.onWatch,
    required this.onInfo,
    super.key,
  });

  final Channel channel;
  final VoidCallback onWatch;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final List<Color> gradient = channel.gradientColors ??
        <Color>[AppColors.surface, AppColors.surfaceHigh];

    return AspectRatio(
      // Format paysage généreux pour l'effet "cinéma".
      // Sur téléphone vertical, ça occupe ~40% de la hauteur d'écran.
      aspectRatio: 16 / 11,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: <Widget>[
            // ---------- Fond dégradé pleine surface ----------
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
              ),
            ),

            // Initiales translucides géantes en arrière-plan
            Positioned.fill(
              child: Align(
                alignment: const Alignment(0.6, -0.3),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    channel.initials,
                    style: AppTextStyles.channelInitials.copyWith(
                      fontSize: 200,
                      color: Colors.white.withValues(alpha: 0.18),
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),

            // Bouton "Play" central translucide (l'utilisateur sait
            // que c'est "lisible" même sans avoir le lecteur encore)
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),

            // ---------- Voile sombre en bas (lisibilité texte) ----------
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),

            // ---------- Badge LIVE en haut à gauche ----------
            if (channel.isLive)
              const Positioned(
                top: 16,
                left: 16,
                child: LiveBadge(),
              ),

            // ---------- Badge "VEDETTE" en haut à droite ----------
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Text(
                  'VEDETTE',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: Colors.black,
                    fontSize: 10,
                  ),
                ),
              ),
            ),

            // ---------- Contenu bas : nom + programme + boutons ----------
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Catégorie en petit cyan
                  Text(
                    channel.category.toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.accentCyan,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Nom de la chaîne en très gros
                  Text(
                    channel.name,
                    style: AppTextStyles.headlineLarge.copyWith(fontSize: 26),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Programme en cours
                  if (channel.currentProgram != null)
                    Text(
                      channel.currentProgram!,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 14),
                  // Boutons d'action
                  Row(
                    children: <Widget>[
                      _HeroButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'Regarder',
                        isPrimary: true,
                        onPressed: onWatch,
                      ),
                      const SizedBox(width: 10),
                      _HeroButton(
                        icon: Icons.info_outline_rounded,
                        label: 'Plus d\'infos',
                        isPrimary: false,
                        onPressed: onInfo,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton compact du Hero — version primaire (blanche)
/// et version secondaire (semi-transparente).
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isPrimary
                ? Colors.white
                : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: isPrimary
                ? null
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1,
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: isPrimary ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isPrimary ? Colors.black : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
