// =========================================================
//  channel_programs_screen.dart — Replay d'une chaîne (24h)
// =========================================================
//  Liste tous les programmes d'aujourd'hui pour une chaîne
//  donnée. Pour chaque programme :
//    - Passé   → bouton "Replay" (catch-up)
//    - En cours → bouton "Lecture" (live)
//    - Futur   → poser ou retirer un RAPPEL (accueil + notification)
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/presentation/cast_button.dart';
import '../../channels/domain/channel.dart';
import '../../channels/presentation/widgets/channel_logo.dart';
import '../../player/presentation/play_channel.dart';
import '../data/catchup_url_builder.dart';
import '../data/epg_repository.dart';
import '../data/program_reminder_repository.dart';
import '../domain/epg_program.dart';
import '../domain/program_reminder.dart';

class ChannelProgramsScreen extends StatefulWidget {
  const ChannelProgramsScreen({required this.channel, super.key});

  final Channel channel;

  @override
  State<ChannelProgramsScreen> createState() => _ChannelProgramsScreenState();
}

class _ChannelProgramsScreenState extends State<ChannelProgramsScreen> {
  late Future<List<EpgProgram>> _future;

  @override
  void initState() {
    super.initState();
    _future = EpgRepository.instance.todayPrograms(widget.channel.id);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = EpgRepository.instance.todayPrograms(widget.channel.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.channel.cleanName,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 17),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              context.l10n.programsToday,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        actions: const <Widget>[
          CastButton(),
          SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<List<EpgProgram>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<List<EpgProgram>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<EpgProgram> programs = snap.data ?? <EpgProgram>[];
          if (programs.isEmpty) {
            return _empty();
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.accent,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              itemCount: programs.length,
              separatorBuilder: (BuildContext _, int __) =>
                  const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                return _ProgramTile(
                  channel: widget.channel,
                  program: programs[index],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ChannelLogo(channel: widget.channel),
            const SizedBox(height: 14),
            Text(
              context.l10n.programsNoneToday,
              style: AppTextStyles.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.programsNoneHelp,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

enum _ProgramState { past, live, future }

class _ProgramTile extends StatefulWidget {
  const _ProgramTile({required this.channel, required this.program});

  final Channel channel;
  final EpgProgram program;

  @override
  State<_ProgramTile> createState() => _ProgramTileState();
}

class _ProgramTileState extends State<_ProgramTile> {
  bool _reminded = false;

  @override
  void initState() {
    super.initState();
    _refreshReminded();
  }

  Future<void> _refreshReminded() async {
    await ProgramReminderRepository.instance.load();
    if (!mounted) return;
    setState(() {
      _reminded = ProgramReminderRepository.instance
          .contains(widget.channel.id, widget.program.startTime);
    });
  }

  _ProgramState _stateFor(DateTime now) {
    final int nowMs = now.millisecondsSinceEpoch;
    if (widget.program.isLiveAt(now)) return _ProgramState.live;
    if (widget.program.stopTime <= nowMs) return _ProgramState.past;
    return _ProgramState.future;
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final _ProgramState state = _stateFor(now);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onTap(context, state),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: state == _ProgramState.live
                ? AppColors.accentSurface
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: state == _ProgramState.live
                  ? AppColors.accent
                  : AppColors.border,
              width: state == _ProgramState.live ? 1.2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              _StateBadge(state: state),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.program.title,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: state == _ProgramState.future
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.schedule_rounded,
                          size: 11,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.program.timeRangeShort,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· ${widget.program.durationLabel}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (widget.program.description != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        widget.program.description!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _ActionIcon(state: state, reminded: _reminded),
            ],
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, _ProgramState state) {
    switch (state) {
      case _ProgramState.live:
        playChannel(context, widget.channel);
      case _ProgramState.past:
        final String? url = CatchupUrlBuilder.build(
          channel: widget.channel,
          program: widget.program,
        );
        if (url != null) {
          playChannel(context, widget.channel,
              overrideUrl: url, overrideTitle: widget.program.title);
        } else {
          _snack(context, context.l10n.programsCatchupUnavailable);
        }
      case _ProgramState.future:
        _toggleReminder();
    }
  }

  /// Second appui = on retire. On le dit toujours clairement :
  /// notification posée, seulement l'accueil, ou trop tard.
  ///
  /// On lit les textes APRÈS chaque `await`, et seulement si l'écran
  /// est encore là (`mounted`) : le contexte du State, pas celui du tap.
  Future<void> _toggleReminder() async {
    final ProgramReminderRepository repo = ProgramReminderRepository.instance;
    final String channelId = widget.channel.id;
    final String channelName = widget.channel.cleanName;
    final String title = widget.program.title;
    final int startMs = widget.program.startTime;
    await repo.load();
    if (!mounted) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (repo.contains(channelId, startMs)) {
      await repo.remove(channelId, startMs);
      await NotificationService.instance.cancelProgramReminder(channelId, startMs);
      if (!mounted) return;
      setState(() => _reminded = false);
      _snack(context, context.l10n.tvReminderCleared);
      return;
    }
    if (ProgramReminderLog.isTooLate(startMs, now)) {
      _snack(context, context.l10n.tvReminderTooLate);
      return;
    }
    await repo.add(ProgramReminder(
      channelId: channelId,
      channelName: channelName,
      title: title,
      startMs: startMs,
    ));
    final bool notified = await NotificationService.instance.scheduleProgramReminder(
      channelId: channelId,
      channelName: channelName,
      title: title,
      startMs: startMs,
    );
    if (!mounted) return;
    setState(() => _reminded = true);
    _snack(
      context,
      notified ? context.l10n.tvReminderSet(title) : context.l10n.tvReminderSavedOnly(title),
    );
  }

  void _snack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceHigh,
        behavior: SnackBarBehavior.floating,
        content: Text(message, style: AppTextStyles.bodyMedium),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});
  final _ProgramState state;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String text;
    late IconData icon;
    switch (state) {
      case _ProgramState.live:
        bg = AppColors.live;
        fg = Colors.white;
        text = context.l10n.badgeLive;
        icon = Icons.fiber_manual_record_rounded;
      case _ProgramState.past:
        bg = AppColors.accent;
        fg = Colors.black;
        text = context.l10n.badgeReplay;
        icon = Icons.replay_rounded;
      case _ProgramState.future:
        bg = AppColors.surfaceHigh;
        fg = AppColors.textSecondary;
        text = context.l10n.badgeSoon;
        icon = Icons.schedule_rounded;
    }
    return Container(
      width: 70,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: fg, size: 14),
          const SizedBox(height: 2),
          Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(
              color: fg,
              fontSize: 9,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.state, required this.reminded});
  final _ProgramState state;
  final bool reminded;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _ProgramState.live:
        return Icon(Icons.play_circle_filled_rounded,
            color: AppColors.accent, size: 28);
      case _ProgramState.past:
        return Icon(Icons.replay_circle_filled_rounded,
            color: AppColors.accent, size: 28);
      case _ProgramState.future:
        // Cloche pleine = rappel déjà posé. Un second appui le retire.
        return Icon(
          reminded ? Icons.alarm_on_rounded : Icons.alarm_add_rounded,
          color: reminded ? AppColors.accent : AppColors.textMuted,
          size: 22,
        );
    }
  }
}
