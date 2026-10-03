// =========================================================
//  show_taste.dart — Ce que la box a retenu, tout seul
// =========================================================
//  Calcul LOCAL. Rien ne part de la box. On ne garde qu'un
//  petit carnet : le titre, le temps regardé, le créneau
//  jour/heure, et si la personne a appuyé sur « Suivre ».
//
//  Une émission est suivie si AU MOINS une de ces choses
//  est vraie :
//    • elle a été marquée à la télécommande (épinglée) ;
//    • l'image est restée environ 15 minutes en tout ;
//    • le même jour de la semaine ET la même heure, au
//      moins deux fois (une habitude) ;
//    • la chaîne est encore dans les favoris ET on a déjà
//      regardé cette émission 8 minutes dessus.
//  Un zapping de quelques secondes ne compte pas. Un favori
//  tout seul ne suit pas toutes les émissions de la chaîne :
//  sinon le bandeau parlerait toute la journée.
// =========================================================

import 'dart:convert';

import 'show_title.dart';

/// Temps d'image cumulé à partir duquel l'émission est suivie.
const int kFollowWatchMs = 15 * 60 * 1000;

/// Sur une chaîne favorite, la barre est plus basse.
const int kFavoriteBoostMs = 8 * 60 * 1000;

/// Deux fois le même jour et la même heure : c'est une habitude.
const int kRecurTimes = 2;

/// Au-delà de 45 minutes sans y revenir, c'est une autre séance.
/// On ne compte pas 40 minutes d'affilée comme 40 habitudes.
const int kSessionGapMs = 45 * 60 * 1000;

/// On ignore un ajout plus court qu'une seconde (bruit).
const int kMinNoteMs = 1000;

/// Plafond du carnet. Au-delà, on oublie la moins regardée
/// qui n'est pas épinglée.
const int kTasteKeep = 40;

/// Rappels déjà montrés. Au-delà, on oublie les plus anciens.
const int kSeenKeep = 80;

/// Un rappel plus vieux que ça ne sert plus.
const int kSeenHorizonMs = 36 * 60 * 60 * 1000;

/// « mercredi 20 h » → `3-20`. L'heure est CELLE qu'on nous
/// donne (déjà locale). On ne convertit pas une deuxième fois :
/// les tests passent l'heure qu'ils veulent.
String habitSlot(DateTime wall) => '${wall.weekday}-${wall.hour}';

/// Heure murale d'un instant UTC, décalée de [utcOffset].
///
/// `DateTime.add` sur une date UTC reste en UTC : l'heure lue
/// est l'heure du fuseau, pas celle de la machine qui lance
/// le test. Minuit est géré (23 h 30 + 2 h = 1 h 30 le lendemain).
DateTime wallTime(int epochMs, Duration utcOffset) {
  final DateTime utc =
      DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
  return utc.add(utcOffset);
}

/// Une émission retenue. Objet simple, sans Flutter.
class ShowTaste {
  const ShowTaste({
    required this.key,
    required this.title,
    required this.channelId,
    required this.watchMs,
    required this.favoriteWatchMs,
    required this.favoriteChannelId,
    required this.sessions,
    required this.pinned,
    required this.slots,
    required this.lastMs,
  });

  final String key;
  final String title;
  final String channelId;
  final int watchMs;
  final int favoriteWatchMs;

  /// Chaîne sur laquelle le temps « favori » a été compté.
  /// Vide si on ne l'a jamais regardée pendant qu'elle était favorite.
  final String favoriteChannelId;

  final int sessions;
  final bool pinned;

  /// Créneau jour/heure → nombre de séances.
  final Map<String, int> slots;

  final int lastMs;

  ShowTaste copyWith({
    String? title,
    String? channelId,
    int? watchMs,
    int? favoriteWatchMs,
    String? favoriteChannelId,
    int? sessions,
    bool? pinned,
    Map<String, int>? slots,
    int? lastMs,
  }) {
    return ShowTaste(
      key: key,
      title: title ?? this.title,
      channelId: channelId ?? this.channelId,
      watchMs: watchMs ?? this.watchMs,
      favoriteWatchMs: favoriteWatchMs ?? this.favoriteWatchMs,
      favoriteChannelId: favoriteChannelId ?? this.favoriteChannelId,
      sessions: sessions ?? this.sessions,
      pinned: pinned ?? this.pinned,
      slots: slots ?? this.slots,
      lastMs: lastMs ?? this.lastMs,
    );
  }
}

/// Carnet + rappels déjà affichés. Immuable : chaque changement
/// renvoie une copie, pour que les tests comparent avant / après.
class ShowBook {
  const ShowBook({
    this.shows = const <String, ShowTaste>{},
    this.seen = const <String>[],
  });

  final Map<String, ShowTaste> shows;
  final List<String> seen;

  static const ShowBook empty = ShowBook();
}

/// Vrai si cette émission mérite un rappel.
///
/// [favoriteIds] est l'ensemble ACTUEL des chaînes en cœur.
/// Si on retire le cœur, le raccourci « 8 minutes » s'en va.
/// Le temps total et l'habitude, eux, restent.
bool isFollowed(ShowTaste taste, Set<String> favoriteIds) {
  if (taste.pinned) return true;
  if (taste.watchMs >= kFollowWatchMs) return true;
  if (taste.slots.values.any((int n) => n >= kRecurTimes)) return true;
  if (taste.favoriteChannelId.isNotEmpty &&
      favoriteIds.contains(taste.favoriteChannelId) &&
      taste.favoriteWatchMs >= kFavoriteBoostMs) {
    return true;
  }
  return false;
}

/// Clés des émissions suivies, pour filtrer le guide.
Set<String> followedKeys(ShowBook book, Set<String> favoriteIds) {
  final Set<String> out = <String>{};
  for (final ShowTaste taste in book.shows.values) {
    if (isFollowed(taste, favoriteIds)) out.add(taste.key);
  }
  return out;
}

/// Chaînes où l'on a vu une émission suivie. On interroge
/// le guide de celles-là en priorité (peu de requêtes).
List<String> followedChannelIds(
  ShowBook book,
  Set<String> favoriteIds, {
  int max = 8,
}) {
  if (max <= 0) return const <String>[];
  final List<String> out = <String>[];
  for (final ShowTaste taste in book.shows.values) {
    if (!isFollowed(taste, favoriteIds)) continue;
    if (taste.channelId.isEmpty || out.contains(taste.channelId)) continue;
    out.add(taste.channelId);
    if (out.length >= max) break;
  }
  return out;
}

/// Ajoute du temps d'image. Ne modifie pas [book].
ShowBook addWatch(
  ShowBook book, {
  required String title,
  required String channelId,
  required int addMs,
  required DateTime wall,
  required int nowMs,
  required bool channelFavorite,
}) {
  final String key = showKey(title);
  if (key.isEmpty || channelId.isEmpty || addMs < kMinNoteMs) return book;
  final ShowTaste? prev = book.shows[key];
  final bool newSession = prev == null || nowMs - prev.lastMs > kSessionGapMs;
  final Map<String, int> slots =
      Map<String, int>.from(prev?.slots ?? <String, int>{});
  if (newSession) {
    final String slot = habitSlot(wall);
    slots[slot] = (slots[slot] ?? 0) + 1;
  }
  final int favMs =
      (prev?.favoriteWatchMs ?? 0) + (channelFavorite ? addMs : 0);
  final String favChannel =
      channelFavorite ? channelId : (prev?.favoriteChannelId ?? '');
  final ShowTaste next = ShowTaste(
    key: key,
    title: title.trim().isEmpty ? (prev?.title ?? title) : title.trim(),
    channelId: channelId,
    watchMs: (prev?.watchMs ?? 0) + addMs,
    favoriteWatchMs: favMs,
    favoriteChannelId: favChannel,
    sessions: (prev?.sessions ?? 0) + (newSession ? 1 : 0),
    pinned: prev?.pinned ?? false,
    slots: slots,
    lastMs: nowMs,
  );
  return _put(book, next);
}

/// Épingle ou retire l'épingle. Le temps déjà compté reste.
ShowBook setPinned(
  ShowBook book, {
  required String title,
  required String channelId,
  required int nowMs,
  required bool pinned,
}) {
  final String key = showKey(title);
  if (key.isEmpty) return book;
  final ShowTaste? prev = book.shows[key];
  if (prev == null && !pinned) return book;
  final ShowTaste next = ShowTaste(
    key: key,
    title: title.trim().isEmpty ? (prev?.title ?? '') : title.trim(),
    channelId: channelId.isEmpty ? (prev?.channelId ?? '') : channelId,
    watchMs: prev?.watchMs ?? 0,
    favoriteWatchMs: prev?.favoriteWatchMs ?? 0,
    favoriteChannelId: prev?.favoriteChannelId ?? '',
    sessions: prev?.sessions ?? 0,
    pinned: pinned,
    slots: Map<String, int>.from(prev?.slots ?? <String, int>{}),
    lastMs: nowMs,
  );
  return _put(book, next);
}

ShowBook rememberAlert(ShowBook book, String alertKey, int nowMs) {
  if (alertKey.isEmpty || book.seen.contains(alertKey)) return book;
  return ShowBook(
    shows: book.shows,
    seen: pruneSeen(<String>[...book.seen, alertKey], nowMs),
  );
}

/// Oublie les rappels trop vieux, puis borne la liste.
List<String> pruneSeen(List<String> seen, int nowMs) {
  final List<String> kept = <String>[];
  for (final String key in seen) {
    if (key.isEmpty) continue;
    final int? start = startOfAlertKey(key);
    if (start != null && start + kSeenHorizonMs < nowMs) continue;
    kept.add(key);
  }
  if (kept.length <= kSeenKeep) return kept;
  return kept.sublist(kept.length - kSeenKeep);
}

/// `chaine@debut@moment` — l'identifiant de chaîne peut
/// lui-même contenir un `@`, donc on lit la fin.
int? startOfAlertKey(String key) {
  final List<String> parts = key.split('@');
  if (parts.length < 3) return null;
  return int.tryParse(parts[parts.length - 2]);
}

ShowBook _put(ShowBook book, ShowTaste taste) {
  final Map<String, ShowTaste> shows = Map<String, ShowTaste>.from(book.shows);
  shows[taste.key] = taste;
  return ShowBook(shows: _cap(shows, taste.key), seen: book.seen);
}

Map<String, ShowTaste> _cap(Map<String, ShowTaste> shows, String keep) {
  if (shows.length <= kTasteKeep) return shows;
  String? drop;
  int worst = 1 << 62;
  for (final ShowTaste taste in shows.values) {
    if (taste.key == keep || taste.pinned) continue;
    if (taste.watchMs < worst) {
      worst = taste.watchMs;
      drop = taste.key;
    }
  }
  drop ??= shows.keys.firstWhere((String k) => k != keep, orElse: () => keep);
  if (drop == keep) return shows;
  shows.remove(drop);
  return shows;
}

/// Disque → mémoire. Un fichier abîmé donne un carnet vide,
/// jamais une exception vers l'accueil.
ShowBook decodeShowBook(String? raw) {
  if (raw == null || raw.isEmpty) return ShowBook.empty;
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) return ShowBook.empty;
    final Map<String, ShowTaste> shows = <String, ShowTaste>{};
    final Object? rawShows = decoded['shows'];
    if (rawShows is Map) {
      rawShows.forEach((Object? key, Object? value) {
        final ShowTaste? taste = _tasteFromJson(key, value);
        if (taste != null) shows[taste.key] = taste;
      });
    }
    final List<String> seen = <String>[];
    final Object? rawSeen = decoded['seen'];
    if (rawSeen is List) {
      for (final Object? item in rawSeen) {
        final String key = item?.toString() ?? '';
        if (key.isNotEmpty) seen.add(key);
      }
    }
    return ShowBook(shows: shows, seen: seen);
  } catch (_) {
    return ShowBook.empty;
  }
}

String encodeShowBook(ShowBook book) {
  return jsonEncode(<String, Object?>{
    'shows': <String, Object?>{
      for (final ShowTaste taste in book.shows.values)
        taste.key: _tasteToJson(taste),
    },
    'seen': book.seen,
  });
}

Map<String, Object?> _tasteToJson(ShowTaste taste) => <String, Object?>{
      't': taste.title,
      'c': taste.channelId,
      'w': taste.watchMs,
      'f': taste.favoriteWatchMs,
      'fc': taste.favoriteChannelId,
      'n': taste.sessions,
      'p': taste.pinned,
      's': taste.slots,
      'last': taste.lastMs,
    };

ShowTaste? _tasteFromJson(Object? key, Object? raw) {
  if (key is! String || raw is! Map) return null;
  final String id = showKey(key);
  if (id.isEmpty) return null;
  final String title = '${raw['t'] ?? ''}'.trim();
  if (title.isEmpty) return null;
  final Map<String, int> slots = <String, int>{};
  final Object? rawSlots = raw['s'];
  if (rawSlots is Map) {
    rawSlots.forEach((Object? slot, Object? n) {
      if (slot is! String || slot.isEmpty) return;
      final int? value = n is int ? n : (n is num ? n.toInt() : null);
      if (value == null || value <= 0) return;
      slots[slot] = value;
    });
  }
  int numOf(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
  return ShowTaste(
    key: id,
    title: title,
    channelId: '${raw['c'] ?? ''}'.trim(),
    watchMs: numOf(raw['w']),
    favoriteWatchMs: numOf(raw['f']),
    favoriteChannelId: '${raw['fc'] ?? ''}'.trim(),
    sessions: numOf(raw['n']),
    pinned: raw['p'] == true,
    slots: slots,
    lastMs: numOf(raw['last']),
  );
}
