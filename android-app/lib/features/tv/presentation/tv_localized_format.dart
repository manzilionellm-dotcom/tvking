// Formats d'affichage uniquement : les dates, durées et octets stockés
// restent identiques. Les nombres et unités suivent la langue de la TV.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/l10n_extension.dart';

String tvNumber(BuildContext context, num value, {int decimals = 0}) =>
    (NumberFormat.decimalPattern(Localizations.localeOf(context).toString())
          ..minimumFractionDigits = decimals
          ..maximumFractionDigits = decimals)
        .format(value);

String tvBytes(BuildContext context, int bytes) {
  if (bytes < 1024) return context.l10n.tvSizeBytes(tvNumber(context, bytes));
  if (bytes < 1024 * 1024)
    return context.l10n.tvSizeKb(tvNumber(context, bytes / 1024, decimals: 1));
  if (bytes < 1024 * 1024 * 1024)
    return context.l10n.tvSizeMb(
      tvNumber(context, bytes / (1024 * 1024), decimals: 1),
    );
  return context.l10n.tvSizeGb(
    tvNumber(context, bytes / (1024 * 1024 * 1024), decimals: 2),
  );
}

String tvDuration(BuildContext context, Duration duration) {
  final int minutes = duration.inMinutes;
  return minutes < 60
      ? context.l10n.tvCinemaMinutes(tvNumber(context, minutes))
      : context.l10n.tvDurationHm(
          tvNumber(context, minutes ~/ 60),
          tvNumber(context, minutes % 60),
        );
}

String tvDateTime(BuildContext context, DateTime date) =>
    '${DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date)} · ${tvTime(context, date)}';

String tvTime(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
