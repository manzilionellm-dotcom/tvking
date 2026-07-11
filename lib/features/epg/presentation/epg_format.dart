// =========================================================
//  epg_format.dart — Formatage LOCALISÉ des horaires/durées EPG
// =========================================================
//  Les getters du domain (`EpgProgram.timeRangeShort`,
//  `EpgProgram.durationLabel`, `Recording.durationLabel`) formatent
//  en dur à la française ("20h30 – 21h15", "1h05", "45min").
//  Pour que l'app suive la langue ET les conventions horaires du
//  téléphone (12h/24h, AM/PM…), la couche presentation passe par
//  ces helpers :
//    - les HEURES via `MaterialLocalizations.formatTimeOfDay`
//      (Flutter choisit le bon format selon la locale),
//    - les DURÉES et la plage horaire via les clés paramétrées
//      `timeRange`, `durationHours`, `durationHoursMinutes`,
//      `durationMinutes` d'AppLocalizations.
//
//  Les getters domain restent en place comme REPLI documenté
//  (utilisés par features/tv, hors périmètre de cette migration).
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/epg_program.dart';

/// Heure de DÉBUT d'un programme, localisée ("20:30", "8:30 PM"…).
String epgStartTime(BuildContext context, EpgProgram program) {
  return MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(program.startDateTime));
}

/// Plage horaire d'un programme, localisée ("20:30 – 21:15").
/// Remplace `EpgProgram.timeRangeShort` dans la couche presentation.
String epgTimeRange(BuildContext context, EpgProgram program) {
  final MaterialLocalizations material = MaterialLocalizations.of(context);
  final String start =
      material.formatTimeOfDay(TimeOfDay.fromDateTime(program.startDateTime));
  final String end =
      material.formatTimeOfDay(TimeOfDay.fromDateTime(program.stopDateTime));
  return context.l10n.timeRange(start, end);
}

/// Durée compacte localisée ("1h05", "45min", "2h").
/// Remplace `EpgProgram.durationLabel` et `Recording.durationLabel`
/// dans la couche presentation — mêmes règles d'arrondi que le domain.
String durationText(AppLocalizations l10n, Duration duration) {
  final int minutes = duration.inMinutes;
  if (minutes >= 60) {
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return m == 0
        ? l10n.durationHours(h)
        : l10n.durationHoursMinutes(h, m.toString().padLeft(2, '0'));
  }
  return l10n.durationMinutes(minutes);
}
