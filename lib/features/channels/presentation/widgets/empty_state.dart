// =========================================================
//  empty_state.dart — État "aucune playlist ajoutée"
// =========================================================
//  Premier écran que voit l'utilisateur tout neuf : une
//  invitation chaleureuse à ajouter sa playlist, avec un CTA
//  visible et — surtout — un accès direct au support VIP
//  pour l'utilisateur perdu qui ne sait pas quoi faire.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/branding/brand_logo.dart';
import '../../../../core/support/vip_help_card.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.onAddPlaylist,
    super.key,
  });

  final VoidCallback onAddPlaylist;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // ----- Logo 7 MOTION halo ember -----
                const BrandLogo.splash(),
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

                // ----- CTA primaire ember -----
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: onAddPlaylist,
                    icon: const Icon(Icons.add_rounded, size: 22),
                    label: const Text('Ajouter une playlist'),
                  ),
                ),

                const SizedBox(height: 28),
                Container(
                  height: 1,
                  width: 80,
                  color: AppColors.border,
                ),
                const SizedBox(height: 20),

                // ----- Aide VIP — accessible direct depuis l'empty -----
                //  C'est exactement quand l'utilisateur ne sait pas
                //  quoi faire qu'il a besoin de nous joindre. Visible,
                //  proche du CTA, mais discret pour ne pas voler la
                //  vedette au bouton "Ajouter".
                const VipHelpCard.full(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
