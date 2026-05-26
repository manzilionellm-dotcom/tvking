// =========================================================
//  round_category_row.dart — Catégories rondes style Apple TV
// =========================================================
//  Row horizontale de "cercles thématiques" sous le hero du
//  HomeScreen. Permet à l'utilisateur de partir DIRECTEMENT
//  vers ce qui l'intéresse — Football, Jeunesse, Info... —
//  sans scanner toutes les rails de genres.
//
//  Inspiration : Apple TV+ profile chips, Netflix Kids mode,
//  YouTube TV "Live" header. Cercle ~68dp avec icône au centre
//  + label en-dessous. Scroll horizontal avec snap.
//
//  "Une grand-mère doit pouvoir l'utiliser" : icônes universelles
//  (ballon, marionnette, masque, journal, planète), labels en
//  français court, gros touch target (72×96 minimum).
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

@immutable
class RoundCategoryItem {
  const RoundCategoryItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class RoundCategoryRow extends StatelessWidget {
  const RoundCategoryRow({
    required this.items,
    super.key,
  });

  final List<RoundCategoryItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (BuildContext _, int __) =>
            const SizedBox(width: 14),
        itemBuilder: (BuildContext context, int i) {
          return _RoundChip(item: items[i]);
        },
      ),
    );
  }
}

class _RoundChip extends StatelessWidget {
  const _RoundChip({required this.item});

  final RoundCategoryItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Glow ember discret + fond surface — visible sans
                  // crier. Sur tap, AnimatedContainer s'illumine plus
                  // (géré par le Material/InkWell par-dessus).
                  color: AppColors.surfaceHigh,
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.32),
                    width: 1,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.10),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Icon(
                  item.icon,
                  color: AppColors.accent,
                  size: 30,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.label,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
