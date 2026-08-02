// =========================================================
//  demo_banner.dart — « Tu es en démo », et la porte de sortie
// =========================================================
//  Un client qui croit avoir un abonnement alors qu'il regarde une
//  démonstration, c'est un litige — et un remboursement. Le bandeau est
//  donc PERMANENT tant que la démo tourne : il le dit, et il donne la
//  sortie dans le même geste. Pas de petite icône discrète.
//
//  Il porte aussi l'accès au guide « Comment ça marche » : c'est là que
//  le nouvel arrivant le cherchera, puisque c'est le seul élément à
//  l'écran qui parle de la démo.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/demo_mode.dart';
import 'demo_guide_screen.dart';

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DemoMode.instance,
      builder: (BuildContext context, Widget? _) {
        if (!DemoMode.instance.isActive) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.accentSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.play_lesson_rounded,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Mode démo',
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ces chaînes sont des exemples. Ajoute ta source pour '
                      'voir les tiennes.',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const DemoGuideScreen(),
                  ),
                ),
                child: const Text('Guide'),
              ),
              TextButton(
                onPressed: () => DemoMode.instance.exit(),
                child: const Text('Quitter'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Le bouton d'ENTRÉE, posé sur l'écran vide : c'est la seule chose à
/// faire quand on n'a pas encore de source, à part attendre.
class DemoEntryButton extends StatelessWidget {
  const DemoEntryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DemoMode.instance,
      builder: (BuildContext context, Widget? _) {
        if (DemoMode.instance.isActive) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: OutlinedButton.icon(
            onPressed: () => DemoMode.instance.enter(),
            icon: const Icon(Icons.play_lesson_rounded),
            label: const Text('Essayer en mode démo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        );
      },
    );
  }
}
