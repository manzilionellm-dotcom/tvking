// =========================================================
//  demo_guide_screen.dart — « Comment ça marche », en cinq gestes
// =========================================================
//  Le client voulait des flèches sur les écrans. On fait autrement, et
//  volontairement : une flèche dessinée sur une capture se périme au
//  premier bouton déplacé, et personne ne pense à la refaire. Ici, cinq
//  étapes numérotées qui nomment l'écran et le geste — ça survit aux
//  retouches d'interface, et ça se traduit.
//
//  Le contenu vit dans `DemoMode.lessons` : le même texte alimente cet
//  écran et les fiches « Guide » du cinéma de démo, sans doublon.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/demo_mode.dart';

class DemoGuideScreen extends StatelessWidget {
  const DemoGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Comment ça marche')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Text(
            'Cinq gestes, et tu sais tout faire.',
            style: AppTextStyles.headlineMedium
                .copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'L\'application est un lecteur : elle ne fournit aucune chaîne. '
            'Ce que tu vois en démo sont des exemples.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          for (final DemoLesson l in DemoMode.lessons) _Step(lesson: l),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: DemoMode.instance,
            builder: (BuildContext context, Widget? _) {
              if (!DemoMode.instance.isActive) return const SizedBox.shrink();
              return FilledButton.icon(
                onPressed: () {
                  DemoMode.instance.exit();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Quitter le mode démo'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.lesson});

  final DemoLesson lesson;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Le numéro, puis la FLÈCHE : c'est elle qui donne le sens de
          // lecture que le client réclamait, sans figer une capture.
          Column(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentSurface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  '${lesson.step}',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Icon(Icons.arrow_downward_rounded,
                  size: 16, color: AppColors.accent.withValues(alpha: 0.45)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 5),
                Text(
                  lesson.title,
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 5),
                Text(
                  lesson.body,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
