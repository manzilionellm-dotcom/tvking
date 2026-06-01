// =========================================================
//  search_skeleton.dart — Placeholders shimmer pour la recherche
// =========================================================
//  Affichés pendant la fenêtre de debounce + le filtre (~300-500
//  ms typique sur 27k chaînes). Donne l'impression que "ça
//  réfléchit" au lieu de geler ou de pop d'un coup.
//
//  Style premium dark : surfaces glass + animation de gradient
//  shimmer ember sobre. Respecte reduced-motion.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class SearchSkeleton extends StatefulWidget {
  const SearchSkeleton({super.key, this.cards = 6});

  /// Nombre de cards placeholder à afficher (calé sur la grille
  /// 2-3 colonnes du résultat réel).
  final int cards;

  @override
  State<SearchSkeleton> createState() => _SearchSkeletonState();
}

class _SearchSkeletonState extends State<SearchSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints cons) {
        final double w = cons.maxWidth;
        final int cols = w >= 1000 ? 4 : w >= 700 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 16 / 11,
          ),
          itemCount: widget.cards,
          itemBuilder: (BuildContext context, int index) {
            return _SkeletonCard(
              controller: _ctrl,
              reduceMotion: reduceMotion,
              // Décalage par card pour que le shimmer ne soit pas
              // synchronisé en bloc (effet "vague" plus naturel).
              phaseOffset: index * 0.08,
            );
          },
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({
    required this.controller,
    required this.reduceMotion,
    required this.phaseOffset,
  });

  final Animation<double> controller;
  final bool reduceMotion;
  final double phaseOffset;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final double t = reduceMotion
            ? 0.5
            : ((controller.value + phaseOffset) % 1.0);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + t * 2, -0.5),
              end: Alignment(0.0 + t * 2, 0.5),
              colors: <Color>[
                AppColors.surface,
                AppColors.surfaceHigh,
                AppColors.surface,
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
            border: Border.all(color: AppColors.border),
          ),
        );
      },
    );
  }
}
