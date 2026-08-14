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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/display_settings.dart';
import 'tv_dimens.dart';
import 'tv_tokens.dart';

/// Intensité du grossissement au focus selon la taille de l'élément.
enum TvFocusScale { small, medium, large }

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onLongPress,
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
    this.onPressChange,
  });

  /// Contenu (carte, rangée, bouton…). Reçoit l'état de focus via [child]
  /// statique ; pour adapter la couleur du contenu, voir [TvFocusBuilder].
  final Widget child;
  final VoidCallback? onSelect;

  /// Appui LONG sur OK (D-pad maintenu ~450 ms) OU appui long au doigt. Sert,
  /// par ex., à mettre une chaîne en favori sans ouvrir le lecteur. Quand
  /// l'appui long se déclenche, l'appui court (onSelect) qui suivrait le
  /// relâchement est ANNULÉ (sinon on ouvrirait aussi le lecteur).
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocusChange;

  /// Notifié quand l'élément passe (true) / sort (false) de l'état APPUYÉ
  /// (OK enfoncé ou doigt posé). Permet aux surfaces de CHANGER DE COULEUR
  /// à l'appui (retour visuel immédiat, avant même l'action).
  final ValueChanged<bool>? onPressChange;
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

  // APPUI LONG (D-pad) : à l'enfoncement d'OK on arme un timer ; s'il se
  // déclenche AVANT le relâchement, c'est un appui long → on appelle
  // onLongPress et on marque _longFired pour ANNULER l'onSelect du relâchement.
  Timer? _longTimer;
  bool _longFired = false;
  static const Duration _kLongPress = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _ownsNode = widget.focusNode == null;
  }

  @override
  void dispose() {
    _longTimer?.cancel();
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  void _cancelLongTimer() {
    _longTimer?.cancel();
    _longTimer = null;
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
      if (!_pressed) {
        setState(() => _pressed = true);
        widget.onPressChange?.call(true);
      }
      // Arme l'appui long seulement si un handler est fourni.
      _longFired = false;
      _cancelLongTimer();
      if (widget.onLongPress != null && widget.enabled) {
        _longTimer = Timer(_kLongPress, () {
          _longFired = true;
          widget.onLongPress!.call();
        });
      }
      return KeyEventResult.handled;
    }
    // Les répétitions clavier (OK maintenu) n'ouvrent rien : le timer décide.
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _cancelLongTimer();
      if (_pressed) {
        setState(() => _pressed = false);
        widget.onPressChange?.call(false);
      }
      // Si l'appui long s'est déclenché, on N'OUVRE PAS (onSelect annulé).
      if (_longFired) {
        _longFired = false;
        return KeyEventResult.handled;
      }
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
              if (!_pressed) {
                setState(() => _pressed = true);
                widget.onPressChange?.call(true);
              }
            }
          : null,
      onTapUp: widget.enabled
          ? (_) {
              if (_pressed) {
                setState(() => _pressed = false);
                widget.onPressChange?.call(false);
              }
            }
          : null,
      onTapCancel: widget.enabled
          ? () {
              if (_pressed) {
                setState(() => _pressed = false);
                widget.onPressChange?.call(false);
              }
            }
          : null,
      onTap: widget.enabled ? widget.onSelect : null,
      // Appui long au DOIGT (écrans tactiles) : même effet que OK maintenu.
      onLongPress: (widget.enabled && widget.onLongPress != null)
          ? () {
              if (_pressed) {
                setState(() => _pressed = false);
                widget.onPressChange?.call(false);
              }
              widget.onLongPress!.call();
            }
          : null,
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        canRequestFocus: widget.enabled,
        onKeyEvent: _onKey,
        onFocusChange: (bool f) {
          // ANCRAGE SENSORIEL (spec « Pavlovian ») : clic système discret à
          // chaque PRISE de focus — le son natif Android (déjà mixé bas par
          // l'OS), zéro asset, zéro latence. Désactivable dans Affichage.
          if (f && DisplaySettings.instance.navSounds) {
            SystemSound.play(SystemSoundType.click);
          }
          setState(() {
            _focused = f;
            if (!f) _pressed = false;
          });
          if (!f) widget.onPressChange?.call(false);
          widget.onFocusChange?.call(f);
        },
        // RepaintBoundary : l'animation de focus (scale + ombre/halo blur
        // 34-40 px, ~9 frames) repeint la couche de la TUILE seulement. Les
        // items de ListView/GridView.builder en ont déjà un (framework) ;
        // celui-ci couvre les tuiles posées dans des Row/Column (5 grandes
        // tuiles + barre du haut du Modèle B, rangée d'icônes Rails…), où
        // chaque cran de D-pad repeignait la route ENTIÈRE — par-dessus une
        // SurfaceView hybrid composition sur l'accueil.
        child: RepaintBoundary(
          child: AnimatedScale(
            // Signal 1 : SCALE (transform GPU uniquement).
            scale: targetScale,
            duration: TvDimens.focusAnim,
            curve: TvDimens.focusCurve,
            child: _DisabledDim(
              enabled: widget.enabled,
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
                          const BoxShadow(
                            color: Color(0x99000000), // noir 60 %
                            blurRadius: TvDimens.focusElevBlur,
                            offset: Offset(0, TvDimens.focusElevDy),
                          ),
                          BoxShadow(
                            color: TvTokens.gold.withValues(alpha: 0.35),
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
      ),
    );
  }
}

/// Variante quand le CONTENU doit réagir au focus (texte sombre sur fond
/// clair, etc.). Donne un `builder(context, focused)`.
class TvFocusBuilder extends StatefulWidget {
  const TvFocusBuilder({
    super.key,
    this.builder,
    this.onSelect,
    this.onLongPress,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.scale = TvFocusScale.medium,
    this.enabled = true,
    this.pressedBuilder,
  }) : assert(builder != null || pressedBuilder != null,
            'builder ou pressedBuilder requis');

  final Widget Function(BuildContext context, bool focused)? builder;

  /// Variante RICHE : reçoit aussi l'état APPUYÉ (OK enfoncé / doigt posé).
  /// Si fournie, elle remplace [builder] — sert aux tuiles qui changent de
  /// couleur à l'appui (template Rails premium).
  final Widget Function(BuildContext context, bool focused, bool pressed)?
      pressedBuilder;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;

  /// Notifié aux TRANSITIONS de focus (gain/perte). À utiliser pour les
  /// effets de bord (débounce d'aperçu, pré-chargement…) au lieu d'un test
  /// `if (focused)` DANS le builder — qui re-déclencherait l'effet à chaque
  /// rebuild de la tuile, pas seulement à l'arrivée du focus.
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final TvFocusScale scale;
  final bool enabled;

  @override
  State<TvFocusBuilder> createState() => _TvFocusBuilderState();
}

class _TvFocusBuilderState extends State<TvFocusBuilder> {
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool f = _focused && widget.enabled;
    return TvFocusable(
      onSelect: widget.onSelect,
      onLongPress: widget.onLongPress,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      scale: widget.scale,
      enabled: widget.enabled,
      showOutline: false,
      onFocusChange: (bool v) {
        setState(() => _focused = v);
        widget.onFocusChange?.call(v);
      },
      onPressChange: widget.pressedBuilder == null
          ? null
          : (bool v) => setState(() => _pressed = v),
      child: widget.pressedBuilder != null
          ? widget.pressedBuilder!(context, f, _pressed && f)
          : widget.builder!(context, f),
    );
  }
}

/// Voile « désactivé » (§4 disabled). L'ancien code posait un
/// [AnimatedOpacity] permanent autour de CHAQUE tuile : à opacité 1.0 le
/// saveLayer est court-circuité, mais le widget restait dans l'arbre de
/// toutes les grilles (30+ tuiles). Ici la couche d'opacité n'existe QUE
/// pour une tuile réellement désactivée — cas rare.
class _DisabledDim extends StatelessWidget {
  const _DisabledDim({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (enabled) return child;
    return Opacity(opacity: 0.45, child: child);
  }
}
