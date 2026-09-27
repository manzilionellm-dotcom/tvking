// =========================================================
//  carousel_config.dart — TOUS les réglages du carrousel 3D Zuno
// =========================================================
//  Un seul endroit pour « tweaker » le rendu (cf. docs/carousel-3d.md) :
//  angle entre les cartes, profondeur de l'anneau, vitesse du snap,
//  zoom de la carte sélectionnée, respiration au repos, sons.
//
//  Équivalences avec la version web décrite dans le cahier des charges :
//    rotateY(angle)      → Matrix4.rotateY(angleRad)
//    translateZ(depth)   → Matrix4.translate(0, 0, -depth)
//    perspective(px)     → Matrix4.setEntry(3, 2, 1 / px)
//  Les unités sont des pixels LOGIQUES du canevas TV (1280 de large, mis à
//  l'échelle sur l'écran réel) : le rendu est identique en 720p, 1080p, 4K.
// =========================================================
import 'package:flutter/foundation.dart';

@immutable
class CarouselConfig {
  const CarouselConfig({
    // ---- Géométrie de l'anneau ----
    this.cardAngleDeg = 24,
    this.ringRadius = 560,
    this.perspectivePx = 1100,
    this.cardWidth = 220,
    this.cardAspect = 2 / 3,
    this.visibleSide = 4,
    // ---- Estompage des voisines ----
    this.sideScaleStep = 0.09,
    this.sideOpacityStep = 0.2,
    this.sideMinOpacity = 0.15,
    // ---- Zoom intelligent ----
    this.selectedScale = 1.10,
    this.glowBlur = 36,
    this.glowOpacity = 0.55,
    // ---- Mouvement ----
    this.snapDuration = const Duration(milliseconds: 380),
    this.wheelStepThreshold = 60,
    this.swipeCardWidthRatio = 0.35,
    this.swipeFlingVelocity = 700,
    // ---- Respiration au repos (idle) ----
    this.idleDelay = const Duration(seconds: 4),
    this.idlePeriod = const Duration(seconds: 6),
    this.idleAmplitudeDeg = 1.4,
    this.idleScaleAmplitude = 0.012,
    // ---- Son ----
    this.soundEnabled = true,
    this.tickFrequencyHz = 1850,
    this.tickDuration = const Duration(milliseconds: 22),
    this.selectFrequenciesHz = const <double>[660, 990],
    this.selectDuration = const Duration(milliseconds: 140),
    this.volume = 0.18,
  });

  /// Angle (degrés) entre deux cartes voisines sur l'anneau.
  /// Plus grand = anneau plus « ouvert », moins de cartes visibles.
  final double cardAngleDeg;

  /// Rayon de l'anneau (px) = profondeur `translateZ`. Plus grand = cartes
  /// voisines plus éloignées et plus petites.
  final double ringRadius;

  /// Distance de la caméra (px). Petit = perspective forte, grand = plate.
  final double perspectivePx;

  /// Largeur de la carte centrale (px logiques) et ratio largeur/hauteur
  /// (2/3 = affiche de cinéma).
  final double cardWidth;
  final double cardAspect;

  /// Nombre de cartes dessinées de chaque côté de la carte centrale (les
  /// autres ne sont pas construites : économie GPU).
  final int visibleSide;

  /// Réduction d'échelle et d'opacité par carte d'écart avec le centre.
  final double sideScaleStep;
  final double sideOpacityStep;
  final double sideMinOpacity;

  /// Échelle de la carte SÉLECTIONNÉE (1.0 = taille normale) et halo or.
  final double selectedScale;
  final double glowBlur;
  final double glowOpacity;

  /// Durée de l'aimantation (snap) sur la carte centrale.
  final Duration snapDuration;

  /// Molette : cumul de défilement (px) qui fait avancer d'une carte.
  final double wheelStepThreshold;

  /// Glisser tactile : fraction de largeur de carte qui fait changer de
  /// carte, et vitesse (px/s) au-delà de laquelle un « lancer » saute.
  final double swipeCardWidthRatio;
  final double swipeFlingVelocity;

  /// Respiration au repos : délai d'inactivité, période, amplitude (en
  /// rotation de l'anneau et en échelle de la carte centrale).
  final Duration idleDelay;
  final Duration idlePeriod;
  final double idleAmplitudeDeg;
  final double idleScaleAmplitude;

  /// Sons synthétisés (aucun fichier) : tick au changement, accord à la
  /// sélection, volume global 0..1.
  final bool soundEnabled;
  final double tickFrequencyHz;
  final Duration tickDuration;
  final List<double> selectFrequenciesHz;
  final Duration selectDuration;
  final double volume;

  /// Hauteur de la carte centrale (px logiques).
  double get cardHeight => cardWidth / cardAspect;
}
