// =========================================================
//  zuno_ring_carousel.dart — LE composant principal : carrousel 3D en anneau
// =========================================================
//  Un seul widget public, deux usages :
//    • ZunoRingCarousel(items: …)          → affiches films / séries ;
//    • ZunoRingCarousel.builder(…)          → n'importe quelles cartes
//      (ex. les Réglages de Zuno : une carte par rubrique).
//
//  GÉOMÉTRIE — même principe que le CSS du cahier des charges :
//
//      perspective(P) · translateZ(R) · rotateY(θ) · translateZ(−R)
//
//  Les cartes sont posées sur un cercle de rayon R dont le centre est
//  DERRIÈRE l'écran. La carte d'écart 0 est face caméra ; la carte d'écart d
//  tourne de θ = −d × angle : elle glisse sur le côté, recule et s'incline
//  (la perspective la rend plus petite). Les voisines reçoivent un VOILE
//  couleur du fond (même rendu qu'une opacité, sans passe GPU en plus).
//
//  NAVIGATION (étape 3)
//    • télécommande / clavier : ◀ ▶ (maintenu = défilement continu),
//      OK / Entrée = sélection ; HAUT / BAS ne sont PAS consommés → le focus
//      sort normalement de l'anneau ;
//    • molette (PC) : cumul du défilement, une carte par cran ;
//    • tactile : glisser (suit le doigt), lancer rapide = plusieurs cartes ;
//      tap sur une voisine = elle vient au centre, tap au centre = OK ;
//    • SNAP magnétique : chaque mouvement se termine exactement sur une
//      carte (easeOutCubic, config.snapDuration).
//
//  ZOOM INTELLIGENT + RESPIRATION (étape 4)
//    • carte centrale : zoom 1,06 + halo or, UNIQUEMENT quand l'anneau a le
//      focus (sinon l'œil croirait qu'elle est sélectionnée) ; le zoom
//      s'estompe pendant qu'elle quitte le centre (aucun à-coup) ;
//    • au repos (config.idleDelay sans action) : l'anneau « respire »
//      (balancement ±1,4°, carte centrale ±1,2 %), en fondu d'entrée ; la
//      moindre action l'arrête net.
//
//  PERFORMANCE (≈ `will-change: transform`) : chaque carte est isolée dans
//  un RepaintBoundary → pendant les animations seule la MATRICE change ;
//  seules les cartes visibles sont construites.
// =========================================================
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tv/core/tv_dimens.dart';
import '../../tv/core/tv_tokens.dart';
import '../domain/carousel_config.dart';
import '../domain/carousel_item.dart';
import 'carousel_controller.dart';
import 'carousel_poster_card.dart';
import 'carousel_sound.dart';

/// Construit la carte n° [index]. [selected] = carte au centre.
typedef RingCardBuilder = Widget Function(
    BuildContext context, int index, bool selected);

class ZunoRingCarousel extends StatefulWidget {
  /// Anneau d'AFFICHES (films / séries).
  ZunoRingCarousel({
    super.key,
    required List<CarouselItem> items,
    this.config = const CarouselConfig(),
    this.initialIndex = 0,
    this.autofocus = false,
    this.focusNode,
    ValueChanged<CarouselItem>? onSelected,
    ValueChanged<CarouselItem>? onFocusChanged,
  })  : itemCount = items.length,
        cardBuilder = ((BuildContext c, int i, bool sel) => CarouselPosterCard(
              item: items[i],
              width: config.cardWidth,
              height: config.cardHeight,
              elevated: sel,
            )),
        semanticLabel = ((int i) => items[i].title),
        onSelectedIndex = onSelected == null
            ? null
            : ((int i) {
                onSelected(items[i]);
              }),
        onFocusIndex = onFocusChanged == null
            ? null
            : ((int i) {
                onFocusChanged(items[i]);
              }),
        cardKey = ((int i) => items[i].id);

  /// Anneau de cartes LIBRES (ex. Réglages).
  const ZunoRingCarousel.builder({
    super.key,
    required this.itemCount,
    required this.cardBuilder,
    required this.semanticLabel,
    this.config = const CarouselConfig(),
    this.initialIndex = 0,
    this.autofocus = false,
    this.focusNode,
    this.onSelectedIndex,
    this.onFocusIndex,
    this.cardKey,
  });

  final int itemCount;
  final RingCardBuilder cardBuilder;
  final String Function(int index) semanticLabel;
  final CarouselConfig config;
  final int initialIndex;
  final bool autofocus;
  final FocusNode? focusNode;

  /// OK / Entrée / tap sur la carte centrale.
  final ValueChanged<int>? onSelectedIndex;

  /// La carte centrale change (pour afficher titre, description… à côté).
  final ValueChanged<int>? onFocusIndex;

  /// Clé stable d'une carte (garde son état quand l'ordre de peinture change).
  final String Function(int index)? cardKey;

  @override
  State<ZunoRingCarousel> createState() => _ZunoRingCarouselState();
}

class _ZunoRingCarouselState extends State<ZunoRingCarousel>
    with TickerProviderStateMixin {
  late ZunoCarouselController _ctrl;
  late CarouselSound _sound;
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  // --- Snap : anime la position continue de [_from] à [_to] ---
  late final AnimationController _snap;
  double _from = 0, _to = 0;

  // --- Focus : 0 → 1 quand l'anneau prend le focus (zoom + halo) ---
  late final AnimationController _focusT;

  // --- Respiration au repos ---
  late final AnimationController _idle; // phase 0..1, en boucle
  late final AnimationController _idleIn; // intensité 0..1 (fondu d'entrée)
  Timer? _idleTimer; // compte à rebours avant respiration (annulable)

  // --- Molette / glisser ---
  double _wheelAcc = 0;
  bool _dragging = false;
  double _dragStart = 0;

  CarouselConfig get _cfg => widget.config;

  /// Distance (px) parcourue par le doigt pour avancer d'une carte :
  /// l'écart horizontal réel entre deux cartes voisines sur l'arc.
  double get _cardSpacing =>
      _cfg.ringRadius * math.sin(_cfg.cardAngleDeg * math.pi / 180);

  @override
  void initState() {
    super.initState();
    _ctrl = _newController();
    _sound = CarouselSound(_cfg);
    _snap = AnimationController(vsync: this, duration: _cfg.snapDuration)
      ..addListener(_onSnapTick);
    _focusT = AnimationController(vsync: this, duration: TvDimens.focusAnim);
    _idle = AnimationController(vsync: this, duration: _cfg.idlePeriod);
    _idleIn = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _focus.addListener(_onFocusChange);
    _scheduleIdle();
  }

  ZunoCarouselController _newController() => ZunoCarouselController(
        count: math.max(1, widget.itemCount),
        initialIndex: widget.initialIndex,
      );

  @override
  void didUpdateWidget(covariant ZunoRingCarousel old) {
    super.didUpdateWidget(old);
    if (old.itemCount != widget.itemCount) {
      _snap.stop();
      _ctrl.dispose();
      _ctrl = _newController();
    }
    if (!identical(old.config, widget.config)) {
      _sound.dispose();
      _sound = CarouselSound(widget.config);
      _snap.duration = widget.config.snapDuration;
      _idle.duration = widget.config.idlePeriod;
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocusChange);
      _focus.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _focus.removeListener(_onFocusChange);
    _ownFocus?.dispose();
    _snap.dispose();
    _focusT.dispose();
    _idle.dispose();
    _idleIn.dispose();
    _ctrl.dispose();
    _sound.dispose();
    super.dispose();
  }

  // =========================================================
  //  Mouvement
  // =========================================================

  void _onSnapTick() {
    final double t = Curves.easeOutCubic.transform(_snap.value);
    _setPosition(_from + (_to - _from) * t);
  }

  void _setPosition(double p) {
    if (_ctrl.setPosition(p)) {
      _sound.tick();
      widget.onFocusIndex?.call(_ctrl.index);
    }
  }

  /// Avance de [delta] cartes avec aimantation. Un appui pendant une
  /// animation part de la cible EN COURS : 3 appuis rapides = 3 cartes.
  void _go(int delta) {
    if (widget.itemCount < 2 || delta == 0) return;
    _touch();
    final double base =
        _snap.isAnimating ? _to : _ctrl.position.roundToDouble();
    _animateTo(base + delta);
  }

  void _animateTo(double target) {
    _from = _ctrl.position;
    _to = target;
    _snap
      ..stop()
      ..value = 0
      ..forward();
  }

  void _activate() {
    if (widget.itemCount == 0) return;
    _touch();
    _sound.select();
    widget.onSelectedIndex?.call(_ctrl.index);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent &&
        (k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.gameButtonA)) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored; // HAUT / BAS / Retour : comportement normal
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final double d = e.scrollDelta.dy.abs() >= e.scrollDelta.dx.abs()
        ? e.scrollDelta.dy
        : e.scrollDelta.dx;
    _wheelAcc += d;
    if (_wheelAcc.abs() >= _cfg.wheelStepThreshold) {
      _go(_wheelAcc.sign.toInt());
      _wheelAcc = 0;
    }
  }

  void _onDragStart(DragStartDetails _) {
    _touch();
    _snap.stop();
    _dragging = true;
    _dragStart = _ctrl.position.roundToDouble();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Doigt vers la gauche = les cartes suivantes arrivent (comme un rouleau).
    _setPosition(_ctrl.position - d.delta.dx / _cardSpacing);
    _touch();
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    final double v = d.primaryVelocity ?? 0; // px/s, > 0 = doigt vers la droite
    final double moved = _ctrl.position - _dragStart; // en cartes
    int steps = moved.round();
    // Glisser lent : au-delà d'une fraction de carte, on change de carte.
    if (steps == 0 && moved.abs() >= _cfg.swipeCardWidthRatio) {
      steps = moved.sign.toInt();
    }
    // Lancer rapide : 1 à 3 cartes selon la vitesse, dans le sens du geste.
    if (v.abs() >= _cfg.swipeFlingVelocity) {
      final int dir = v < 0 ? 1 : -1;
      final int extra = (v.abs() / _cfg.swipeFlingVelocity).floor().clamp(1, 3);
      steps = dir * math.max(steps.abs(), extra);
    }
    _animateTo(_dragStart + steps);
  }

  // =========================================================
  //  Focus + respiration
  // =========================================================

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _focusT.forward();
    } else {
      _focusT.reverse();
    }
  }

  /// Toute action : on arrête la respiration et on relance le compte à rebours.
  void _touch() {
    if (_idle.isAnimating || _idleIn.value > 0) {
      _idle.stop();
      _idleIn.value = 0;
    }
    _scheduleIdle();
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_cfg.idleDelay, () {
      if (!mounted || _dragging) return;
      if (_snap.isAnimating) {
        _scheduleIdle();
        return;
      }
      _idle.repeat();
      _idleIn.forward(from: 0);
    });
  }

  // =========================================================
  //  Rendu
  // =========================================================

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    final CarouselConfig cfg = _cfg;
    // Material transparent : style de texte de base (sinon soulignement
    // jaune de debug hors Scaffold). Aucun effet visuel.
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        focusNode: _focus,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: SizedBox(
              // TOUTE la largeur disponible : l'anneau déborde largement la
              // carte centrale (sans ça, le ClipRect ne garderait qu'elle).
              width: double.infinity,
              // Carte zoomée + ombre portée + sol.
              height: cfg.cardHeight * cfg.selectedScale + 64,
              child: ClipRect(
                clipBehavior: Clip.hardEdge,
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                      <Listenable>[_ctrl, _focusT, _idle, _idleIn]),
                  builder: (BuildContext context, _) => _buildRing(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRing(BuildContext context) {
    final CarouselConfig cfg = _cfg;
    final double angleStep = cfg.cardAngleDeg * math.pi / 180;
    final double reach = cfg.visibleSide + 1.0;

    // Respiration : sinusoïde douce, en fondu d'entrée.
    final double breath = math.sin(_idle.value * 2 * math.pi) *
        Curves.easeInOut.transform(_idleIn.value);
    final double idleTheta = breath * cfg.idleAmplitudeDeg * math.pi / 180;

    final List<_Placed> placed = <_Placed>[];
    for (int i = 0; i < widget.itemCount; i++) {
      final double d = _ctrl.offsetOf(i);
      if (d.abs() < reach) placed.add(_Placed(i, d));
    }
    // Du plus loin au plus proche : le centre est peint en dernier.
    placed.sort((_Placed a, _Placed b) => b.d.abs().compareTo(a.d.abs()));

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        // « Sol » : ombre elliptique qui ancre l'anneau.
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
          _buildCard(
              context, p.index, p.d, angleStep, reach, idleTheta, breath),
      ],
    );
  }

  Widget _buildCard(BuildContext context, int index, double d, double angleStep,
      double reach, double idleTheta, double breath) {
    final CarouselConfig cfg = _cfg;
    final double t = d.abs();
    final double theta = -d * angleStep + idleTheta;

    // Proximité du centre : 1 au centre exact, 0 à une carte d'écart.
    final double centerness = (1 - t).clamp(0.0, 1.0);
    final double focusT = Curves.easeOut.transform(_focusT.value);
    double scale = math.max(0.5, 1 - cfg.sideScaleStep * t);
    // Zoom intelligent : seulement la carte au centre, seulement avec focus.
    scale *= 1 + (cfg.selectedScale - 1) * focusT * centerness;
    scale *= 1 + cfg.idleScaleAmplitude * breath * centerness;

    final double visible =
        math.max(cfg.sideMinOpacity, 1 - cfg.sideOpacityStep * t);
    final double edge = (reach - t).clamp(0.0, 1.0);
    final double veil = (1 - visible * edge).clamp(0.0, 1.0);
    final double glow = cfg.glowOpacity * focusT * centerness;

    final Matrix4 m = Matrix4.identity()
      ..setEntry(3, 2, 1 / cfg.perspectivePx)
      ..translateByDouble(0, 0, cfg.ringRadius, 1)
      ..rotateY(theta)
      ..translateByDouble(0, 0, -cfg.ringRadius, 1)
      ..scaleByDouble(scale, scale, 1, 1);

    final bool center = t < 0.5;
    const BorderRadius radius =
        BorderRadius.all(Radius.circular(TvDimens.cardRadius));
    return Transform(
      key: ValueKey<String>(widget.cardKey?.call(index) ?? 'c$index'),
      alignment: Alignment.center,
      transform: m,
      child: GestureDetector(
        onTap: () {
          final int steps = d.round();
          if (steps == 0) {
            _activate();
          } else {
            _go(steps);
          }
        },
        child: Semantics(
          label: widget.semanticLabel(index),
          selected: center,
          button: true,
          child: SizedBox(
            width: cfg.cardWidth,
            height: cfg.cardHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                // Halo or (focus) : derrière la carte, jamais dans son cache.
                if (glow > 0.01)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color:
                                  TvTokens.accentBright.withValues(alpha: glow),
                              blurRadius: cfg.glowBlur,
                              spreadRadius: TvDimens.focusGlowSpread,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: RepaintBoundary(
                    child: widget.cardBuilder(context, index, center),
                  ),
                ),
                // Liseré or du focus (2 px), en fondu comme le halo.
                if (glow > 0.01)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: TvTokens.accentBright
                                .withValues(alpha: focusT * centerness),
                            width: TvDimens.focusOutline,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (veil > 0.001)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: TvTokens.bg.withValues(alpha: veil),
                          borderRadius: radius,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
