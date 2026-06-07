// =========================================================
//  device_id_card.dart — Carte d'affichage du MAC virtuel
// =========================================================
//  Widget réutilisable qui affiche le MAC virtuel de l'app
//  (style MAG box : "MK:A3:B2:F1:8E:91") avec :
//    - Une typo monospace pour faciliter la lecture/dictée
//    - Un bouton "Copier" qui met la valeur dans le clipboard
//    - Une légende explicative pour le client final
//
//  Affichage à deux endroits :
//    - À propos (pour que le client puisse lire son ID)
//    - Réglages → Provisioning à distance (à côté de l'URL
//      de config, pour que l'admin sache quelle ligne du JSON
//      éditer pour ce client)
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/device_identity.dart';

class DeviceIdCard extends StatefulWidget {
  const DeviceIdCard({
    super.key,
    this.showCaption = true,
  });

  /// Affiche ou non la petite phrase explicative sous le MAC.
  /// On la masque dans certains contextes denses (Réglages) où
  /// le titre de la section suffit déjà à donner le contexte.
  final bool showCaption;

  @override
  State<DeviceIdCard> createState() => _DeviceIdCardState();
}

class _DeviceIdCardState extends State<DeviceIdCard> {
  String? _mac;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String value) {
      if (mounted) setState(() => _mac = value);
    });
  }

  Future<void> _copy() async {
    if (_mac == null) return;
    await Clipboard.setData(ClipboardData(text: _mac!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.idCopied(_mac!)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String display = _mac ?? 'MK:??:??:??:??:??';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.fingerprint_rounded,
                color: AppColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.deviceIdLabel,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  display,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.accent,
                  ),
                ),
              ),
              IconButton(
                onPressed: _mac == null ? null : _copy,
                tooltip: context.l10n.buttonCopy,
                icon: const Icon(Icons.copy_rounded),
                color: AppColors.textPrimary,
              ),
            ],
          ),
          if (widget.showCaption) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              context.l10n.deviceIdCaption,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 11,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
