// =========================================================
//  active_profile.dart — Qui regarde, MAINTENANT
// =========================================================
//  Lisible tout de suite, sans attendre le disque ni un choix
//  à l'écran. Au tout premier instant c'est le profil 1
//  (les données déjà là). Si le disque dit ensuite « Enfants »,
//  on prévient les tiroirs (favoris, historique, reprise…)
//  et ils se rechargent. Une chaîne déjà lancée n'est pas coupée :
//  ce notifier ne parle pas au lecteur.
// =========================================================

import 'package:flutter/foundation.dart';

import '../domain/family_profile.dart';

class ActiveProfile {
  ActiveProfile._();
  static final ActiveProfile instance = ActiveProfile._();

  String _id = ProfileIds.origin;

  /// Id du profil en cours. Jamais vide.
  String get id => _id;

  /// Change seulement quand l'id change vraiment.
  final ValueNotifier<String> listenable = ValueNotifier<String>(ProfileIds.origin);

  void set(String next) {
    if (next.isEmpty || next == _id) return;
    _id = next;
    listenable.value = next;
  }
}
