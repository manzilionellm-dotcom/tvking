// =========================================================
//  forced_update_screen.dart — Écran bloquant "mets à jour"
// =========================================================
//  S'affiche À LA PLACE de l'app quand la version installée est
//  obsolète (cf. kBuildTs vs dernière version publiée, calcul dans
//  _AppEntry). L'utilisateur ne peut PAS continuer sans installer la
//  nouvelle version :
//    - sur TV / box : il tape le code Downloader affiché ;
//    - sur téléphone : bouton "Télécharger" qui ouvre le lien anonyme.
//  Un bouton "Réessayer" relance la vérification une fois l'app
//  mise à jour réinstallée.
// =========================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app/build_info.dart';
import '../../../core/branding/brand_logo.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class ForcedUpdateScreen extends StatelessWidget {
  const ForcedUpdateScreen({super.key, required this.onRetry});

  /// Relance la vérification (appelé par "J'ai mis à jour").
  final VoidCallback onRetry;

  Future<void> _download() async {
    final Uri? uri = Uri.tryParse(kDownloadUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const BrandLogo.medium(),
                  const SizedBox(height: 28),
                  Icon(Icons.system_update_rounded,
                      color: AppColors.accent, size: 56),
                  const SizedBox(height: 18),
                  Text(
                    context.l10n.forceUpdateTitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headlineLarge.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.forceUpdateBody,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 26),

                  // Bloc code Downloader (TV / box).
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        Text(
                          context.l10n.forceUpdateDownloaderHint,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.labelSmall.copyWith(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          kDownloaderCode,
                          style: AppTextStyles.headlineLarge.copyWith(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: AppColors.accent,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Bouton téléchargement direct (téléphone).
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _download,
                      icon: const Icon(Icons.download_rounded),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.voidSurface,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      label: Text(
                        context.l10n.forceUpdateDownloadBtn,
                        style: AppTextStyles.button.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.voidSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(
                      context.l10n.forceUpdateRetry,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
