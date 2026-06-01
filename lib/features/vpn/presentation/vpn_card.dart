// =========================================================
//  vpn_card.dart — Carte VPN (V1 : stub UI)
// =========================================================
//  Le user a demandé "VPN intégré". Une vraie intégration
//  (WireGuard ou OpenVPN natif Android) demande 3-5 jours de
//  développement Kotlin + setup des serveurs côté backend.
//
//  V1 : carte informative qui :
//    - Annonce la feature (cohérent avec l'onboarding qui la liste)
//    - Explique pourquoi c'est utile (anonymat, contournement géo,
//      protection du flux IPTV vis-à-vis du FAI)
//    - Statut "Bientôt disponible" pour ne pas mentir au client
//    - Propose un workflow alternatif IMMÉDIAT : utiliser un VPN
//      tiers (Mullvad, NordVPN, ProtonVPN) au niveau système
//      Android — 7 MOTION fonctionne au-dessus comme tout app
//
//  V2 (hors scope ce sprint) :
//    - Intégration WireGuard via flutter_wireguard_dart ou bridge
//      natif Kotlin
//    - Sélection de pays sortie (FR, NL, US, etc.)
//    - Kill switch (bloque le trafic si VPN tombe)
//    - Auto-connect au boot
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class VpnCard extends StatelessWidget {
  const VpnCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.3),
          width: 1.1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'VPN intégré',
                      style: AppTextStyles.headlineMedium.copyWith(
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'BIENTÔT DISPONIBLE',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.accent,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Protège ton flux IPTV de ton FAI et contourne les '
            'restrictions géographiques. Connexion 1-tap, kill switch '
            'automatique, choix du pays de sortie.',
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppColors.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'En attendant : utilise un VPN tiers (Mullvad, '
                    'ProtonVPN, NordVPN…) au niveau Android. '
                    '7 MOTION fonctionne dessus sans config.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
