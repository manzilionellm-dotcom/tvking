// =========================================================
//  reminder_book.dart — Carnet de rappels d'UN profil
// =========================================================
//  L'alarme Android (la notification) est commune à la box.
//  Pour que les rappels soient QUAND MÊME séparés, on note
//  dans ce carnet QUI a demandé QUOI. En changeant de profil
//  on annule les alarmes de l'autre et on repose les nôtres.
//
//  L'id de notification est un nombre STABLE (même calcul à
//  chaque lancement). Le hashCode Dart des String change
//  d'une exécution à l'autre : on ne s'en sert pas, sinon
//  on ne pourrait plus annuler le rappel au prochain boot.
// =========================================================

import 'dart:convert';

class ProgramReminder {
  const ProgramReminder({
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.startMs,
    required this.leadMinutes,
  });

  final String channelId;
  final String channelName;
  final String title;

  /// Début du programme, epoch millisecondes.
  final int startMs;

  /// Combien de minutes avant le début on sonne.
  final int leadMinutes;

  Map<String, Object?> toJson() => <String, Object?>{
        'c': channelId,
        'n': channelName,
        't': title,
        's': startMs,
        'l': leadMinutes,
      };

  static ProgramReminder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String channelId = raw['c']?.toString() ?? '';
    final int start = (raw['s'] as num?)?.toInt() ?? 0;
    if (channelId.isEmpty || start <= 0) return null;
    final int lead = (raw['l'] as num?)?.toInt() ?? 5;
    return ProgramReminder(
      channelId: channelId,
      channelName: raw['n']?.toString() ?? '',
      title: raw['t']?.toString() ?? '',
      startMs: start,
      leadMinutes: lead < 0 ? 0 : lead,
    );
  }
}

class ReminderBook {
  const ReminderBook([this.items = const <ProgramReminder>[]]);

  static const int maxEntries = 40;

  final List<ProgramReminder> items;

  /// Ajoute ou remplace le même programme (même chaîne + même début).
  /// Oublie ce qui est déjà passé (plus de 2 min) et garde les 40
  /// prochains au plus.
  ReminderBook upsert(ProgramReminder reminder, {required int nowMs}) {
    final List<ProgramReminder> next = <ProgramReminder>[
      for (final ProgramReminder e in items)
        if (!_same(e, reminder) && !_expired(e, nowMs)) e,
      reminder,
    ]..sort((ProgramReminder a, ProgramReminder b) => a.startMs.compareTo(b.startMs));
    if (next.length <= maxEntries) return ReminderBook(next);
    return ReminderBook(next.sublist(next.length - maxEntries));
  }

  ReminderBook remove(String channelId, int startMs) => ReminderBook(<ProgramReminder>[
        for (final ProgramReminder e in items)
          if (e.channelId != channelId || e.startMs != startMs) e,
      ]);

  /// Ceux qui n'ont pas encore commencé : on peut encore les poser.
  List<ProgramReminder> pending(int nowMs) => <ProgramReminder>[
        for (final ProgramReminder e in items)
          if (e.startMs > nowMs) e,
      ];

  String encode() => jsonEncode(items.map((ProgramReminder e) => e.toJson()).toList());

  static ReminderBook decode(String? raw) {
    if (raw == null || raw.isEmpty) return const ReminderBook();
    try {
      final Object? list = jsonDecode(raw);
      if (list is! List) return const ReminderBook();
      return ReminderBook(<ProgramReminder>[
        for (final Object? item in list)
          if (ProgramReminder.fromJson(item) != null) ProgramReminder.fromJson(item)!,
      ]);
    } catch (_) {
      return const ReminderBook();
    }
  }

  static bool _same(ProgramReminder a, ProgramReminder b) =>
      a.channelId == b.channelId && a.startMs == b.startMs;

  static bool _expired(ProgramReminder e, int nowMs) => e.startMs < nowMs - 120000;
}

/// Id d'alarme Android, positif, stable d'un lancement à l'autre.
/// Deux profils qui rappellent le MÊME programme ont deux ids :
/// annuler l'un ne coupe pas l'autre.
int reminderNotificationId({
  required String profileId,
  required String channelId,
  required int startMs,
}) {
  // FNV-1a 32 bits. On ne veut pas String.hashCode : il n'est
  // pas garanti identique au prochain démarrage de l'app.
  int h = 0x811c9dc5;
  final String s = '$profileId|$channelId|$startMs';
  for (final int c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h == 0 ? 1 : h;
}
