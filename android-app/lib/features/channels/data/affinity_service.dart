// =========================================================
//  affinity_service.dart — Score d'affinité par genre
// =========================================================
//  Lit watch_sessions sur les 30 derniers jours, regroupe par
//  genre (via ChannelClassifier) et produit un score normalisé
//  [0..1] par ChannelGenre. Utilisé par :
//
//    - HomeScreen : réordonne les rangées (le genre dominant
//      remonte en haut).
//    - Time-of-day : combiné avec l'heure courante, on choisit
//      la rangée "hero" appropriée.
//    - Discover Tonight : on shuffle 70% des genres connus +
//      30% inconnus pour le variable reward.
//
//  Performance : le cache se rafraîchit max toutes les 5 min
//  ou explicitement via `refresh()`. Pour 20 000 chaînes /
//  500 sessions ça reste sub-millisecond.
// =========================================================

import 'package:flutter/foundation.dart';

import '../../playlists/data/playlist_repository.dart';
import '../domain/channel.dart';
import '../domain/channel_genre.dart';
import 'watch_history_repository.dart';

class AffinityService extends ChangeNotifier {
  AffinityService._();
  static final AffinityService instance = AffinityService._();

  /// Scores normalisés [0..1] par genre. Le genre le plus regardé
  /// = 1.0. Les genres jamais regardés = 0.0.
  Map<ChannelGenre, double> _scores = <ChannelGenre, double>{};

  /// Durée brute en ms par genre (pour debug / affichage éventuel).
  Map<ChannelGenre, int> _rawMs = <ChannelGenre, int>{};

  /// Liste des genres triés par score décroissant.
  List<ChannelGenre> _rankedGenres = <ChannelGenre>[];

  Map<ChannelGenre, double> get scores =>
      Map<ChannelGenre, double>.unmodifiable(_scores);
  List<ChannelGenre> get rankedGenres =>
      List<ChannelGenre>.unmodifiable(_rankedGenres);

  /// Le genre dominant — celui que l'utilisateur regarde le plus.
  /// `null` si aucun visionnage encore.
  ChannelGenre? get dominantGenre =>
      _rankedGenres.isEmpty ? null : _rankedGenres.first;

  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kRefreshTtl = Duration(minutes: 5);

  /// Force un recalcul. Sinon `ensureFresh()` recalcule au max
  /// toutes les 5 min.
  Future<void> refresh() async {
    final Map<String, int> byChannel = await WatchHistoryRepository
        .instance
        .watchTimeByChannel(days: 30);

    // On a besoin du mapping channelId → genre. Source : la cache
    // mémoire de PlaylistRepository (synchrone, instantanée).
    final List<Channel> all =
        PlaylistRepository.instance.currentChannels;
    final Map<String, ChannelGenre> idToGenre = <String, ChannelGenre>{};
    for (final Channel c in all) {
      idToGenre[c.id] = c.genre;
    }

    final Map<ChannelGenre, int> raw = <ChannelGenre, int>{};
    for (final MapEntry<String, int> e in byChannel.entries) {
      final ChannelGenre? g = idToGenre[e.key];
      if (g == null) continue;
      raw[g] = (raw[g] ?? 0) + e.value;
    }

    // Normalisation : max → 1.0
    int max = 0;
    for (final int v in raw.values) {
      if (v > max) max = v;
    }
    final Map<ChannelGenre, double> scores = <ChannelGenre, double>{};
    if (max > 0) {
      for (final MapEntry<ChannelGenre, int> e in raw.entries) {
        scores[e.key] = e.value / max;
      }
    }

    final List<ChannelGenre> ranked = raw.keys.toList()
      ..sort((ChannelGenre a, ChannelGenre b) =>
          (raw[b] ?? 0).compareTo(raw[a] ?? 0));

    _rawMs = raw;
    _scores = scores;
    _rankedGenres = ranked;
    _lastRefresh = DateTime.now();
    notifyListeners();
  }

  /// Recalcule si la cache est trop vieille.
  Future<void> ensureFresh() async {
    if (DateTime.now().difference(_lastRefresh) > _kRefreshTtl) {
      await refresh();
    }
  }

  /// Score brut en ms pour un genre. 0 si pas de visionnage.
  int rawMsFor(ChannelGenre g) => _rawMs[g] ?? 0;

  /// Retourne `true` si le user a regardé ce genre au moins une fois
  /// sur les 30 derniers jours.
  bool hasWatched(ChannelGenre g) => (_rawMs[g] ?? 0) > 0;
}
