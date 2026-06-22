// =========================================================
//  tv_focusable.dart — Composant FOCUSABLE réutilisable (§4)
// =========================================================
//  Le cœur d'une app TV : 90 % des portages échouent ici. Ici on
//  COMBINE plusieurs signaux de focus (jamais un simple liseré) :
//    1. SCALE (transform GPU, 120-200 ms ease-out)
//    2. COULEUR de surface tonale (+1..+5) : fond ET contenu changent
//    3. HALO / élévation (ombre)
//    4. CONTOUR + inset
//  + état PRESSED tant que OK est tenu.
//
//  PERF (§10) : on n'anime QUE `transform` (scale) et la peinture
//  (couleur/ombre/bordure) — JAMAIS width/height/top/left (reflow).
//
//  Le D-pad « OK » (select / enter / gameButtonA / space) déclenche
//  `onSelect`. `Back` est géré par le Navigator au niveau de l'écran.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_dimens.dart';
import 'tv_tokens.dart';

/// Intensité du grossissement au focus selon la taille de l'élément.
enum TvFocusScale { small, medium, large }

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.scale = TvFocusScale.medium,
    this.borderRadius,
    this.focusColor,
    this.baseColor = Colors.transparent,
    this.enabled = true,
    this.selected = false,
    this.showOutline = true,
    this.showGlow = true,
  });

  /// Contenu (carte, rangée, bouton…). Reçoit l'état de focus via [child]
  /// statique ; pour adapter la couleur du contenu, voir [TvFocusBuilder].
  final Widget child;
  final VoidCallback? onSelect;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final TvFocusScale scale;
  final BorderRadius? borderRadius;

  /// Surface au focus (défaut : surface tonale +). Le contenu doit, lui,
  /// passer en sombre quand le fond s'éclaircit (cf. TiviMate).
  final Color? focusColor;
  final Color baseColor;

  /// `false` = non focusable, contraste réduit (§4 disabled).
  final bool enabled;

  /// `true` = élément actuellement sélectionné (onglet actif, etc.).
  final bool selected;
  final bool showOutline;
  final bool showGlow;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  bool _ownsNode = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ownsNode = widget.focusNode == null;
  }

  @override
  void dispose() {
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  double get _scaleValue {
    switch (widget.scale) {
      case TvFocusScale.small:
        return TvDimens.focusScaleSmall;
      case TvFocusScale.medium:
        return TvDimens.focusScaleMedium;
      case TvFocusScale.large:
        return TvDimens.focusScaleLarge;
    }
  }

  bool _isSelectKey(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA ||
      k == LogicalKeyboardKey.space;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (!_isSelectKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      if (!_pressed) setState(() => _pressed = true);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      if (_pressed) setState(() => _pressed = false);
      widget.onSelect?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        widget.borderRadius ?? BorderRadius.circular(TvDimens.cardRadius);
    final Color focusBg = widget.focusColor ?? TvTokens.sel;
    final bool active = _focused && widget.enabled;

    // Échelle : un poil moins quand on enfonce OK (effet "pressé").
    final double targetScale =
        active ? (_pressed ? _scaleValue * 0.97 : _scaleValue) : 1.0;

    // TACTILE (TV/tablette à écran tactile) : on rend l'élément cliquable au
    // doigt EN PLUS du D-pad. Comme TOUTE l'UI TV passe par TvFocusable, ce
    // seul GestureDetector rend l'app entière navigable au toucher. Le doigt
    // prend d'abord le focus (le halo suit le doigt), puis relâche = onSelect.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled
          ? (_) {
              _node.requestFocus();
              if (!_pressed) setState(() => _pressed = true);
            }
          : null,
      onTapUp: widget.enabled
          ? (_) {
              if (_pressed) setState(() => _pressed = false);
            }
          : null,
      onTapCancel: widget.enabled
          ? () {
              if (_pressed) setState(() => _pressed = false);
            }
          : null,
      onTap: widget.enabled ? widget.onSelect : null,
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        canRequestFocus: widget.enabled,
        onKeyEvent: _onKey,
        onFocusChange: (bool f) {
          setState(() {
            _focused = f;
            if (!f) _pressed = false;
          });
          widget.onFocusChange?.call(f);
        },
        child: AnimatedScale(
          // Signal 1 : SCALE (transform GPU uniquement).
          scale: targetScale,
          duration: TvDimens.focusAnim,
          curve: TvDimens.focusCurve,
          child: AnimatedOpacity(
            opacity: widget.enabled ? 1.0 : 0.45, // §4 disabled
            duration: TvDimens.focusAnim,
            child: AnimatedContainer(
              duration: TvDimens.focusAnim,
              curve: TvDimens.focusCurve,
              decoration: BoxDecoration(
                // Signal 2 : COULEUR de surface (tonale, Maison Noir).
                color: active
                    ? focusBg
                    : (widget.selected ? TvTokens.sel : widget.baseColor),
                borderRadius: radius,
                // Signal 4 : CONTOUR OR au focus (visible partout, §5 spec).
                border: (widget.showOutline && (active || widget.selected))
                    ? Border.all(
                        color: active ? TvTokens.gold : TvTokens.line,
                        width: TvDimens.focusOutline,
                      )
                    : null,
                // Signal 3 : ÉLÉVATION (ombre portée) + lueur champagne. C'est
                // l'ombre profonde — pas la bordure — qui « soulève » l'élément
                // façon Apple TV+ ; la lueur or signe la marque.
                boxShadow: (widget.showGlow && active)
                    ? <BoxShadow>[
                        BoxShadow(
                          color: const Color(0x99000000), // noir 60 %
                          blurRadius: TvDimens.focusElevBlur,
                          offset: const Offset(0, TvDimens.focusElevDy),
                        ),
                        BoxShadow(
                          color: TvTokens.gold.withValues(alpha: 0.30),
                          blurRadius: TvDimens.focusGlowBlur,
                          spreadRadius: TvDimens.focusGlowSpread,
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Variante quand le CONTENU doit réagir au focus (texte sombre sur fond
/// clair, etc.). Donne un `builder(context, focused)`.
class TvFocusBuilder extends StatefulWidget {
  const TvFocusBuilder({
    super.key,
    required this.builder,
    this.onSelect,
    this.focusNode,
    this.autofocus = false,
    this.scale = TvFocusScale.medium,
    this.enabled = true,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final FocusNode? focusNode;
  final bool autofocus;
  final TvFocusScale scale;
  final bool enabled;

  @override
  State<TvFocusBuilder> createState() => _TvFocusBuilderState();
}

class _TvFocusBuilderState extends State<TvFocusBuilder> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: widget.onSelect,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      scale: widget.scale,
      enabled: widget.enabled,
      showOutline: false,
      onFocusChange: (bool f) => setState(() => _focused = f),
      child: widget.builder(context, _focused && widget.enabled),
    );
  }
}
