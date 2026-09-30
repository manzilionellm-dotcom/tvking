// =========================================================
//  time_picks.dart — Ce qu'on regarde à cette heure-ci
// =========================================================
//  Calcul LOCAL. On compte, pour le créneau en cours, les
//  chaînes déjà ouvertes sur cette box. Pas de service
//  extérieur, pas de classement « populaire » mélangé.
//
//  Un créneau = semaine ou week-end × matin / après-midi /
//  soir / nuit. Un créneau vide reste vide : on n'affiche
//  pas « tout l'historique » à la place.
// =========================================================

import 'dart:convert';

/// Quatre moments de la journée, heure LOCALE de la box.
enum TimeBand { morning, afternoon, evening, night }

/// 5 h → midi, midi → 18 h, 18 h → 23 h, sinon la nuit.
TimeBand timeBand(int hour) {
  if (hour >= 5 && hour < 12) return TimeBand.morning;
  if (hour >= 12 && hour < 18) return TimeBand.afternoon;
  if (hour >= 18 && hour < 23) return TimeBand.evening;
  return TimeBand.night;
}

/// Samedi et dimanche. Le reste de la semaine est à part :
/// le lundi matin n'a pas les habitudes du dimanche matin.
bool isWeekendDay(int weekday) =>
    weekday == DateTime.saturday || weekday == DateTime.sunday;

/// Clé stable du créneau. Ex. `wd-evening`, `we-morning`.
String timeSlotKey(DateTime local) {
  final String day = isWeekendDay(local.weekday) ? 'we' : 'wd';
  return '$day-${timeBand(local.hour).name}';
}

/// Cartes affichées sur l'accueil.
const int kTimePickMax = 8;

/// Combien de chaînes on retient par créneau, pas plus.
const int kTimePickKeep = 24;

/// Ajoute un visionnage. Ne modifie pas [book] : on renvoie
/// une copie, pour que les tests comparent avant / après.
Map<String, Map<String, int>> noteTimePick(
  Map<String, Map<String, int>> book,
  String slot,
  String channelId, {
  int keep = kTimePickKeep,
}) {
  if (slot.isEmpty || channelId.isEmpty) return book;
  final Map<String, Map<String, int>> next = <String, Map<String, int>>{
    for (final MapEntry<String, Map<String, int>> e in book.entries)
      e.key: Map<String, int>.from(e.value),
  };
  final Map<String, int> counts =
      Map<String, int>.from(next[slot] ?? const <String, int>{});
  counts[channelId] = (counts[channelId] ?? 0) + 1;
  if (keep > 0 && counts.length > keep) {
    final List<MapEntry<String, int>> ranked = counts.entries.toList()
      ..sort(_byCountThenId);
    next[slot] = Map<String, int>.fromEntries(ranked.take(keep));
  } else {
    next[slot] = counts;
  }
  return next;
}

/// Chaînes du créneau, la plus vue en premier.
/// Créneau absent ou vide → liste vide. On ne pioche pas
/// dans un autre créneau.
List<String> picksForSlot(
  Map<String, Map<String, int>> book,
  String slot, {
  int max = kTimePickMax,
}) {
  final Map<String, int>? counts = book[slot];
  if (counts == null || counts.isEmpty || max <= 0) return const <String>[];
  final List<MapEntry<String, int>> ranked = counts.entries.toList()
    ..sort(_byCountThenId);
  return ranked.take(max).map((MapEntry<String, int> e) => e.key).toList(growable: false);
}

int _byCountThenId(MapEntry<String, int> a, MapEntry<String, int> b) {
  final int byCount = b.value.compareTo(a.value);
  if (byCount != 0) return byCount;
  return a.key.compareTo(b.key);
}

/// Disque → mémoire. Un fichier abîmé donne un carnet vide,
/// jamais une exception vers l'accueil.
Map<String, Map<String, int>> decodeTimePicks(String? raw) {
  if (raw == null || raw.isEmpty) return <String, Map<String, int>>{};
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, Map<String, int>>{};
    final Map<String, Map<String, int>> out = <String, Map<String, int>>{};
    decoded.forEach((Object? slot, Object? counts) {
      if (slot is! String || counts is! Map) return;
      final Map<String, int> row = <String, int>{};
      counts.forEach((Object? id, Object? n) {
        if (id is! String || id.isEmpty) return;
        final int? value = n is int ? n : (n is num ? n.toInt() : null);
        if (value == null || value <= 0) return;
        row[id] = value;
      });
      if (row.isNotEmpty) out[slot] = row;
    });
    return out;
  } catch (_) {
    return <String, Map<String, int>>{};
  }
}

String encodeTimePicks(Map<String, Map<String, int>> book) => jsonEncode(book);
