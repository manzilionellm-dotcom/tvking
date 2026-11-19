// =========================================================
//  tv_remote_shortcuts.dart — Touches qui doivent marcher partout
// =========================================================
//  Le focus Flutter connaît les flèches et Entrée. Il ignore
//  souvent BUTTON_B, Page haut/bas et Canal +/−. On les ajoute
//  UNE fois, au-dessus de tous les écrans.
//
//  L'écran qui a le focus passe d'abord. Le lecteur, lui,
//  consomme Canal +/− pour zapper : ce raccourci ne se déclenche
//  que si personne n'a pris la touche. Une liste, alors, bouge.
//  Rien ici n'avale une touche inconnue : pas de piège.
// =========================================================

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Raccourcis ajoutés à ceux de Material. Les flèches restent
/// celles du système : on ne les redéfinit pas.
final Map<ShortcutActivator, Intent> tvRemoteShortcutIntents =
    <ShortcutActivator, Intent>{
  const SingleActivator(LogicalKeyboardKey.gameButtonB): const DismissIntent(),
  const SingleActivator(LogicalKeyboardKey.gameButtonSelect):
      const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.pageUp): const ScrollIntent(
    direction: AxisDirection.up,
    type: ScrollIncrementType.page,
  ),
  const SingleActivator(LogicalKeyboardKey.pageDown): const ScrollIntent(
    direction: AxisDirection.down,
    type: ScrollIncrementType.page,
  ),
  const SingleActivator(LogicalKeyboardKey.channelUp):
      const DirectionalFocusIntent(TraversalDirection.up),
  const SingleActivator(LogicalKeyboardKey.channelDown):
      const DirectionalFocusIntent(TraversalDirection.down),
};

class TvRemoteShortcuts extends StatelessWidget {
  const TvRemoteShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: tvRemoteShortcutIntents,
      child: child,
    );
  }
}
