// =========================================================
//  age_gate_screen.dart — Modal "Vous avez 18 ans ou plus ?"
// =========================================================
//  Premier écran que voit l'utilisateur de Red Room après le
//  splash. Une seule fois (puis mémorisé en SharedPreferences).
//
//  UX :
//    - Logo "R" + tagline STRICTLY 18+
//    - Texte court rappelant la nature du service
//    - Deux boutons : "J'AI 18 ANS OU PLUS" (CTA rouge) /
//      "Quitter" (texte clair)
//    - Une note légale en pied : la responsabilité de l'âge
//      réel revient à l'utilisateur
//
//  Sur refus : on appelle SystemNavigator.pop() qui tente de
//  fermer l'app (Android). Sur iOS ce sera ignoré (Apple ne
//  permet pas la sortie programmatique) — l'app reste sur cet
//  écran tant que l'user ne change pas d'avis ou ne ferme pas
//  manuellement (peu importe : pas d'iOS pour Red Room de toute
//  façon, Apple refuse l'adulte du store).
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/cinematic_spacing.dart';
import '../data/age_gate_settings.dart';

class AgeGateScreen extends StatelessWidget {
  const AgeGateScreen({required this.onConfirmed, super.key});

  /// Callback appelé une fois la confirmation enregistrée.
  /// L'app peut alors basculer vers le verrou biométrique
  /// (puis l'écran d'accueil).
  final VoidCallback onConfirmed;

  Future<void> _confirm() async {
    await AgeGateSettings.instance.markConfirmed();
    onConfirmed();
  }

  Future<void> _decline() async {
    // Sur Android, tente de quitter l'app. SystemNavigator.pop()
    // appelle Activity.finish() sur la MainActivity, ce qui
    // ramène à l'écran d'accueil système.
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidSurface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CinematicSpacing.l,
                vertical: CinematicSpacing.xl,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Spacer(),

                  // Logo Red Room officiel (R stylise + silhouette
                  // + 'RED ROOM 18+', livre par l'utilisateur). Le
                  // PNG inclut deja le wordmark + le badge 18+ donc
                  // on ne re-affiche PAS 'Red Room' ni la tagline
                  // en dessous — ce serait redondant et nuirait a
                  // la composition.
                  const Center(child: BrandLogo.splash()),

                  const SizedBox(height: CinematicSpacing.xxl),

                  // Bloc d'avertissement
                  Container(
                    padding: const EdgeInsets.all(CinematicSpacing.m),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          BorderRadius.circular(CinematicSpacing.radiusL),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Contenu réservé aux adultes',
                          style: AppTextStyles.headlineMedium.copyWith(
                            fontSize: 17,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: CinematicSpacing.xs),
                        Text(
                          'Cette application diffuse des programmes '
                          'à caractère explicite réservés aux personnes '
                          'majeures. En continuant, vous déclarez sur '
                          'l\'honneur avoir atteint l\'âge légal de '
                          'majorité dans votre pays.',
                          style: AppTextStyles.bodyLarge.copyWith(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: CinematicSpacing.xl),

                  // CTA principal — j'ai 18+
                  _PrimaryButton(
                    label: "J'AI 18 ANS OU PLUS — ENTRER",
                    onPressed: _confirm,
                  ),
                  const SizedBox(height: CinematicSpacing.s),
                  _GhostButton(
                    label: 'Quitter',
                    onPressed: _decline,
                  ),

                  const Spacer(),

                  // Note légale en pied
                  Text(
                    'En cas de fausse déclaration, la responsabilité '
                    'incombe exclusivement à l\'utilisateur.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 0.6,
                      height: 1.6,
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

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(CinematicSpacing.radiusM),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(CinematicSpacing.radiusM),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          label,
          style: AppTextStyles.button.copyWith(
            color: Colors.black,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: AppTextStyles.button.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
