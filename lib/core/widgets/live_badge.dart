// =========================================================
//  live_badge.dart — Badge "EN DIRECT" avec pulse rouge
// =========================================================
//  Petit composant animé qu'on plante en haut à gauche des
//  vignettes des chaînes diffusant en live.
//
//  L'animation "pulse" est faite avec un AnimationController
//  qui fait varier la taille et l'opacité d'un cercle rouge.
// =========================================================

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key});

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

// `with SingleTickerProviderStateMixin` : indispensable pour
// pouvoir créer un AnimationController dans ce State.
// "Ticker" = horloge interne de Flutter qui pulse à 60/120 fps.
class _LiveBadgeState extends State<LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true); // pulse continu (aller-retour)
  }

  @override
  void dispose() {
    // TRÈS IMPORTANT : on libère le controller pour éviter
    // une fuite mémoire quand le widget disparaît.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.live,
        borderRadius: BorderRadius.circular(6),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.live.withValues(alpha: 0.5),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Le petit point qui pulse
          AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              return Container(
                width: 6 + (_controller.value * 2), // 6 → 8 px
                height: 6 + (_controller.value * 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: 0.6 + (_controller.value * 0.4), // 0.6 → 1.0
                  ),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Text(
            'EN DIRECT',
            style: AppTextStyles.labelSmall.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}
