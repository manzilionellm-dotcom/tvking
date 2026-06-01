// =========================================================
//  floating_bottom_nav.dart — Barre de navigation flottante
// =========================================================
//  Refonte Phase 1.0b ("premium streaming platform") :
//
//  L'ancienne nav exposait des genres (Sport, Live TV, Cinema,
//  Series, Adulte) — c'est un panel revendeur, pas une nav de
//  plateforme premium. Les utilisateurs de Netflix ou Apple TV+
//  ne tapent jamais "Sport" en bas d'ecran pour explorer du sport.
//
//  Modele (demande user 2026-06-01) : la barre du bas donne un
//  acces direct aux CATEGORIES les plus demandees, en plus de
//  l'accueil :
//
//    Home         — accueil discovery (hero + rails + chips)
//    Football     — toutes les chaines sport (tous pays)
//    Information  — toutes les chaines info / actu
//    Enfant       — toutes les chaines jeunesse
//    Cinema       — tous les films
//
//  Favoris et Profil sont accessibles depuis la barre du haut
//  (icones coeur et profil). Glassmorphism conserve + pill de
//  selection.
// =========================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/tv_focusable.dart';

class FloatingBottomNav extends StatelessWidget {
  const FloatingBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final void Function(int index) onTap;

  static const List<_NavItem> _items = <_NavItem>[
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.sports_soccer_rounded, label: 'Football'),
    _NavItem(icon: Icons.newspaper_rounded, label: 'Information'),
    _NavItem(icon: Icons.child_care_rounded, label: 'Enfant'),
    _NavItem(icon: Icons.movie_creation_rounded, label: 'Cinéma'),
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

// =========================================================
//  _NavButton — Bouton individuel input-agnostic
// =========================================================
//  Refonte TV : wrappé dans `TvFocusable` pour que la
//  télécommande Android TV / Fire TV / clavier / souris-air
//  reçoive le MÊME focus ring ember que partout dans l'app.
//
//  Pourquoi pas juste `InkWell` ?
//    - `InkWell` répond au tap doigt et au clavier (focus
//      ring système gris, peu visible).
//    - `TvFocusable` ajoute par-dessus : bordure ember 2.4 px,
//      scale 1.06, scroll auto si dans un Scrollable, et
//      respect du réglage "Réduire les animations".
//    - On supprime le `Material > InkWell` interne pour éviter
//      la double zone tactile + double ripple (TvFocusable
//      fournit déjà son propre `Material > InkWell`).
//
//  Le `borderRadius: 18` du TvFocusable matche la pill interne
//  pour que le focus ring épouse exactement la forme dessinée.
//  `showGlow: false` parce que la barre est compacte — un halo
//  ember sur chaque onglet baverait sur les voisins.
// =========================================================
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
    final Color color = selected ? AppColors.accent : Colors.white;

    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      showGlow: false,
      semanticsLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 14 : 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 22),
            // Le label apparaît UNIQUEMENT sur l'onglet sélectionné
            // pour économiser la place et créer un effet "pill" Apple.
            // Au focus télécommande, le focus ring ember + l'icône
            // restent les signaux principaux — c'est suffisant.
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
    );
  }
}
