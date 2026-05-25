// =========================================================
//  home_screen.dart — Écran d'accueil de l'app "TV King"
// =========================================================
//  C'est le premier écran que voit l'utilisateur.
//  Composition :
//    - Fond avec gradient + halos lumineux flous
//    - En-tête "TV KING" doré + sous-titre
//    - Section "En direct" avec une grille responsive de
//      ChannelCard (2 cols mobile, 3 cols tablette, 5 cols TV)
//
//  Responsive : on utilise LayoutBuilder pour adapter le nombre
//  de colonnes au format de l'écran. La même app, le même écran,
//  s'adapte du téléphone vertical à la TV 4K.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/fake_channels.dart';
import 'widgets/channel_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // extendBodyBehindAppBar = la AppBar flotte au-dessus du contenu,
      // ce qui permet de voir le dégradé jusqu'en haut.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'TV KING',
          style: AppTextStyles.headlineLarge.copyWith(
            color: AppColors.gold,
            letterSpacing: 4,
            fontSize: 22,
          ),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              // TODO(phase-1.4) : ouvrir l'écran de recherche.
            },
            icon: const Icon(Icons.search, color: Colors.white),
          ),
          IconButton(
            onPressed: () {
              // TODO(phase-1.4) : ouvrir l'écran des réglages.
            },
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // LayoutBuilder au sommet : on calcule le nombre de colonnes
      // de la grille en fonction de la largeur réelle de l'écran,
      // une fois pour toutes. On évite ainsi `SliverLayoutBuilder`
      // qui demande le type `SliverConstraints` (parfois non visible
      // suivant les versions de Flutter et les imports).
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double w = constraints.maxWidth;
          // Nombre de colonnes selon la largeur disponible.
          final int cols = w >= 1400
              ? 5
              : w >= 1000
                  ? 4
                  : w >= 700
                      ? 3
                      : 2;

          return Stack(
            children: <Widget>[
              // -------- Couche 1 : dégradé de fond principal --------------
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.backgroundGradient,
                ),
                child: SizedBox.expand(),
              ),

              // -------- Couche 2 : halos lumineux flous (ambiance) --------
              // Deux cercles flous très transparents qui donnent vie au fond.
              Positioned(
                top: -120,
                left: -80,
                child: _GlowOrb(
                  color: AppColors.accentPink.withValues(alpha: 0.25),
                  size: 320,
                ),
              ),
              Positioned(
                bottom: -160,
                right: -100,
                child: _GlowOrb(
                  color: AppColors.accentCyan.withValues(alpha: 0.18),
                  size: 380,
                ),
              ),

              // -------- Couche 3 : le contenu défilable -------------------
              SafeArea(
                child: CustomScrollView(
                  slivers: <Widget>[
                    // Petit espace sous l'AppBar
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),

                    // Titre "Bienvenue"
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Bienvenue',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Que voulez-vous regarder ?',
                          style: AppTextStyles.displayLarge.copyWith(fontSize: 34),
                        ),
                      ),
                    ),

                    // Titre de section
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              'En direct',
                              style: AppTextStyles.headlineLarge,
                            ),
                            Text(
                              '${kFakeChannels.length} chaînes',
                              style: AppTextStyles.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ---- Grille responsive de chaînes ----
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 16 / 11, // format paysage doux
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext context, int index) {
                            return ChannelCard(
                              channel: kFakeChannels[index],
                              onTap: () {
                                // Phase 1 — étape 3 : on branchera ici le
                                // lecteur vidéo. Pour l'instant on affiche
                                // juste un SnackBar de confirmation.
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: AppColors.surfaceHigh,
                                    content: Text(
                                      'Lecture de "${kFakeChannels[index].name}" — à brancher',
                                      style: AppTextStyles.bodyLarge,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          childCount: kFakeChannels.length,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Petit cercle flou décoratif pour l'effet "halo VIP".
/// Privé (`_GlowOrb`) car uniquement utilisé dans ce fichier.
class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
