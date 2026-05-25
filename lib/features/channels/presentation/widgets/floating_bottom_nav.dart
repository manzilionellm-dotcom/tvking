// =========================================================
//  floating_bottom_nav.dart — Barre de navigation flottante
// =========================================================
//  Barre semi-transparente avec effet glassmorphism qui
//  flotte au-dessus du contenu en bas d'écran (style iOS 17
//  / Apple TV / dernières versions Netflix).
//
//  5 onglets pour l'instant :
//    - Accueil (sélectionné par défaut)
//    - TV Guide (Phase 2)
//    - Films (futur Xtream VOD)
//    - Recherche (Phase 1.4)
//    - Profil (Phase 5)
//
//  Phase 1 — uniquement visuel, les autres onglets afficheront
//  un message "Bientôt disponible" pour l'instant.
// =========================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class FloatingBottomNav extends StatelessWidget {
  const FloatingBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final void Function(int index) onTap;

  static const List<_NavItem> _items = <_NavItem>[
    _NavItem(icon: Icons.home_rounded, label: 'Accueil'),
    _NavItem(icon: Icons.live_tv_rounded, label: 'TV Guide'),
    _NavItem(icon: Icons.movie_creation_outlined, label: 'Films'),
    _NavItem(icon: Icons.search_rounded, label: 'Recherche'),
    _NavItem(icon: Icons.account_circle_outlined, label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List<Widget>.generate(_items.length, (int i) {
                  final _NavItem item = _items[i];
                  final bool selected = i == currentIndex;
                  return _NavButton(
                    icon: item.icon,
                    label: item.label,
                    selected: selected,
                    onTap: () => onTap(i),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? AppColors.accentPink : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 14 : 10,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentPink.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: color, size: 22),
              // Le label apparaît UNIQUEMENT sur l'onglet sélectionné
              // pour économiser la place et créer un effet "pill" Apple.
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          label,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
