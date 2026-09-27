// =========================================================
//  zuno_ring_carousel.dart — LE composant principal : carrousel 3D en anneau
// =========================================================
//  Un seul widget public. Il reçoit la liste d'affiches, crée son contrôleur
//  (ZunoCarouselController ≈ useCarousel) et ses sons (CarouselSound ≈
//  useSound), et dessine l'anneau.
//
//  ÉTAPES À VENIR (cahier des charges) :
//    étape 2 → cartes posées sur l'arc 3D (perspective + rotateY +
//              translateZ), carte centrale nette, voisines inclinées,
//              réduites, estompées ;
//    étape 3 → flèches, molette, glisser + snap ;
//    étape 4 → zoom + halo de la carte sélectionnée, respiration au repos ;
//    étape 5 → sons ;
//    étape 6 → données de démonstration et rendu final.
// =========================================================
import 'package:flutter/material.dart';

import '../domain/carousel_config.dart';
import '../domain/carousel_item.dart';

class ZunoRingCarousel extends StatefulWidget {
  const ZunoRingCarousel({
    super.key,
    required this.items,
    this.config = const CarouselConfig(),
    this.initialIndex = 0,
    this.onSelected,
    this.onFocusChanged,
  });

  final List<CarouselItem> items;
  final CarouselConfig config;
  final int initialIndex;

  /// OK / Entrée / tap sur la carte centrale.
  final ValueChanged<CarouselItem>? onSelected;

  /// La carte centrale change (pour afficher titre, résumé… à côté).
  final ValueChanged<CarouselItem>? onFocusChanged;

  @override
  State<ZunoRingCarousel> createState() => _ZunoRingCarouselState();
}

class _ZunoRingCarouselState extends State<ZunoRingCarousel> {
  @override
  Widget build(BuildContext context) {
    // Étape 2 : rendu de l'anneau.
    return const SizedBox.shrink();
  }
}
