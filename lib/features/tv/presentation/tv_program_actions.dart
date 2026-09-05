// =========================================================
//  tv_program_actions.dart — « Que faire de cette émission À VENIR ? »
// =========================================================
//  Un seul dialogue, partagé par TOUS les guides TV (programmes d'une
//  chaîne, grille TiviMate, timeline) : appuyer OK sur une émission
//  future propose
//    • ENREGISTRER (ou annuler l'enregistrement déjà programmé) — le
//      magnétoscope : la box capte l'émission à l'heure dite, même en
//      veille (RecordingScheduler + alarmes natives) ;
//    • ME RAPPELER 5 min avant (rappel local existant) ;
//    • Fermer.
//  Chaque action confirme par un petit message. Les erreurs sont dites
//  clairement (créneau déjà pris = une seule connexion, émission finie).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/notifications/notification_service.dart';
import '../../channels/domain/channel.dart';
import '../../epg/domain/epg_program.dart';
import '../../recordings/data/recording_scheduler.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

enum _ProgramAction { record, unrecord, remind, close }

/// Ouvre le dialogue d'actions pour une émission À VENIR et exécute le
/// choix. Renvoie le message de confirmation à afficher (null = rien).
Future<String?> showTvUpcomingProgramActions(
  BuildContext context, {
  required Channel channel,
  required EpgProgram program,
}) async {
  final bool scheduled =
      RecordingScheduler.instance.activeFor(channel.id, program.startTime) !=
          null;
  final _ProgramAction? choice = await showDialog<_ProgramAction>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.86),
    builder: (BuildContext ctx) => _ProgramActionsDialog(
      channel: channel,
      program: program,
      scheduled: scheduled,
    ),
  );
  if (choice == null || !context.mounted) return null;
  switch (choice) {
    case _ProgramAction.record:
      final ScheduleResult r = await RecordingScheduler.instance
          .schedule(channel: channel, program: program);
      if (!context.mounted) return null;
      switch (r) {
        case ScheduleResult.ok:
          return context.l10n.tvRecScheduled;
        case ScheduleResult.conflict:
          return context.l10n.tvRecScheduleConflict;
        case ScheduleResult.tooLate:
          return context.l10n.tvRecScheduleTooLate;
        case ScheduleResult.failed:
          return context.l10n.tvRecScheduleFailed;
      }
    case _ProgramAction.unrecord:
      await RecordingScheduler.instance
          .cancel(_idFor(channel, program));
      if (!context.mounted) return null;
      return context.l10n.tvRecScheduleRemoved;
    case _ProgramAction.remind:
      final bool ok = await NotificationService.instance.scheduleProgramReminder(
        channelId: channel.id,
        channelName: channel.cleanName,
        title: program.title,
        startMs: program.startTime,
      );
      if (!context.mounted) return null;
      return ok ? context.l10n.tvReminderSet : context.l10n.tvReminderFailed;
    case _ProgramAction.close:
      return null;
  }
}

String _idFor(Channel channel, EpgProgram program) =>
    RecordingScheduler.instance
        .activeFor(channel.id, program.startTime)
        ?.id ??
    '';

class _ProgramActionsDialog extends StatelessWidget {
  const _ProgramActionsDialog({
    required this.channel,
    required this.program,
    required this.scheduled,
  });

  final Channel channel;
  final EpgProgram program;
  final bool scheduled;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: TvTokens.card,
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvTokens.line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(program.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TvTokens.display(22, color: TvTokens.text)),
              const SizedBox(height: 6),
              Text(
                '${channel.cleanName}  ·  ${program.timeRangeShort}',
                textAlign: TextAlign.center,
                style: TvTokens.ui(15, color: TvTokens.mutedDim),
              ),
              const SizedBox(height: 22),
              _ActionRow(
                icon: scheduled
                    ? Icons.stop_circle_outlined
                    : Icons.fiber_manual_record_rounded,
                label: scheduled
                    ? context.l10n.tvRecScheduleCancel
                    : context.l10n.tvRecScheduleAction,
                accent: TvTokens.live,
                autofocus: true,
                onSelect: () => Navigator.of(context).pop(
                    scheduled ? _ProgramAction.unrecord : _ProgramAction.record),
              ),
              const SizedBox(height: 10),
              _ActionRow(
                icon: Icons.notifications_none_rounded,
                label: context.l10n.tvRecChoiceReminder,
                accent: TvTokens.gold,
                onSelect: () => Navigator.of(context).pop(_ProgramAction.remind),
              ),
              const SizedBox(height: 10),
              _ActionRow(
                icon: Icons.close_rounded,
                label: context.l10n.buttonCancel,
                accent: TvTokens.muted,
                onSelect: () => Navigator.of(context).pop(_ProgramAction.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onSelect,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.onGold : TvTokens.text;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: focused ? TvTokens.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(TvTokens.rButton),
            border: Border.all(color: focused ? TvTokens.gold : TvTokens.line),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, color: focused ? fg : accent, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(16, weight: FontWeight.w700, color: fg)),
              ),
            ],
          ),
        );
      },
    );
  }
}
