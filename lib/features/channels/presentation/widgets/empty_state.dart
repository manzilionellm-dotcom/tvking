// =========================================================
//  empty_state.dart — État "aucune chaîne pour l'instant"
// =========================================================
//  Premier écran que voit le client tout neuf qui n'a pas encore
//  reçu de playlist de son revendeur. Au lieu de lui demander de
//  taper une URL M3U lui-même (technique, source d'erreur), on
//  affiche son identifiant 7 MOTION + un bouton WhatsApp pour
//  l'envoyer directement au revendeur. Workflow MAG-portal :
//  client envoie sa MAC, admin active à distance, chaînes
//  arrivent automatiquement.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/branding/brand_logo.dart';
import '../../../../core/support/vip_support.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../device/data/device_identity.dart';

class EmptyStateView extends StatefulWidget {
  const EmptyStateView({
    required this.onAddPlaylist,
    super.key,
  });

  /// Conservé pour compatibilité (référencé encore par HomeScreen),
  /// mais plus appelé depuis cet écran — le client est censé passer
  /// par le revendeur via WhatsApp, pas ajouter une playlist lui-même.
  final VoidCallback onAddPlaylist;

  @override
  State<EmptyStateView> createState() => _EmptyStateViewState();
}

class _EmptyStateViewState extends State<EmptyStateView> {
  String? _mac;

  @override
  void initState() {
    super.initState();
    DeviceIdentity.instance.mac.then((String v) {
      if (mounted) setState(() => _mac = v);
    });
  }

  Future<void> _copy() async {
    if (_mac == null) return;
    await Clipboard.setData(ClipboardData(text: _mac!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Identifiant copié : $_mac',
            style: AppTextStyles.bodyMedium),
      ),
    );
  }

  Future<void> _sendWhatsApp() async {
    if (_mac == null) return;
    await VipSupport.openWhatsApp(
      customMessage:
          'Bonjour 7 MOTION, voici mon identifiant pour activer mes chaînes :\n\n$_mac',
    );
  }

  @override
  Widget build(BuildContext context) {
    final String display = _mac ?? 'MK:??:??:??:??:??';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BrandLogo.splash(),
                const SizedBox(height: 22),

                Text(
                  'Tes chaînes arrivent bientôt',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineLarge
                      .copyWith(fontSize: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  'Envoie ton identifiant à ton revendeur. Il active '
                  'tes chaînes à distance — elles apparaîtront ici '
                  'automatiquement.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),

                // ----- MAC en GROS -----
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.45),
                      width: 1.4,
                    ),
                    boxShadow: AppColors.champagneGlow,
                  ),
                  child: Column(
                    children: <Widget>[
                      Text('TON IDENTIFIANT',
                          style: AppTextStyles.eyebrow),
                      const SizedBox(height: 6),
                      SelectableText(
                        display,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ----- Bouton primaire : WhatsApp -----
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _mac == null ? null : _sendWhatsApp,
                    icon: const Icon(Icons.chat_rounded, size: 20),
                    label: const Text('Envoyer à mon revendeur'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      textStyle: AppTextStyles.button.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ----- Bouton secondaire : copier -----
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _mac == null ? null : _copy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copier l\'identifiant'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
