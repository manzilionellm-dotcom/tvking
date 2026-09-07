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
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/app/build_info.dart' show kBuildLabel;
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

  //  LE NUMÉRO DE VERSION, JUSTE SOUS LA MAC (07/09/2026).
  //
  //  Même décision que sur la box, et pour la même raison de terrain :
  //  cette carte-là est DÉJÀ celle qu'on lit au téléphone quand on
  //  active un appareil ou qu'on dépanne un client. Les deux questions
  //  du support sont « qui est cet appareil ? » et « quelle version
  //  fait-il tourner ? » — elles doivent tenir dans le même regard.
  //
  //  Repli sur le numéro technique du paquet quand le numéro maison
  //  n'est pas gravé (compilation locale, ou APK antérieur au 07/09) :
  //  le support a toujours quelque chose à faire lire au client.
  String _buildLabel = kBuildLabel;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String value) {
      if (mounted) setState(() => _mac = value);
    });
    if (_buildLabel.isEmpty) {
      PackageInfo.fromPlatform().then((PackageInfo p) {
        if (mounted) setState(() => _buildLabel = p.buildNumber);
      });
    }
  }

  Future<void> _copy() async {
    if (_mac == null) return;
    // Code NU (sans « MK: ») : évite le doublon dans le panel revendeur.
    final String nu = DeviceIdentity.stripPrefix(_mac!);
    await Clipboard.setData(ClipboardData(text: nu));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.idCopied(nu)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String display =
        _mac == null ? '??:??:??:??:??' : DeviceIdentity.stripPrefix(_mac!);
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
          // ----- Numéro de version, sous la MAC -----
          if (_buildLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  '${context.l10n.tvAboutVersionBuildLabel} : ',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  _buildLabel,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
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
