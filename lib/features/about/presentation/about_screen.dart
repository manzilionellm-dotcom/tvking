// =========================================================
//  about_screen.dart — À propos de TV King
// =========================================================
//  - Logo + version + n° de build
//  - Bouton "Vérifier les mises à jour" → ping GitHub
//  - Liens : GitHub, politique de confidentialité, CGU
//  - Crédits (Flutter, media_kit, libmpv, sqflite, etc.)
//  - Mention "Lecteur média générique"
// =========================================================

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/support/vip_help_card.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../device/presentation/device_id_card.dart';
import '../data/update_checker.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _pkg;
  UpdateInfo? _update;
  bool _checking = false;
  String? _checkError;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((PackageInfo p) {
      if (mounted) setState(() => _pkg = p);
    });
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _checkError = null;
    });
    final UpdateInfo? info = await UpdateChecker.instance.check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _update = info;
      if (info == null) {
        _checkError =
            'Impossible de contacter le serveur de mises à jour. Vérifie ta connexion.';
      }
    });
  }

  Future<void> _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('À propos'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ----- Hero logo + nom -----
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: <Widget>[
                  const BrandLogo.medium(),
                  const SizedBox(height: 16),
                  Text(
                    BrandStrings.appName,
                    style: AppTextStyles.headlineLarge.copyWith(
                      letterSpacing: 4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lecteur IPTV premium',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  if (_pkg != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'v${_pkg!.version} • build ${_pkg!.buildNumber}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ----- Aide VIP — accessible en premier après le hero -----
            const VipHelpCard.full(),

            const SizedBox(height: 20),

            // ----- Identifiant unique de cet appareil -----
            //  Sert à associer l'appareil à un abonnement côté admin.
            _section(
              icon: Icons.fingerprint_rounded,
              title: 'Mon appareil',
              child: const DeviceIdCard(),
            ),

            const SizedBox(height: 20),

            // ----- Update checker -----
            _section(
              icon: Icons.system_update_rounded,
              title: 'Mises à jour',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_update != null && _update!.hasUpdate)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.accentSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.accent
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(Icons.celebration_rounded,
                                  color: AppColors.accent, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Nouvelle version disponible',
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'v${_update!.latestVersion} '
                            '(toi : v${_update!.currentVersion})',
                            style: AppTextStyles.bodyMedium,
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _openUrl(_update!.releaseUrl),
                            icon: const Icon(Icons.open_in_new_rounded,
                                size: 16),
                            label: const Text('Voir les notes de version'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              side: BorderSide(
                                color: AppColors.accent
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_update != null && !_update!.hasUpdate)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.check_circle_rounded,
                              color: AppColors.success, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Tu as la dernière version (v${_update!.latestVersion}).',
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  if (_checkError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _checkError!,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.live),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _checking ? null : _checkForUpdates,
                    icon: _checking
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(_checking
                        ? 'Vérification...'
                        : 'Vérifier les mises à jour'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ----- Liens -----
            _section(
              icon: Icons.link_rounded,
              title: 'Liens utiles',
              child: Column(
                children: <Widget>[
                  _linkTile(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Politique de confidentialité',
                    onTap: () => _openUrl(
                      'https://7motion.app/privacy',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ----- Crédits -----
            _section(
              icon: Icons.favorite_outline_rounded,
              title: 'Construit avec',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _creditLine('Flutter', 'Framework UI multiplateforme'),
                  _creditLine('media_kit · libmpv',
                      'Moteur vidéo (HLS, MPEG-TS, MP4)'),
                  _creditLine('sqflite', 'Stockage local des playlists'),
                  _creditLine('cached_network_image',
                      'Cache disque des logos'),
                  _creditLine(
                      'Google Fonts (Inter)', 'Typographie premium'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ----- Mention légale -----
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '7 MOTION est un lecteur média générique. Aucun contenu n\'est '
                'inclus avec l\'app. Tu es responsable des sources que tu '
                'ajoutes et de leur conformité aux lois en vigueur dans '
                'ton pays.',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTextStyles.headlineMedium.copyWith(fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _linkTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: <Widget>[
              Icon(icon, color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 14),
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                color: AppColors.textMuted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _creditLine(String name, String role) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            name,
            style: AppTextStyles.bodyLarge.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '— $role',
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
