// =========================================================
//  tv_field_keys.dart — Sortir d'un champ avec une télécommande
// =========================================================
//  Cause : un champ d'une seule ligne avale Bas / Haut.
//
//  1. Les raccourcis de texte de Flutter transforment la flèche
//     en « ligne suivante ». Sur une seule ligne, le curseur ne
//     bouge pas, mais la touche est quand même consommée : le
//     focus ne descend pas au mot de passe.
//  2. Clavier ouvert (ou connexion de saisie encore active) :
//     Android, dans InputConnectionAdaptor, fait la même chose
//     et répond « traité » AVANT Flutter. La télécommande
//     infrarouge n'arrive jamais au cadre.
//
//  Ici, Bas / Haut / Entrée demandent le champ suivant ou
//  précédent. Gauche / Droite restent au curseur. Le pont
//  Android (MainActivity) envoie la même demande quand la
//  connexion de saisie mangerait la touche.
// =========================================================

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Pont avec l'activité Android. Sans activité (test, bureau),
/// les raccourcis ci-dessous suffisent.
abstract final class TvFieldNav {
  static const MethodChannel _channel =
      MethodChannel('com.sevenmotion.zuno/field_keys');

  static int _armed = 0;
  static bool _listening = false;

  static void arm() {
    _listen();
    _armed++;
    _push();
  }

  static void disarm() {
    if (_armed > 0) _armed--;
    _push();
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'move' && call.arguments is String) {
        _move(call.arguments as String);
      }
      return null;
    });
  }

  static void _push() {
    _channel.invokeMethod<void>('setArmed', _armed > 0).catchError((Object _) {
      // Pas Android, ou l'activité n'a pas encore le canal.
      return null;
    });
  }

  static void _move(String direction) {
    final BuildContext? context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return;
    final FocusScopeNode scope = FocusScope.of(context);
    if (direction == 'up') {
      scope.previousFocus();
    } else {
      scope.nextFocus();
    }
  }
}

/// À placer AUTOUR d'un [TextField] (ou équivalent), pas autour
/// de tout l'écran : sinon les flèches ne serviraient plus à
/// parcourir les listes.
class TvFieldKeys extends StatefulWidget {
  const TvFieldKeys({super.key, required this.child});

  final Widget child;

  /// Plus proche que les raccourcis de texte de l'application :
  /// c'est cette table qui gagne pour ces touches seulement.
  static const Map<ShortcutActivator, Intent> shortcuts =
      <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
    SingleActivator(LogicalKeyboardKey.enter): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.channelDown): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.channelUp): PreviousFocusIntent(),
    SingleActivator(LogicalKeyboardKey.pageDown): NextFocusIntent(),
    SingleActivator(LogicalKeyboardKey.pageUp): PreviousFocusIntent(),
  };

  @override
  State<TvFieldKeys> createState() => _TvFieldKeysState();
}

class _TvFieldKeysState extends State<TvFieldKeys> {
  bool _inside = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_sync);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_sync);
    if (_inside) TvFieldNav.disarm();
    super.dispose();
  }

  void _sync() {
    final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
    final bool inside = focused != null &&
        focused.mounted &&
        focused.findAncestorStateOfType<_TvFieldKeysState>() == this;
    if (inside == _inside) return;
    _inside = inside;
    if (inside) {
      TvFieldNav.arm();
    } else {
      TvFieldNav.disarm();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: TvFieldKeys.shortcuts,
      child: widget.child,
    );
  }
}
