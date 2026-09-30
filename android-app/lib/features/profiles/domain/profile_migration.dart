// =========================================================
//  profile_migration.dart — Rien ne se perd au passage
// =========================================================
//  Les favoris et l'historique vivaient dans des tables SQLite
//  SANS colonne « profil » (une seule personne implicite).
//  On ne peut pas y mettre deux personnes : la clé primaire
//  est l'id de chaîne, une seule fois.
//
//  Alors on COPIE ces lignes dans une nouvelle table, rangées
//  sous le profil 1, et on LAISSE l'ancienne table en place
//  (copie de secours, jamais vidée par ce code).
//
//  La copie ne se fait qu'UNE FOIS. Sinon, un favori retiré
//  du profil 1 reviendrait au prochain démarrage, recopié
//  depuis la vieille table.
// =========================================================

import 'family_profile.dart';

abstract final class ProfileMigration {
  /// `true` tant qu'on n'a pas encore copié. Dès que le drapeau
  /// disque est posé, on ne touche plus à l'ancienne table.
  static bool shouldCopyLegacy({required bool alreadyMigrated}) =>
      !alreadyMigrated;

  /// Ajoute chaque id historique au profil 1.
  /// Ne retire JAMAIS un id : ni ceux du profil 1 déjà là,
  /// ni ceux des autres profils.
  static Map<String, Set<String>> mergeFavorites({
    required Iterable<String> legacyIds,
    required Map<String, Set<String>> scoped,
  }) {
    final Map<String, Set<String>> out = <String, Set<String>>{
      for (final MapEntry<String, Set<String>> e in scoped.entries)
        e.key: <String>{...e.value},
    };
    final Set<String> origin = out.putIfAbsent(ProfileIds.origin, () => <String>{});
    for (final String id in legacyIds) {
      if (id.isEmpty) continue;
      origin.add(id);
    }
    return out;
  }

  /// Copie l'historique (chaîne → instant) vers le profil 1.
  /// Si le profil 1 a DÉJÀ cette chaîne, on garde SON instant
  /// (le plus récent connu du tiroir), on n'écrase pas avec
  /// la vieille table.
  static Map<String, Map<String, int>> mergeHistory({
    required Map<String, int> legacy,
    required Map<String, Map<String, int>> scoped,
  }) {
    final Map<String, Map<String, int>> out = <String, Map<String, int>>{
      for (final MapEntry<String, Map<String, int>> e in scoped.entries)
        e.key: <String, int>{...e.value},
    };
    final Map<String, int> origin =
        out.putIfAbsent(ProfileIds.origin, () => <String, int>{});
    legacy.forEach((String channelId, int ts) {
      if (channelId.isEmpty) return;
      origin.putIfAbsent(channelId, () => ts);
    });
    return out;
  }
}
