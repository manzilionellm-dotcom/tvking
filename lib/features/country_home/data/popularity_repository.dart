// =========================================================
//  popularity_repository.dart — Score de popularité LOCAL
// =========================================================
//  À défaut de stats serveur, on calcule un proxy local par chaîne :
//     score = (ouvertures × 3) + (favori × 5) + bonus de récence
//  persisté en SharedPreferences (lecture instantanée au boot).
//
//  IMPORTANT : toute l'UI passe par `getPopularChannels()`. Le jour où
//  un vrai compteur serveur existe, il suffit de réécrire CETTE méthode
//  (ou d'injecter les scores serveur) sans toucher à l'écran.
//
//  Aucune dépendance au cast.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../channels/domain/channel.dart';
import '../../playlists/data/favorites_repository.dart';

class PopularityRepository {
  PopularityRepository._();
  static final PopularityRepository instance = PopularityRepository._();

  static const String _kOpensKey = 'pop.opens.v1';
  static const String _kLastKey = 'pop.last.v1';

  Map<String, int> _opens = <String, int>{};
  Map<String, int> _lastOpenMs = <String, int>{};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      _opens = _decode(p.getString(_kOpensKey));
      _lastOpenMs = _decode(p.getString(_kLastKey));
    } catch (e) {
      if (kDebugMode) debugPrint('[Popularity] load: $e');
    }
  }

  Map<String, int> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final Object? d = jsonDecode(raw);
      if (d is Map) {
        return d.map((Object? k, Object? v) => MapEntry<String, int>(
            '$k', v is int ? v : int.tryParse('$v') ?? 0));
      }
    } catch (_) {}
    return <String, int>{};
  }

  /// À appeler quand l'utilisateur OUVRE une chaîne (avant de lancer la
  /// lecture). Best-effort : n'interrompt jamais la lecture.
  Future<void> recordOpen(String channelId) async {
    if (channelId.isEmpty) return;
    _opens[channelId] = (_opens[channelId] ?? 0) + 1;
    _lastOpenMs[channelId] = DateTime.now().millisecondsSinceEpoch;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString(_kOpensKey, jsonEncode(_opens));
      await p.setString(_kLastKey, jsonEncode(_lastOpenMs));
    } catch (_) {/* best-effort */}
  }

  /// Score d'une chaîne (plus haut = plus populaire).
  int scoreFor(Channel c, Set<String> favorites) {
    final int opens = _opens[c.id] ?? 0;
    final int fav = favorites.contains(c.id) ? 5 : 0;
    int recency = 0;
    final int? last = _lastOpenMs[c.id];
    if (last != null) {
      final int ageH =
          (DateTime.now().millisecondsSinceEpoch - last) ~/ 3600000;
      if (ageH < 24) {
        recency = 4;
      } else if (ageH < 24 * 7) {
        recency = 2;
      }
    }
    return opens * 3 + fav + recency;
  }

  /// Top chaînes par popularité décroissante. Au 1er lancement (aucun
  /// historique), on retombe sur un défaut sensé : chaînes LIVE d'abord,
  /// puis ordre playlist — pour que la rangée ne soit jamais vide.
  List<Channel> getPopularChannels(List<Channel> channels, {int top = 10}) {
    if (channels.isEmpty) return const <Channel>[];
    final Set<String> favs = FavoritesRepository.instance.current;
    final List<Channel> sorted = List<Channel>.of(channels);
    sorted.sort((Channel a, Channel b) {
      final int sb = scoreFor(b, favs);
      final int sa = scoreFor(a, favs);
      if (sb != sa) return sb.compareTo(sa);
      // Égalité (souvent 0 au début) : LIVE d'abord, puis nom.
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted.take(top).toList();
  }
}
