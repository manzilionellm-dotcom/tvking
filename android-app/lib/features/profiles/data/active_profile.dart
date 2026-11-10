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
  List<int>? _playlistIds;

  /// Id du profil en cours. Jamais vide.
  String get id => _id;

  List<int>? get playlistIds => _playlistIds;

  /// Une source sans identifiant ne peut appartenir à un profil explicite.
  bool allowsPlaylist(int? id) =>
      _playlistIds == null || (id != null && _playlistIds!.contains(id));

  /// Contrairement au notifier d'identité, celui-ci réveille aussi les
  /// catalogues lorsque le même profil reçoit sa première/nouvelle liste.
  final ValueNotifier<int> scopeListenable = ValueNotifier<int>(0);

  /// Change seulement quand l'id change vraiment.
  final ValueNotifier<String> listenable =
      ValueNotifier<String>(ProfileIds.origin);

  void set(String next, {List<int>? playlistIds}) {
    if (next.isEmpty) return;
    final List<int>? selection = playlistIds == null
        ? null
        : List<int>.unmodifiable(playlistIds.where((int id) => id > 0).toSet());
    if (next == _id && listEquals(selection, _playlistIds)) return;
    _id = next;
    _playlistIds = selection;
    listenable.value = next;
    scopeListenable.value++;
  }
}
