// =========================================================
//  zuno_ring_carousel.dart — LE composant principal : carrousel 3D en anneau
// =========================================================
//  Un seul widget public. Il reçoit la liste d'affiches, crée son contrôleur
//  (ZunoCarouselController ≈ useCarousel) et ses sons (CarouselSound ≈
//  useSound), et dessine l'anneau.
//
//  GÉOMÉTRIE (étape 2) — même principe que le CSS du cahier des charges :
//
//      perspective(P) · translateZ(R) · rotateY(θ) · translateZ(−R)
//
//  Les cartes sont posées sur un cercle de rayon R dont le centre est
//  DERRIÈRE l'écran. La carte d'écart 0 est face caméra (θ = 0, z = 0) ;
//  la carte d'écart d tourne de θ = −d × angle autour de ce centre : elle
//  glisse sur le côté, recule (z = R·(1 − cos θ)) et s'incline — la
//  perspective la rend naturellement plus petite. On ajoute :
//    • une réduction d'échelle par carte d'écart (sideScaleStep) ;
//    • un voile NOIR (couleur du fond) au lieu d'une vraie opacité : même
//      rendu à l'œil (la carte se fond dans la scène), mais sans
//      `saveLayer` → aucune passe GPU supplémentaire, 60 i/s tenus sur box.
//
//  PERFORMANCE (équivalent de `will-change: transform`) :
//    • chaque affiche est isolée dans un RepaintBoundary : quand l'anneau
//      tourne, seule la MATRICE change, l'image n'est pas redessinée ;
//    • seules les cartes visibles sont construites (visibleSide de chaque
//      côté + 1 carte d'entrée/sortie qui apparaît en fondu).
//
//  ÉTAPES À VENIR (cahier des charges) :
//    étape 3 → flèches, molette, glisser + snap ;
//    étape 4 → zoom + halo de la carte sélectionnée, respiration au repos ;
//    étape 5 → sons ;
//    étape 6 → données de démonstration et rendu final.
// =========================================================
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_tokens.dart';
import '../domain/carousel_config.dart';
import '../domain/carousel_item.dart';
import 'carousel_controller.dart';
import 'carousel_poster_card.dart';
import 'carousel_sound.dart';

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
  late ZunoCarouselController _controller;
  late CarouselSound _sound;

  @override
  void initState() {
    super.initState();
    _controller = _newController();
    _sound = CarouselSound(widget.config);
  }

  ZunoCarouselController _newController() => ZunoCarouselController(
        count: math.max(1, widget.items.length),
        initialIndex: widget.initialIndex,
      );

  @override
  void didUpdateWidget(covariant ZunoRingCarousel old) {
    super.didUpdateWidget(old);
    // Nouvelle liste de taille différente → nouvel anneau (l'ancien index
    // n'a plus de sens). Même taille → on garde la position.
    if (old.items.length != widget.items.length) {
      _controller.dispose();
      _controller = _newController();
    }
    if (!identical(old.config, widget.config)) {
      _sound.dispose();
      _sound = CarouselSound(widget.config);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _sound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final CarouselConfig cfg = widget.config;
    // Material transparent : fournit le style de texte de base. Sans lui,
    // Flutter souligne le texte en jaune (avertissement de debug) si le
    // carrousel est posé hors d'un Scaffold. Aucun effet visuel sinon.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        // Hauteur réservée : carte + marge pour l'ombre portée et le sol.
        height: cfg.cardHeight * cfg.selectedScale + 64,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, _) =>
              _buildRing(cfg, _controller, widget.items),
        ),
      ),
    );
  }

  Widget _buildRing(
    CarouselConfig cfg,
    ZunoCarouselController ctrl,
    List<CarouselItem> items,
  ) {
    final double angleStep = cfg.cardAngleDeg * math.pi / 180;
    // Au-delà de visibleSide, une carte de plus « entre » en fondu : pas
    // d'apparition sèche quand l'anneau tourne.
    final double reach = cfg.visibleSide + 1.0;

    final List<_Placed> placed = <_Placed>[];
    for (int i = 0; i < items.length; i++) {
      final double d = ctrl.offsetOf(i);
      if (d.abs() < reach) placed.add(_Placed(i, d));
    }
    // Ordre de peinture : du plus loin au plus proche (le centre en dernier,
    // donc au premier plan) — l'équivalent du z-index.
    placed.sort((_Placed a, _Placed b) => b.d.abs().compareTo(a.d.abs()));

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        // « Sol » : ombre elliptique sous l'anneau. Ancre visuellement les
        // cartes (elles ne flottent pas dans le vide) — très sombre, calme.
        Positioned(
          bottom: 8,
          child: IgnorePointer(
            child: SizedBox(
              width: cfg.cardWidth * 4,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.5,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        for (final _Placed p in placed)
          _buildCard(cfg, items[p.index], p.d, angleStep, reach),
      ],
    );
  }

  Widget _buildCard(
    CarouselConfig cfg,
    CarouselItem item,
    double d,
    double angleStep,
    double reach,
  ) {
    final double t = d.abs();
    final double theta = -d * angleStep;
    final double scale = math.max(0.5, 1 - cfg.sideScaleStep * t);

    // Voile : 0 au centre, puis s'épaissit jusqu'au plancher d'opacité ;
    // la carte d'entrée/sortie (entre visibleSide et reach) finit
    // totalement fondue dans le fond.
    final double visible =
        math.max(cfg.sideMinOpacity, 1 - cfg.sideOpacityStep * t);
    final double edge =
        (reach - t).clamp(0.0, 1.0); // 1 → 0 sur la dernière carte
    final double veil = (1 - visible * edge).clamp(0.0, 1.0);

    final Matrix4 m = Matrix4.identity()
      ..setEntry(3, 2, 1 / cfg.perspectivePx)
      ..translateByDouble(0, 0, cfg.ringRadius, 1)
      ..rotateY(theta)
      ..translateByDouble(0, 0, -cfg.ringRadius, 1)
      ..scaleByDouble(scale, scale, 1, 1);

    final bool center = t < 0.5;
    return Transform(
      key: ValueKey<String>(item.id),
      alignment: Alignment.center,
      transform: m,
      child: Semantics(
        label: item.title,
        selected: center,
        child: Stack(
          children: <Widget>[
            RepaintBoundary(
              child: CarouselPosterCard(
                item: item,
                width: cfg.cardWidth,
                height: cfg.cardHeight,
                elevated: center,
              ),
            ),
            if (veil > 0.001)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: TvTokens.bg.withValues(alpha: veil),
                      borderRadius: const BorderRadius.all(
                          Radius.circular(TvDimens.cardRadius)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Position d'une carte sur l'anneau (index dans la liste + écart signé).
class _Placed {
  const _Placed(this.index, this.d);
  final int index;
  final double d;
}
