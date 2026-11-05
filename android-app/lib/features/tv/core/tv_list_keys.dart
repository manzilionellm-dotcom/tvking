// =========================================================
//  tv_list_keys.dart — Le D-pad reste dans sa colonne
// =========================================================
//  Flutter cherche la cible d'une flèche dans tout l'écran.
//  Au bout d'une liste courte, Bas partait donc dans la
//  colonne voisine (sur l'écran Direct, le focus d'une
//  catégorie change la liste affichée). Gauche, lui, visait
//  la ligne la plus proche en hauteur, pas celle d'où l'on
//  venait.
// =========================================================

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tv_remote_map.dart';

/// À placer autour d'UNE ligne focusable d'une liste verticale.
class TvListRowKeys extends StatelessWidget {
  const TvListRowKeys({
    super.key,
    required this.child,
    this.last = false,
    this.onLeft,
  });

  final Widget child;

  /// Dernière ligne : Bas et Canal − (raccourci de Bas) restent ici.
  final bool last;

  /// Gauche. `true` = le focus a été placé ; sinon la recherche
  /// habituelle de Flutter s'applique.
  final bool Function()? onLeft;

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final TvRemoteAction? action = readTvRemoteKey(event.logicalKey)?.action;
    if (last &&
        (action == TvRemoteAction.down ||
            action == TvRemoteAction.channelDown)) {
      return KeyEventResult.handled;
    }
    if (action == TvRemoteAction.left && (onLeft?.call() ?? false)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    includeSemantics: false,
    onKeyEvent: _onKey,
    child: child,
  );
}
