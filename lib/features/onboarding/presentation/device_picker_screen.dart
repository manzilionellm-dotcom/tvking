// =========================================================
//  device_picker_screen.dart — "Téléphone ou Télévision ?"
// =========================================================
//  Premier écran à la première ouverture. Précède l'onboarding.
//  3 cartes XL :
//    - Téléphone : layout tactile compact
//    - Télévision : layout XL focus-aware (D-pad / télécommande)
//    - Détection auto : on devine au runtime
//
//  Le choix est persisté dans `DeviceClassRepository`. Il peut
//  être changé plus tard dans Réglages → Apparence.
//
//  Design Maison Noir / 7 MOTION : surfaces charcoal, accents
//  ember, focus rings accentEmber-bright. Aucune décoration
//  superflue — on respire, on choisit, on continue.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/branding/verified_badge.dart';
import '../../../core/flavor/flavor.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/device_class_repository.dart';

class DevicePickerScreen extends StatefulWidget {
  const DevicePickerScreen({required this.onDone, super.key});

  /// Appelé une fois que l'utilisateur a confirmé son choix.
  final VoidCallback onDone;

  @override
  State<DevicePickerScreen> createState() => _DevicePickerScreenState();
}

class _DevicePickerScreenState extends State<DevicePickerScreen> {
  DeviceClass? _selected;
  bool _saving = false;

  Future<void> _confirm() async {
    final DeviceClass? choice = _selected;
    if (choice == null) return;
    setState(() => _saving = true);
    await DeviceClassRepository.instance.setChoice(choice);
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          // Halo ember en arrière-plan
          Positioned(
            top: -160,
            right: -120,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.accent.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // ----- Header brand (avec badge ✓ après MOTION) -----
                  Row(
                    children: <Widget>[
                      const BrandLogo.compact(),
                      const SizedBox(width: 12),
                      Text(
                        FlavorConfig.current.appName,
                        style: AppTextStyles.headlineLarge.copyWith(
                          fontSize: 18,
                          letterSpacing: 3.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const VerifiedBadge.small(),
                    ],
                  ),
                  const SizedBox(height: 56),

                  // ----- Question -----
                  Text(
                    'Tu es sur quoi ?',
                    style: AppTextStyles.displayLarge.copyWith(
                      fontSize: 36,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'On adapte l\'expérience à ton appareil. Tu pourras '
                    'changer ce choix dans les Réglages.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // ----- Cartes -----
                  //  Sur téléphone portrait les 3 cartes ne rentrent
                  //  pas en hauteur — on les rend scrollables. Sur
                  //  desktop / TV large on garde les 3 colonnes
                  //  côte à côte sans scroll.
                  Expanded(
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(child: _phoneCard()),
                              const SizedBox(width: 14),
                              Expanded(child: _tvCard()),
                              const SizedBox(width: 14),
                              Expanded(child: _autoCard()),
                            ],
                          )
                        : SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              children: <Widget>[
                                _phoneCard(),
                                const SizedBox(height: 12),
                                _tvCard(),
                                const SizedBox(height: 12),
                                _autoCard(),
                                // Petit espace pour ne pas que la
                                // 3e carte se retrouve collée au
                                // bouton "Continuer" en bas.
                                const SizedBox(height: 4),
                              ],
                            ),
                          ),
                  ),

                  const SizedBox(height: 14),

                  // ----- CTA -----
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed:
                          (_selected == null || _saving) ? null : _confirm,
                      child: Text(
                        _saving ? 'Préparation…' : 'Continuer',
                        style: AppTextStyles.button.copyWith(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneCard() => _DeviceCard(
        icon: Icons.smartphone_rounded,
        title: 'Téléphone',
        subtitle: 'Smartphone, tablette',
        description:
            'Interface tactile compacte. Navigation au doigt, '
            'mini-player et écran plein écran fluides.',
        selected: _selected == DeviceClass.phone,
        onTap: () => setState(() => _selected = DeviceClass.phone),
      );

  Widget _tvCard() => _DeviceCard(
        icon: Icons.tv_rounded,
        title: 'Télévision',
        subtitle: 'Android TV, Fire TV, Google TV',
        description:
            'Layout XL pour télécommande. Focus rings visibles à 3 m, '
            'tailles cinéma, raccourcis D-pad.',
        selected: _selected == DeviceClass.tv,
        onTap: () => setState(() => _selected = DeviceClass.tv),
      );

  Widget _autoCard() => _DeviceCard(
        icon: Icons.auto_awesome_rounded,
        title: 'Auto',
        subtitle: 'Détection automatique',
        description:
            'L\'app devine d\'après ton écran. Bon choix si tu ne sais '
            'pas, ou si tu utilises plusieurs appareils.',
        selected: _selected == DeviceClass.auto,
        onTap: () => setState(() => _selected = DeviceClass.auto),
      );
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected ? AppColors.emberGlowShadow : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.accent
                      : AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: selected
                      ? AppColors.voidSurface
                      : AppColors.accent,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: AppTextStyles.headlineMedium.copyWith(
                  color: selected
                      ? AppColors.accent
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                description,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
