// =========================================================
//  carousel_item.dart — Une affiche du carrousel 3D
// =========================================================
//  Modèle PUR (aucun widget) : le carrousel peut afficher les données de
//  démonstration (étape 6) comme, plus tard, les vrais films / séries du
//  module Cinéma (CinemaTitle → CarouselItem).
// =========================================================
import 'package:flutter/foundation.dart';

/// Les 6 catégories de la démonstration.
enum CarouselCategory {
  action,
  scienceFiction,
  drame,
  animation,
  thriller,
  documentaire
}

@immutable
class CarouselItem {
  const CarouselItem({
    required this.id,
    required this.title,
    required this.category,
    this.posterUrl,
    this.year,
    this.rating,
    this.isSeries = false,
  });

  final String id;
  final String title;
  final CarouselCategory category;

  /// Affiche distante ; null = affiche générée (dégradé + titre), pour que
  /// la démonstration fonctionne sans réseau.
  final String? posterUrl;
  final int? year;
  final double? rating;
  final bool isSeries;
}
