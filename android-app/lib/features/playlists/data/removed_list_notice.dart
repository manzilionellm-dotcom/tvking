// =========================================================
//  removed_list_notice.dart — La liste vient d'être retirée
// =========================================================
//  Le dépôt de sources pose cet avis APRÈS avoir vraiment
//  supprimé une ligne locale. L'écran TV s'en sert pour
//  expliquer, puis revenir à « Ajouter ma liste » s'il n'en
//  reste plus. On ne l'allume pas si rien n'a été effacé.
// =========================================================

import 'package:flutter/foundation.dart';

@immutable
class RemovedListEvent {
  const RemovedListEvent({
    required this.removed,
    required this.noneLeft,
    required this.token,
  });

  /// Nombre de listes réellement supprimées de la base locale.
  final int removed;

  /// Plus aucune liste en base : l'écran d'ajout doit revenir.
  final bool noneLeft;

  /// Identifiant de cet avis, pour ne pas réafficher le même.
  final int token;
}

class RemovedListNotice {
  RemovedListNotice._();
  static final RemovedListNotice instance = RemovedListNotice._();

  final ValueNotifier<RemovedListEvent?> event =
      ValueNotifier<RemovedListEvent?>(null);

  int _token = 0;

  void signal({required int removed, required bool noneLeft}) {
    if (removed <= 0) return;
    _token++;
    event.value = RemovedListEvent(
      removed: removed,
      noneLeft: noneLeft,
      token: _token,
    );
  }

  @visibleForTesting
  void resetForTesting() {
    _token = 0;
    event.value = null;
  }
}
