// =========================================================
//  signal_inbox.dart — Les écrans écoutent le canal
// =========================================================
//  Le bandeau d'annonce et l'écran « mets à jour » ne relisent
//  pas le réseau tout seuls en boucle. Quand un ordre arrive,
//  on les prévient ici. Le dernier nom sert aux tests
//  (« la box a bien vu suspend »).
// =========================================================

import 'package:flutter/foundation.dart';

class SignalInbox extends ChangeNotifier {
  SignalInbox._();
  static final SignalInbox instance = SignalInbox._();

  String? lastKind;
  bool forceBlocked = false;

  /// Noms appliqués depuis le démarrage de cette session.
  /// Les tests chronomètrent jusqu'à ce que le leur apparaisse.
  final List<String> appliedKinds = <String>[];

  void note(String kind) {
    lastKind = kind;
    appliedKinds.add(kind);
    notifyListeners();
  }

  void setForceBlocked(bool value) {
    if (forceBlocked == value) return;
    forceBlocked = value;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    lastKind = null;
    forceBlocked = false;
    appliedKinds.clear();
    notifyListeners();
  }
}
