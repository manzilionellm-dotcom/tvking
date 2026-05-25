// =========================================================
//  empty_state.dart — État "aucune playlist ajoutée"
// =========================================================
//  Premier écran que voit l'utilisateur tout neuf : une
//  invitation chaleureuse à ajouter sa playlist, avec un CTA
//  visible et un visuel cohérent VIP.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.onAddPlaylist,
    super.key,
  });

  final VoidCallback onAddPlaylist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Cercle décoratif avec icône
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: <Color>[
                    AppColors.accentPink.withValues(alpha: 0.6),
                    AppColors.accentCyan.withValues(alpha: 0.6),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.accentPink.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.live_tv_rounded,
                color: Colors.white,
                size: 56,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Aucune chaîne pour l\'instant',
              style: AppTextStyles.headlineLarge.copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Ajoute ta première playlist IPTV — M3U ou Xtream Codes.\n'
              'Tes chaînes apparaîtront automatiquement.',
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onAddPlaylist,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentPink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 22),
                label: const Text('Ajouter une playlist'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
