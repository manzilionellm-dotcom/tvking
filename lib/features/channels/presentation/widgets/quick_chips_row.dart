// =========================================================
//  quick_chips_row.dart — Rangée de raccourcis rapides
// =========================================================
//  Petite barre horizontale sous le Hero avec 4 raccourcis :
//  Catégories / Favoris / Réglages / Recherche.
//
//  Style "chip" semi-transparent, glassmorphism léger.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class QuickChipsRow extends StatelessWidget {
  const QuickChipsRow({
    required this.onCategories,
    required this.onFavorites,
    required this.onSettings,
    required this.onSearch,
    super.key,
  });

  final VoidCallback onCategories;
  final VoidCallback onFavorites;
  final VoidCallback onSettings;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _Chip(
              icon: Icons.grid_view_rounded,
              label: 'Catégories',
              onTap: onCategories,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Chip(
              icon: Icons.favorite_outline,
              label: 'Favoris',
              onTap: onFavorites,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Chip(
              icon: Icons.search_rounded,
              label: 'Recherche',
              onTap: onSearch,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Chip(
              icon: Icons.tune_rounded,
              label: 'Réglages',
              onTap: onSettings,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                color: AppColors.accentCyan,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
