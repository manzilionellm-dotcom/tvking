// =========================================================
//  qr_cast_sheet.dart — Cast par QR Code (multi-device)
// =========================================================
//  Bottom sheet qui génère un QR code contenant l'URL du flux
//  en cours de lecture. N'importe quel autre appareil (TV, ordi,
//  tablette, autre tel) peut scanner ce QR depuis son navigateur
//  ou une app caméra pour lancer la lecture.
//
//  Avantages vs Chromecast classique :
//    - Marche avec TOUT device qui a une caméra + un navigateur
//      (PAS besoin de DIAL, SSDP, Cast SDK Google)
//    - Marche cross-OS : iPad lit le QR généré sur Android, etc.
//    - Aucune compatibilité réseau requise (pas de mDNS, pas de
//      UPnP), juste un coup d'œil de la caméra
//    - Le destinataire peut copier l'URL dans VLC / IINA / mpv
//
//  Demande user : "caste n'importe quel appareil tv ordi tablt
//  via qr code".
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Ouvre une bottom sheet plein écran avec le QR code du flux
/// courant. `streamUrl` doit être une URL ABSOLUE valide (M3U8,
/// MPEG-TS, MP4, etc.) — pas de credentials Xtream encodés.
Future<void> showQrCastSheet(
  BuildContext context, {
  required String streamUrl,
  required String channelName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext ctx) {
      return SafeArea(
        top: false,
        child: _QrCastBody(
          streamUrl: streamUrl,
          channelName: channelName,
        ),
      );
    },
  );
}

class _QrCastBody extends StatelessWidget {
  const _QrCastBody({
    required this.streamUrl,
    required this.channelName,
  });

  final String streamUrl;
  final String channelName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ----- Drag handle -----
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ----- Header -----
          Row(
            children: <Widget>[
              Icon(Icons.qr_code_2_rounded,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cast par QR Code',
                  style: AppTextStyles.headlineMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Scanne ce code depuis n\'importe quel appareil '
            '(TV, ordi, tablette, autre téléphone) pour y '
            'lancer la lecture du flux.',
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),

          // ----- QR centré -----
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.18),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: QrImageView(
                data: streamUrl,
                size: 260,
                version: QrVersions.auto,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                gapless: true,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ----- Nom de la chaîne -----
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              channelName,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),

          // ----- Copier l'URL (fallback si pas de caméra) -----
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: streamUrl));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.surfaceHigh,
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                  duration: const Duration(seconds: 2),
                  content: Text(
                    'URL copiée — colle-la dans VLC / navigateur',
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copier l\'URL du flux'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(
                color: AppColors.accent.withValues(alpha: 0.6),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ----- Tip d'usage -----
          Text(
            'Astuce : ouvre l\'appareil photo de ton autre device, '
            'pointe vers ce QR — un lien apparaît. Ouvre-le dans '
            'le navigateur ou colle dans VLC.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 10.5,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
