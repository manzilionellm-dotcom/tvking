// =========================================================
//  watch_progress.dart — « Reprendre là où je me suis arrêté »
// =========================================================
//  Mémorise, POUR CHAQUE film / épisode, la position de lecture et la durée.
//  Sert à :
//    • reprendre automatiquement à la bonne seconde (quelques secondes plus
//      tôt, pour retrouver le fil — comme Netflix) ;
//    • la rangée « Continuer à regarder » (films entamés + pour chaque série
//      son épisode en cours ou le SUIVANT quand le précédent est fini) ;
//    • marquer « vu » (barre pleine) et déclencher l'épisode suivant.
//
//  Règle « terminé » : ≥ 93 % de la durée OU moins de 2 min restantes
//  (générique de fin). Stockage : SharedPreferences (JSON, 400 entrées max,
//  les plus récentes) — survit aux redémarrages et aux mises à jour.
// =========================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une position de lecture mémorisée.
@immutable
class WatchEntry {
  const WatchEntry({
    required this.id,
    required this.isEpisode,
    required this.title,
    required this.streamUrl,
    required this.posMs,
    required this.durMs,
    required this.updatedAt,
    this.subtitle,
    this.posterUrl,
    this.containerExt = 'mp4',
    this.sourceKey = '',
    this.remoteId = '',
    this.seriesId,
    this.season,
    this.episode,
    this.finished = false,
    this.upNext = false,
  });

  /// Identifiant du film / de l'épisode (cf. CinemaTitle.id / CinemaEpisode.id).
  final String id;
  final bool isEpisode;

  /// Film : son titre. Épisode : le NOM DE LA SÉRIE.
  final String title;

  /// Épisode : « S2 · E3 · Titre ». Film : null.
  final String? subtitle;
  final String? posterUrl;
  final String streamUrl;
  final String containerExt;
  final String sourceKey;
  final String remoteId;

  /// Épisode : identifiant de la série (CinemaTitle.id).
  final String? seriesId;
  final int? season;
  final int? episode;

  final int posMs;
  final int durMs;
  final int updatedAt;
  final bool finished;

  /// Épisode SUIVANT proposé après la fin du précédent (position 0).
  final bool upNext;

  double get fraction =>
      durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

  /// À afficher dans « Continuer à regarder » ?
  bool get isResumable => !finished && (upNext || posMs >= 30000);

  /// Position de reprise : 5 s plus tôt pour retrouver le fil.
  Duration get resumeAt {
    if (!isResumable || upNext) return Duration.zero;
    final int ms = posMs - 5000;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  static bool isFinishedAt(int posMs, int durMs) {
    if (durMs <= 0) return false;
    return posMs >= durMs * 0.93 || durMs - posMs <= 120000;
  }

  WatchEntry copyWith({int? posMs, int? durMs, int? updatedAt, bool? finished, bool? upNext}) =>
      WatchEntry(
        id: id,
        isEpisode: isEpisode,
        title: title,
        subtitle: subtitle,
        posterUrl: posterUrl,
        streamUrl: streamUrl,
        containerExt: containerExt,
        sourceKey: sourceKey,
        remoteId: remoteId,
        seriesId: seriesId,
        season: season,
        episode: episode,
        posMs: posMs ?? this.posMs,
        durMs: durMs ?? this.durMs,
        updatedAt: updatedAt ?? this.updatedAt,
        finished: finished ?? this.finished,
        upNext: upNext ?? this.upNext,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'ep': isEpisode,
        't': title,
        if (subtitle != null) 'st': subtitle,
        if (posterUrl != null) 'img': posterUrl,
        'url': streamUrl,
        'ext': containerExt,
        'src': sourceKey,
        'rid': remoteId,
        if (seriesId != null) 'sid': seriesId,
        if (season != null) 's': season,
        if (episode != null) 'e': episode,
        'pos': posMs,
        'dur': durMs,
        'at': updatedAt,
        if (finished) 'fin': true,
        if (upNext) 'next': true,
      };

  static WatchEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String? id = raw['id'] as String?;
    final String? url = raw['url'] as String?;
    if (id == null || url == null) return null;
    int i(Object? v) => v is num ? v.toInt() : 0;
    return WatchEntry(
      id: id,
      isEpisode: raw['ep'] == true,
      title: (raw['t'] as String?) ?? '',
      subtitle: raw['st'] as String?,
      posterUrl: raw['img'] as String?,
      streamUrl: url,
      containerExt: (raw['ext'] as String?) ?? 'mp4',
      sourceKey: (raw['src'] as String?) ?? '',
      remoteId: (raw['rid'] as String?) ?? '',
      seriesId: raw['sid'] as String?,
      season: raw['s'] is num ? (raw['s'] as num).toInt() : null,
      episode: raw['e'] is num ? (raw['e'] as num).toInt() : null,
      posMs: i(raw['pos']),
      durMs: i(raw['dur']),
      updatedAt: i(raw['at']),
      finished: raw['fin'] == true,
      upNext: raw['next'] == true,
    );
  }
}

/// Logique PURE (testable) : ensemble des positions mémorisées.
class WatchProgressStore {
  WatchProgressStore([Iterable<WatchEntry> initial = const <WatchEntry>[]]) {
    for (final WatchEntry e in initial) {
      _byId[e.id] = e;
    }
  }

  static const int maxEntries = 400;
  final Map<String, WatchEntry> _byId = <String, WatchEntry>{};

  WatchEntry? get(String id) => _byId[id];
  Iterable<WatchEntry> get all => _byId.values;

  /// Enregistre une position ; calcule « terminé ». Renvoie l'entrée stockée.
  WatchEntry record(WatchEntry e) {
    final bool fin = WatchEntry.isFinishedAt(e.posMs, e.durMs);
    final WatchEntry stored = e.copyWith(finished: fin, upNext: false);
    _byId[e.id] = stored;
    // Série : une seule « tête » par série dans Continuer — l'épisode qu'on
    // regarde remplace l'ancien « suivant » proposé.
    if (e.seriesId != null) {
      _byId.removeWhere((String k, WatchEntry v) =>
          k != e.id && v.seriesId == e.seriesId && v.upNext);
    }
    _prune();
    return stored;
  }

  /// Propose l'épisode suivant dans « Continuer » (après la fin du précédent).
  void proposeNext(WatchEntry next) {
    final WatchEntry? existing = _byId[next.id];
    if (existing != null && (existing.isResumable || existing.finished)) return;
    _byId[next.id] = next.copyWith(posMs: 0, upNext: true, finished: false);
    _prune();
  }

  /// Retire une entrée de « Continuer » (sans effacer l'état « vu »).
  void dismiss(String id) {
    final WatchEntry? e = _byId[id];
    if (e == null) return;
    if (e.upNext) {
      _byId.remove(id);
    } else {
      _byId[id] = e.copyWith(finished: true);
    }
  }

  /// « Continuer à regarder » : plus récent d'abord ; une seule entrée par
  /// série (la plus récente).
  List<WatchEntry> continueWatching({bool? episodes, int max = 24}) {
    final List<WatchEntry> list = _byId.values
        .where((WatchEntry e) => e.isResumable && (episodes == null || e.isEpisode == episodes))
        .toList()
      ..sort((WatchEntry a, WatchEntry b) => b.updatedAt.compareTo(a.updatedAt));
    final Set<String> seenSeries = <String>{};
    final List<WatchEntry> out = <WatchEntry>[];
    for (final WatchEntry e in list) {
      if (e.seriesId != null && !seenSeries.add(e.seriesId!)) continue;
      out.add(e);
      if (out.length >= max) break;
    }
    return out;
  }

  /// Dernier épisode touché d'une série (reprise depuis la fiche série).
  WatchEntry? latestForSeries(String seriesId) {
    WatchEntry? best;
    for (final WatchEntry e in _byId.values) {
      if (e.seriesId != seriesId) continue;
      if (best == null || e.updatedAt > best.updatedAt) best = e;
    }
    return best;
  }

  void _prune() {
    if (_byId.length <= maxEntries) return;
    final List<WatchEntry> sorted = _byId.values.toList()
      ..sort((WatchEntry a, WatchEntry b) => b.updatedAt.compareTo(a.updatedAt));
    _byId
      ..clear()
      ..addEntries(sorted.take(maxEntries).map((WatchEntry e) => MapEntry<String, WatchEntry>(e.id, e)));
  }

  String encode() => jsonEncode(_byId.values.map((WatchEntry e) => e.toJson()).toList());

  static WatchProgressStore decode(String? raw) {
    if (raw == null || raw.isEmpty) return WatchProgressStore();
    try {
      final Object? list = jsonDecode(raw);
      if (list is! List) return WatchProgressStore();
      return WatchProgressStore(list.map(WatchEntry.fromJson).whereType<WatchEntry>());
    } catch (_) {
      return WatchProgressStore(); // stockage corrompu → on repart propre
    }
  }
}

/// Accès app (persistance + notification des écrans).
class WatchProgressRepository extends ChangeNotifier {
  WatchProgressRepository._();
  static final WatchProgressRepository instance = WatchProgressRepository._();

  static const String _kKey = 'cinema.progress.v1';
  WatchProgressStore _store = WatchProgressStore();
  bool _loaded = false;
  Timer? _saveTimer;

  Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _store = WatchProgressStore.decode(prefs.getString(_kKey));
    _loaded = true;
    notifyListeners();
  }

  WatchEntry? get(String id) => _store.get(id);
  List<WatchEntry> continueWatching({bool? episodes}) =>
      _store.continueWatching(episodes: episodes);
  WatchEntry? latestForSeries(String seriesId) => _store.latestForSeries(seriesId);

  WatchEntry record(WatchEntry e, {bool flushNow = false}) {
    final WatchEntry stored = _store.record(e);
    _scheduleSave(flushNow);
    notifyListeners();
    return stored;
  }

  void proposeNext(WatchEntry next) {
    _store.proposeNext(next);
    _scheduleSave(true);
    notifyListeners();
  }

  void dismiss(String id) {
    _store.dismiss(id);
    _scheduleSave(true);
    notifyListeners();
  }

  /// Écriture groupée (au plus toutes les 3 s) : le lecteur enregistre souvent.
  void _scheduleSave(bool now) {
    _saveTimer?.cancel();
    if (now) {
      unawaited(_save());
    } else {
      _saveTimer = Timer(const Duration(seconds: 3), () => unawaited(_save()));
    }
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, _store.encode());
    } catch (e) {
      if (kDebugMode) debugPrint('[WatchProgress] sauvegarde impossible : $e');
    }
  }
}
