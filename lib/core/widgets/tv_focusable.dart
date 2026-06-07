// =========================================================
//  tv_focusable.dart — Wrapper focus-aware pour TV / D-pad
// =========================================================
//  Composant transverse qui rend N'IMPORTE QUEL widget
//  pleinement utilisable à la télécommande Android TV /
//  Fire TV / Google TV :
//
//    1. FOCUS RING — bordure ember + glow + scale animé.
//       Mêmes valeurs sur toute l'app, donc la télécommande
//       envoie toujours le même signal visuel ("je suis ici").
//
//    2. SCROLL-ON-FOCUS — quand l'élément reçoit le focus,
//       l'app appelle `Scrollable.ensureVisible(context)` qui
//       fait scroller la liste parente pour ramener l'élément
//       à un endroit confortable. Sans ça, l'utilisateur peut
//       focusser une carte hors-écran et ne pas savoir où il
//       est. C'est le bug N°1 d'UX télécommande Flutter.
//
//    3. ACCESSIBILITÉ — respecte `MediaQuery.disableAnimationsOf`
//       (réglage système "Réduire les animations" Android).
//       Quand actif, le scale et la transition deviennent
//       instantanés au lieu de tween 180 ms.
//
//    4. DRY — la majorité des FocusableActionDetector +
//       AnimatedScale + Border + Glow custom écrits manuellement
//       dans l'app sont remplaçables par ce widget. Un seul
//       endroit pour régler le look TV.
//
//  Pédagogie :
//    - `FocusableActionDetector` est le widget Flutter standard
//      qui mappe les intents (ActivateIntent = touche OK/Enter)
//      à des callbacks. On surcouche dessus pour ajouter le
//      visuel ember BLACK7 ROYAL.
//    - `Scrollable.ensureVisible` cherche en remontant l'arbre
//      le Scrollable le plus proche et anime son scroll. Si on
//      n'est pas dans un Scrollable, il ne fait rien — donc
//      `TvFocusable` reste safe à utiliser n'importe où.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';
import 'tv_accent_scope.dart';

/// Wrapper focus-aware pour la télécommande.
///
/// Exemple :
/// ```dart
/// TvFocusable(
///   onTap: () => playChannel(channel),
///   child: ChannelLogo(channel: channel),
/// )
/// ```
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    required this.child,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.focusedScale = 1.06,
    this.borderRadius,
    this.borderWidth = 2.4,
    this.unfocusedBorderColor,
    this.focusedBorderColor,
    this.ensureVisibleAlignment = 0.3,
    this.showGlow = true,
    this.semanticsLabel,
    super.key,
  });

  /// Le contenu encapsulé (carte, icône, bouton, etc.).
  final Widget child;

  /// Appelé sur OK télécommande / Enter clavier / tap doigt.
  final VoidCallback onTap;

  /// Optionnel — pour ré-injecter le focus depuis l'extérieur
  /// (ex. autofocus géré par l'écran parent).
  final FocusNode? focusNode;

  /// Si true, prend le focus au premier rendu de l'écran.
  /// Un seul `autofocus: true` par écran sinon Flutter prend
  /// le premier rencontré (pas de garantie d'ordre).
  final bool autofocus;

  /// Facteur d'agrandissement au focus. 1.06 = +6 %, suffisant
  /// pour signaler la sélection sans être tape-à-l'œil.
  final double focusedScale;

  /// Rayon de coupe (border + clip). Défaut 14 px = cohérence
  /// avec le reste du design BLACK7 ROYAL.
  final BorderRadius? borderRadius;

  /// Épaisseur de la bordure au focus.
  final double borderWidth;

  /// Couleur de bordure quand NON focusé. Défaut transparent
  /// pour les éléments plats qui ne veulent pas de cadre dessiné
  /// en permanence. Mettre `AppColors.border` si on veut un
  /// cadre subtil même au repos.
  final Color? unfocusedBorderColor;

  /// Couleur de la bordure (et teinte du halo) au focus. Ordre de
  /// priorité : ce paramètre > `TvAccentScope` ambiant > ember par
  /// défaut. Permet d'imposer ponctuellement une couleur précise sans
  /// dépendre du scope.
  final Color? focusedBorderColor;

  /// Position visée pour le scroll auto-recentrage. 0.0 = haut
  /// de l'écran, 0.5 = centre, 1.0 = bas. Défaut 0.3 = un peu
  /// au-dessus du centre (confort de lecture).
  final double ensureVisibleAlignment;

  /// Si true, le focus déclenche aussi le halo ember (BoxShadow).
  /// Désactiver dans les listes denses où on ne veut pas que les
  /// glows débordent.
  final bool showGlow;

  /// Optionnel — label TalkBack / lecteur d'écran. À fournir
  /// quand le contenu n'a pas de texte intrinsèque.
  final String? semanticsLabel;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final Duration animDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    final BorderRadius radius = widget.borderRadius ?? BorderRadius.circular(14);

    // Résolution de l'accent de focus : override explicite >
    // TvAccentScope ambiant (TV violet) > ember par défaut (téléphone).
    final TvAccentScope? scope = TvAccentScope.maybeOf(context);
    final Color focusColor = widget.focusedBorderColor ??
        scope?.focusBorderColor ??
        AppColors.accent;
    final List<BoxShadow> glow =
        scope?.focusGlow ?? AppColors.emberGlowShadow;

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: _handleFocusChange,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Semantics(
        label: widget.semanticsLabel,
        button: true,
        focusable: true,
        focused: _focused,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: radius,
            child: AnimatedScale(
              scale: _focused ? widget.focusedScale : 1.0,
              duration: animDuration,
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: animDuration,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: _focused
                        ? focusColor
                        : (widget.unfocusedBorderColor ?? Colors.transparent),
                    width: _focused ? widget.borderWidth : 1,
                  ),
                  boxShadow: (_focused && widget.showGlow) ? glow : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Appelé par `FocusableActionDetector` quand le focus visuel
  /// entre ou sort. On distingue ici "focus visuel" et "focus
  /// applicatif" — Flutter highlight le focus uniquement quand
  /// l'utilisateur navigue au clavier/D-pad (pas au mouse hover
  /// par exemple). C'est exactement ce qu'on veut.
  void _handleFocusChange(bool focused) {
    if (!mounted) return;
    setState(() => _focused = focused);

    // Scroll-on-focus : on attend la fin de la frame en cours
    // (sinon `ensureVisible` peut tourner avant que le ListView
    // ait fini de mesurer l'enfant et faire un saut visuel
    // saccadé). `addPostFrameCallback` est le pattern Flutter
    // standard pour "attends la prochaine frame stable".
    if (focused) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // `Scrollable.ensureVisible` est l'API publique qui remonte
        // l'arbre pour trouver le Scrollable parent et anime son
        // offset. Si on n'est dans aucun Scrollable, c'est un no-op
        // silencieux — donc `TvFocusable` reste utilisable partout.
        Scrollable.ensureVisible(
          context,
          alignment: widget.ensureVisibleAlignment,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }
}
