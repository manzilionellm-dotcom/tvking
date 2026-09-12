// =========================================================
//  home_hook_picker.dart — Ordre du rail « Derniers vus » (D)
// =========================================================
//  Vague 3 recadrée : STABILITÉ > Netflix. On ne crée PAS de rail
//  nouveau, PAS de groupe, PAS de posters. On réordonne le rail
//  « Derniers vus » DÉJÀ AFFICHÉ sur l'accueil TiviMate (8 logos).
//
//  Ce fichier ne FAIT QUE CHOISIR, en mémoire, parmi des Channel
//  déjà chargés. Zéro réseau, zéro EPG, zéro décodage, zéro flux.
//
//  POURQUOI UN MODULE. Le Lanceur fait déjà
//  WatchHistoryRepository.topChannelForSlot → héro. L'accueil D
//  avait le même dépôt et ne l'utilisait pas. Une fonction PURE
//  pour que D et les tests partagent la même règle : habitude de
//  créneau d'abord, puis récents, plafond 8 (le plafond D'AVANT).
// =========================================================

import '../domain/channel.dart';

/// Choix PUR des IDs du rail existant. Testable sans Flutter.
abstract final class HomeHookPicker {
  /// INCHANGÉ par rapport à `_recentChannels` d'avant Vague 3.
  /// 9 logos = pic mémoire en hausse — interdit.
  static const int kMaxRail = 8;

  /// Habitude de créneau [slotChannelId] d'abord (si encore dans
  /// le bouquet), puis les IDs récemment vus. Doublons et IDs
  /// inconnues sautés — jamais d'exception.
  ///
  /// STABILITÉ : pas de `Map` du bouquet (5 000–25 000 entrées
  /// pour 8 lookups). 8 scans linéaires sur des String déjà en
  /// RAM tiennent en sous-milliseconde.
  static List<Channel> continueWatching({
    required List<Channel> all,
    required Iterable<String> recentIds,
    String? slotChannelId,
    int limit = kMaxRail,
  }) {
    if (limit <= 0 || all.isEmpty) return const <Channel>[];
    final List<Channel> out = <Channel>[];
    final Set<String> seen = <String>{};

    void take(String? id) {
      if (id == null || id.isEmpty || !seen.add(id)) return;
      for (final Channel c in all) {
        if (c.id == id) {
          out.add(c);
          return;
        }
      }
    }

    take(slotChannelId);
    if (out.length >= limit) return out;
    for (final String id in recentIds) {
      take(id);
      if (out.length >= limit) break;
    }
    return out;
  }
}
