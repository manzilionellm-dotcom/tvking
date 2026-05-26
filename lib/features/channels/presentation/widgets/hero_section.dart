// =========================================================
//  hero_section.dart — Bannière "vedette" Premium v2
// =========================================================
//  Refonte Phase 1.4 :
//    - Plus de gradient coloré géant aux couleurs aléatoires
//    - Card sombre élégante avec :
//        * Logo de la chaîne BIEN visible à gauche
//        * Bloc texte propre (nom, genre, pays, programme)
//        * Bouton "Lecture" doré (l'unique accent) en CTA
//        * Bouton "Détails" secondaire
//    - Discret badge LIVE en haut à gauche
//    - Badge "VEDETTE" doré en haut à droite
//
//  L'idée : la vedette doit RENDRE HOMMAGE à la marque de la
//  chaîne (donc montrer son logo), pas l'effacer derrière des
//  effets visuels.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/live_badge.dart';
import '../../domain/channel.dart';
import 'channel_logo.dart';

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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Stack(
          children: <Widget>[
            // ----- Halo doré subtil en arrière-plan -----
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: 1.2,
                      colors: <Color>[
                        AppColors.accent.withValues(alpha: 0.07),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ----- Contenu -----
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: <Widget>[
                  // ----- Logo à gauche -----
                  Stack(
                    children: <Widget>[
                      ChannelLogo(
                        channel: channel,
                        size: ChannelLogoSize.large,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      if (channel.isLive)
                        const Positioned(
                          top: 6,
                          left: 6,
                          child: LiveBadge(),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // ----- Texte à droite -----
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Mini chip "VEDETTE"
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accentSurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.accent
                                  .withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'VEDETTE',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.accent,
                              fontSize: 9,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Nom de la chaîne
                        Text(
                          channel.cleanName,
                          style: AppTextStyles.headlineLarge.copyWith(
                            fontSize: 22,
                            height: 1.15,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),

                        // Metadata (genre + pays + qualité)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: <Widget>[
                            _metaChip(
                              icon: channel.genre.icon,
                              text: channel.genre.label,
                            ),
                            if (channel.country != null)
                              _metaChip(
                                text:
                                    '${channel.country!.flag} ${channel.country!.name}',
                              ),
                            if (channel.quality != ChannelQuality.sd)
                              ChannelQualityBadge(quality: channel.quality),
                          ],
                        ),

                        // Programme en cours (Phase 2)
                        if (channel.currentProgram != null) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            channel.currentProgram!,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 14),

                        // ----- Boutons d'action (Wrap pour
                        //       éviter l'overflow sur petits écrans
                        //       avec des noms de chaîne longs) -----
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _PrimaryButton(
                              icon: Icons.play_arrow_rounded,
                              label: 'Lecture',
                              onPressed: onWatch,
                            ),
                            _SecondaryButton(
                              icon: Icons.info_outline_rounded,
                              label: 'Détails',
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
          ],
        ),
      ),
    );
  }

  Widget _metaChip({IconData? icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: AppColors.textSecondary),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: Colors.black),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.bodyLarge.copyWith(
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
