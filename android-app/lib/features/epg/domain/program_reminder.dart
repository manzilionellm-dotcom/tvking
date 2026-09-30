// =========================================================
//  program_reminder.dart — Rappel d'émission choisi par l'utilisateur
// =========================================================
//  Un rappel n'existe QUE parce que la personne a appuyé sur une émission
//  à venir (guide du lecteur). Rien n'est posé tout seul.
//
//  Deux endroits s'en servent :
//    • l'accueil TV, qui montre les prochains rappels (« dans 25 min ») ;
//    • le système de notifications, qui essaie d'afficher un message
//      5 minutes avant (best-effort : sur une box, le volet Android est
//      parfois discret, l'accueil reste la source fiable).
//
//  Ce fichier est PUR : pas de disque, pas de plugin. Les tests peuvent
//  donc vérifier le tri, le nettoyage et le « trop tard » sans Android.
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Une émission que l'utilisateur veut retrouver.
@immutable
class ProgramReminder {
  const ProgramReminder({
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.startMs,
  });

  /// Identifiant de la chaîne dans la playlist (Channel.id).
  final String channelId;

  /// Nom affiché au moment où le rappel a été posé (la chaîne peut
  /// ensuite être renommée : on garde ce que la personne a lu).
  final String channelName;

  /// Titre de l'émission (« Le Grand Journal »).
  final String title;

  /// Début de l'émission, millisecondes epoch (UTC, comme l'EPG).
  final int startMs;

  /// Clé stable : une même émission ne peut pas avoir deux rappels.
  String get key => '$channelId@$startMs';

  Map<String, Object?> toJson() => <String, Object?>{
        'c': channelId,
        'n': channelName,
        't': title,
        's': startMs,
      };

  static ProgramReminder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final String id = '${raw['c'] ?? ''}'.trim();
    final String title = '${raw['t'] ?? ''}'.trim();
    final Object? start = raw['s'];
    if (id.isEmpty || title.isEmpty || start is! num) return null;
    return ProgramReminder(
      channelId: id,
      channelName: '${raw['n'] ?? ''}'.trim(),
      title: title,
      startMs: start.toInt(),
    );
  }
}

/// Règles de la liste de rappels (tri, oubli du passé, plafond).
abstract final class ProgramReminderLog {
  /// On ne garde pas une infinité de vieux rappels.
  static const int maxKept = 30;

  /// L'émission a commencé depuis plus longtemps que ça → le rappel
  /// ne sert plus, on le retire au prochain nettoyage.
  static const int graceAfterStartMs = 20 * 60 * 1000;

  /// L'accueil ne montre pas ce qui est dans plus de 36 h : trop loin
  /// pour donner envie « maintenant », ça resterait du bruit.
  static const int homeHorizonMs = 36 * 60 * 60 * 1000;

  /// Moins d'une minute avant le début : un rappel n'a plus de sens
  /// (la notification n'aurait pas le temps d'arriver). On refuse,
  /// et on le dit clairement.
  static const int tooLateMs = 60 * 1000;

  /// « Bientôt » pour le focus de l'accueil : dans la prochaine demi-heure
  /// (ou déjà commencé depuis moins de 15 min — on peut encore arriver).
  static const int soonWindowMs = 30 * 60 * 1000;
  static const int soonGraceMs = 15 * 60 * 1000;

  static bool isTooLate(int startMs, int nowMs) => startMs <= nowMs + tooLateMs;

  static bool isSoon(int startMs, int nowMs) {
    final int delta = startMs - nowMs;
    return delta > -soonGraceMs && delta <= soonWindowMs;
  }

  /// Retire le passé, trie du plus proche au plus lointain, borne la taille.
  static List<ProgramReminder> prune(List<ProgramReminder> items, int nowMs) {
    final List<ProgramReminder> kept = <ProgramReminder>[
      for (final ProgramReminder r in items)
        if (r.channelId.isNotEmpty && r.startMs + graceAfterStartMs >= nowMs) r,
    ]..sort((ProgramReminder a, ProgramReminder b) =>
        a.startMs.compareTo(b.startMs));
    if (kept.length <= maxKept) return kept;
    return kept.sublist(0, maxKept);
  }

  /// Ce que l'accueil a le droit d'afficher : proche, et la chaîne existe
  /// encore dans la playlist (sinon OK n'ouvrirait rien).
  static List<ProgramReminder> forHome(
    List<ProgramReminder> items,
    int nowMs, {
    bool Function(String channelId)? channelStillThere,
    int max = 6,
  }) {
    final List<ProgramReminder> out = <ProgramReminder>[];
    for (final ProgramReminder r in prune(items, nowMs)) {
      if (r.startMs > nowMs + homeHorizonMs) continue;
      if (channelStillThere != null && !channelStillThere(r.channelId)) {
        continue;
      }
      out.add(r);
      if (out.length >= max) break;
    }
    return out;
  }

  static bool contains(
    List<ProgramReminder> items,
    String channelId,
    int startMs,
  ) =>
      items.any((ProgramReminder r) =>
          r.channelId == channelId && r.startMs == startMs);

  /// Ajoute ou remplace (même chaîne + même heure = un seul rappel).
  static List<ProgramReminder> upsert(
    List<ProgramReminder> items,
    ProgramReminder next,
    int nowMs,
  ) {
    final List<ProgramReminder> copy = <ProgramReminder>[
      for (final ProgramReminder r in items)
        if (!(r.channelId == next.channelId && r.startMs == next.startMs)) r,
      next,
    ];
    return prune(copy, nowMs);
  }

  static List<ProgramReminder> without(
    List<ProgramReminder> items,
    String channelId,
    int startMs,
  ) =>
      <ProgramReminder>[
        for (final ProgramReminder r in items)
          if (!(r.channelId == channelId && r.startMs == startMs)) r,
      ];

  static String encode(List<ProgramReminder> items) =>
      jsonEncode(items.map((ProgramReminder e) => e.toJson()).toList());

  static List<ProgramReminder> decode(String? raw) {
    if (raw == null || raw.isEmpty) return <ProgramReminder>[];
    try {
      final Object? list = jsonDecode(raw);
      if (list is! List) return <ProgramReminder>[];
      return <ProgramReminder>[
        for (final Object? e in list)
          if (ProgramReminder.fromJson(e) != null) ProgramReminder.fromJson(e)!,
      ];
    } catch (_) {
      // Stockage abîmé : on repart d'une liste vide plutôt que de planter.
      return <ProgramReminder>[];
    }
  }
}
