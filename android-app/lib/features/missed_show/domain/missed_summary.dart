// =========================================================
//  missed_summary.dart — Ce que le guide dit qu'on a raté
// =========================================================
//  Uniquement les heures du programme déjà connu. Pas de
//  service extérieur. Le retour au début n'est proposé que
//  si l'appelant a une adresse de catch-up DÉCLARÉE par la
//  chaîne. On ne l'invente pas : un direct rembobiné au
//  hasard reste souvent sur le logo.
// =========================================================

import '../../epg/domain/epg_program.dart';

class MissedSummary {
  const MissedSummary({
    required this.title,
    required this.missedMinutes,
    this.description,
    this.rewindUrl,
  });

  final String title;
  final int missedMinutes;
  final String? description;

  /// Adresse de replay, ou null si le guide n'a pas la vidéo.
  final String? rewindUrl;

  bool get canRewind => rewindUrl != null && rewindUrl!.isNotEmpty;
}

/// null = à l'heure, programme inconnu, ou déjà fini.
MissedSummary? missedFromGuide({
  required EpgProgram? program,
  required DateTime now,
  required bool catchupDeclared,
  String? rewindUrl,
  int minMinutes = 3,
}) {
  if (program == null) return null;
  if (program.title.trim().isEmpty) return null;
  final int nowMs = now.millisecondsSinceEpoch;
  if (nowMs < program.startTime || nowMs >= program.stopTime) return null;
  final int missed = (nowMs - program.startTime) ~/ 60000;
  if (missed < minMinutes) return null;
  String? description = program.description?.trim();
  if (description != null && description.isEmpty) description = null;
  if (description != null && description.length > 180) {
    description = '${description.substring(0, 177)}…';
  }
  final String? url =
      catchupDeclared && rewindUrl != null && rewindUrl.isNotEmpty ? rewindUrl : null;
  return MissedSummary(
    title: program.title.trim(),
    missedMinutes: missed,
    description: description,
    rewindUrl: url,
  );
}
