// =========================================================
//  program_actions_sheet.dart — Émission à venir (MOBILE)
// =========================================================
//  Pendant mobile du dialogue TV (tv_program_actions.dart) : une feuille
//  du bas avec « Enregistrer / Annuler l'enregistrement » et « Me
//  rappeler 5 min avant ». Même planificateur, mêmes messages.
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/domain/channel.dart';
import '../../recordings/data/recording_scheduler.dart';
import '../domain/epg_program.dart';
import 'epg_format.dart';

enum _Choice { record, unrecord, remind }

/// Feuille d'actions pour une émission À VENIR. Affiche elle-même le
/// message de confirmation (SnackBar).
Future<void> showProgramActionsSheet(
  BuildContext context, {
  required Channel channel,
  required EpgProgram program,
}) async {
  final bool scheduled =
      RecordingScheduler.instance.activeFor(channel.id, program.startTime) !=
          null;
  final _Choice? choice = await showModalBottomSheet<_Choice>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (BuildContext ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 10),
          ListTile(
            title: Text(program.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.headlineMedium),
            subtitle: Text(
              '${channel.cleanName} · ${epgTimeRange(ctx, program)}',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              scheduled
                  ? Icons.stop_circle_outlined
                  : Icons.fiber_manual_record_rounded,
              color: AppColors.live,
            ),
            title: Text(scheduled
                ? ctx.l10n.tvRecScheduleCancel
                : ctx.l10n.tvRecScheduleAction),
            onTap: () => Navigator.of(ctx)
                .pop(scheduled ? _Choice.unrecord : _Choice.record),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none_rounded),
            title: Text(ctx.l10n.tvRecChoiceReminder),
            onTap: () => Navigator.of(ctx).pop(_Choice.remind),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  String message;
  switch (choice) {
    case _Choice.record:
      final ScheduleResult r = await RecordingScheduler.instance
          .schedule(channel: channel, program: program);
      if (!context.mounted) return;
      message = switch (r) {
        ScheduleResult.ok => context.l10n.tvRecScheduled,
        ScheduleResult.conflict => context.l10n.tvRecScheduleConflict,
        ScheduleResult.tooLate => context.l10n.tvRecScheduleTooLate,
        ScheduleResult.failed => context.l10n.tvRecScheduleFailed,
      };
    case _Choice.unrecord:
      final String? id = RecordingScheduler.instance
          .activeFor(channel.id, program.startTime)
          ?.id;
      if (id != null) await RecordingScheduler.instance.cancel(id);
      if (!context.mounted) return;
      message = context.l10n.tvRecScheduleRemoved;
    case _Choice.remind:
      final bool ok = await NotificationService.instance.scheduleProgramReminder(
        channelId: channel.id,
        channelName: channel.cleanName,
        title: program.title,
        startMs: program.startTime,
      );
      if (!context.mounted) return;
      message = ok
          ? context.l10n.guideReminderSet(
              program.title, epgStartTime(context, program))
          : context.l10n.tvReminderFailed;
  }
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppColors.surfaceHigh,
      behavior: SnackBarBehavior.floating,
      content: Text(message, style: AppTextStyles.bodyMedium),
    ),
  );
}
