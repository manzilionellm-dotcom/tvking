// =========================================================
//  tv_channel_programs_screen.dart — Guide de chaîne 10-foot (TV)
// =========================================================
//  Version NATIVE TV de l'écran « programmes du jour » d'une chaîne.
//  Affiche, pour la chaîne en cours de lecture, la liste des émissions
//  d'aujourd'hui (passées / EN DIRECT / à venir), navigable à la
//  télécommande (D-pad), avec l'émission en cours mise en avant.
//
//  POURQUOI un écran DÉDIÉ TV (et pas le ChannelProgramsScreen mobile) :
//  l'écran mobile importe le lecteur mobile (play_channel → media_kit/libmpv).
//  Comme la TV lit EXCLUSIVEMENT via ExoPlayer (native_video_player), faire
//  passer la TV par l'écran mobile « tirait » media_kit dans l'APK TV (~30 Mo
//  inutiles) ET empêchait de l'alléger. Cet écran n'importe AUCUN lecteur :
//  il est purement informatif (le live continue derrière). On casse ainsi la
//  dernière dépendance TV → media_kit. Voir build-tv.yml (allègement).
// =========================================================
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/notifications/notification_service.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/catchup_url_builder.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_player_screen.dart';

class TvChannelProgramsScreen extends StatefulWidget {
  const TvChannelProgramsScreen({required this.channel, super.key});

  final Channel channel;

  @override
  State<TvChannelProgramsScreen> createState() =>
      _TvChannelProgramsScreenState();
}

class _TvChannelProgramsScreenState extends State<TvChannelProgramsScreen> {
  late Future<List<EpgProgram>> _future;

  // Heures de début (startTime) des émissions pour lesquelles un RAPPEL est posé
  // pendant cette session → permet d'afficher l'icône alarme « pleine » et de
  // basculer (poser/retirer). L'id de notif est dérivé de (chaîne, startTime),
  // donc l'opération est idempotente même entre deux ouvertures.
  final Set<int> _reminders = <int>{};

  @override
  void initState() {
    super.initState();
    _future = EpgRepository.instance.todayPrograms(widget.channel.id);
  }

  /// Pose ou retire un rappel (alarme 5 min avant) sur une émission à venir.
  Future<void> _toggleReminder(EpgProgram p) async {
    final bool alreadySet = _reminders.contains(p.startTime);
    if (alreadySet) {
      await NotificationService.instance
          .cancelProgramReminder(widget.channel.id, p.startTime);
      if (!mounted) return;
      setState(() => _reminders.remove(p.startTime));
      _toast(context.l10n.tvReminderRemoved);
      return;
    }
    final bool ok = await NotificationService.instance.scheduleProgramReminder(
      channelId: widget.channel.id,
      channelName: widget.channel.cleanName,
      title: p.title,
      startMs: p.startTime,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _reminders.add(p.startTime));
      _toast(context.l10n.tvReminderSet);
    } else {
      // Échec : créneau trop proche/passé, ou rappels coupés dans les réglages.
      _toast(context.l10n.tvReminderFailed);
    }
  }

  /// « REVOIR » (catch-up) : rejoue une émission PASSÉE depuis l'ARCHIVE DU
  /// FOURNISSEUR (jamais un enregistrement local). On fabrique une chaîne
  /// synthétique — copie de la chaîne live mais avec l'URL d'archive et
  /// isLive=false — et on la passe AU LECTEUR EXISTANT (ExoPlayer). Aucun
  /// changement de lecteur, aucun buffer local → qualité/stabilité intactes.
  void _replay(EpgProgram p) {
    final String? url = CatchupUrlBuilder.build(channel: widget.channel, program: p);
    if (url == null) {
      _toast(context.l10n.tvReplayUnavailable);
      return;
    }
    final Channel c = widget.channel;
    final Channel replayChannel = Channel(
      id: '${c.id}#catchup${p.startTime}',
      name: '${c.cleanName} · ${p.title}',
      category: c.category,
      streamUrl: url,
      isLive: false,
      playlistId: c.playlistId,
      logoUrl: c.logoUrl,
      currentProgram: p.title,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(
          channels: <Channel>[replayChannel],
          startIndex: 0,
        ),
      ),
    );
  }

  /// Une émission passée est-elle « revoyable » (archive dispo) ?
  bool _canReplay(EpgProgram p) =>
      CatchupUrlBuilder.build(channel: widget.channel, program: p) != null;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TvTokens.card,
        content: Text(msg,
            style: TextStyle(color: TvTokens.text, fontSize: TvDimens.body)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvTokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 36, 48, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ----- En-tête : nom de la chaîne + « Programmes du jour » -----
              Text(
                widget.channel.cleanName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.display(30, color: TvTokens.text),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.programsToday,
                style: TvTokens.ui(15, color: TvTokens.mutedDim),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: FutureBuilder<List<EpgProgram>>(
                  future: _future,
                  builder: (BuildContext context,
                      AsyncSnapshot<List<EpgProgram>> snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final List<EpgProgram> programs =
                        snap.data ?? const <EpgProgram>[];
                    if (programs.isEmpty) return _empty(context);
                    // On donne le focus initial à l'émission EN COURS (ou, à
                    // défaut, à la première) pour ne pas démarrer en haut d'une
                    // longue liste passée.
                    final DateTime now = DateTime.now();
                    int liveIndex = programs
                        .indexWhere((EpgProgram p) => p.isLiveAt(now));
                    if (liveIndex < 0) liveIndex = 0;
                    return ListView.separated(
                      // Mémoire bornée : on ne garde pas les lignes hors écran.
                      addAutomaticKeepAlives: false,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: programs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int i) => _ProgramRow(
                        program: programs[i],
                        autofocus: i == liveIndex,
                        hasReminder: _reminders.contains(programs[i].startTime),
                        canReplay: _canReplay(programs[i]),
                        onToggleReminder: () => _toggleReminder(programs[i]),
                        onReplay: () => _replay(programs[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.event_busy_rounded, size: 48, color: TvTokens.mutedDim),
          const SizedBox(height: 14),
          Text(context.l10n.programsNoneToday,
              style: TvTokens.ui(18, color: TvTokens.text)),
          const SizedBox(height: 6),
          Text(context.l10n.programsNoneHelp,
              textAlign: TextAlign.center,
              style: TvTokens.ui(14, color: TvTokens.mutedDim)),
        ],
      ),
    );
  }
}

enum _ProgState { past, live, future }

class _ProgramRow extends StatelessWidget {
  const _ProgramRow({
    required this.program,
    this.autofocus = false,
    this.hasReminder = false,
    this.canReplay = false,
    this.onToggleReminder,
    this.onReplay,
  });

  final EpgProgram program;
  final bool autofocus;
  final bool hasReminder;

  /// L'émission passée dispose-t-elle d'une archive (catch-up) rejouable ?
  final bool canReplay;
  final VoidCallback? onToggleReminder;
  final VoidCallback? onReplay;

  _ProgState _stateFor(DateTime now) {
    if (program.isLiveAt(now)) return _ProgState.live;
    if (program.stopTime <= now.millisecondsSinceEpoch) return _ProgState.past;
    return _ProgState.future;
  }

  @override
  Widget build(BuildContext context) {
    final _ProgState state = _stateFor(DateTime.now());
    final bool isLive = state == _ProgState.live;
    final bool isFuture = state == _ProgState.future;
    // « REVOIR » : possible sur une émission PASSÉE, ET sur l'émission EN COURS
    // (revoir depuis le début — l'exemple du match commencé il y a 1 h). Jamais
    // sur une émission à venir (rien à rejouer).
    final bool replayable = canReplay && !isFuture;
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      // À VENIR → OK pose/retire un RAPPEL (alarme 5 min avant).
      // PASSÉ / EN DIRECT avec archive → OK lance le REPLAY depuis le début.
      // Sinon → rien (le direct continue derrière) ; Retour revient au lecteur.
      onSelect: isFuture
          ? onToggleReminder
          : (replayable ? onReplay : () {}),
      builder: (BuildContext context, bool focused) {
        final Color border = focused
            ? TvTokens.gold
            : (isLive ? TvTokens.live : TvTokens.lineSoft);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: focused
                ? TvTokens.sel
                : (isLive
                    ? TvTokens.live.withValues(alpha: 0.12)
                    : TvTokens.card),
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(
                color: border, width: focused ? TvDimens.focusOutline : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _StateChip(state: state),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      program.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TvDimens.title,
                        fontWeight: FontWeight.w700,
                        color: state == _ProgState.future
                            ? TvTokens.muted
                            : TvTokens.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${program.timeRangeShort}  ·  ${program.durationLabel}',
                      style: TextStyle(
                          fontSize: TvDimens.label, color: TvTokens.mutedDim),
                    ),
                    if (program.description != null &&
                        program.description!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        program.description!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: TvDimens.label,
                            height: 1.35,
                            color: TvTokens.muted),
                      ),
                    ],
                  ],
                ),
              ),
              // À VENIR : indicateur de RAPPEL. Cloche pleine (or) = rappel posé ;
              // cloche vide = OK pour poser un rappel.
              if (isFuture) ...<Widget>[
                const SizedBox(width: 12),
                Icon(
                  hasReminder
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  size: 26,
                  color: hasReminder ? TvTokens.gold : TvTokens.mutedDim,
                ),
              ]
              // PASSÉ / EN DIRECT avec archive : pastille « ⟲ Revoir » →
              // OK rejoue l'émission depuis le début (catch-up fournisseur).
              else if (replayable) ...<Widget>[
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: focused ? TvTokens.gold : TvTokens.badgeBg,
                    borderRadius: BorderRadius.circular(TvTokens.rSmall),
                    border: Border.all(color: TvTokens.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.replay_rounded,
                          size: 18,
                          color: focused
                              ? const Color(0xFF1A1206)
                              : TvTokens.goldBright),
                      const SizedBox(width: 6),
                      Text(context.l10n.tvReplay,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: focused
                                  ? const Color(0xFF1A1206)
                                  : TvTokens.goldBright)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Pastille d'état (TERMINÉ / EN DIRECT / À VENIR) à gauche de chaque ligne.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});
  final _ProgState state;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String label;
    switch (state) {
      case _ProgState.live:
        bg = TvTokens.live;
        fg = Colors.white;
        icon = Icons.fiber_manual_record_rounded;
        label = context.l10n.tvProgramLive;
      case _ProgState.past:
        bg = TvTokens.sel;
        fg = TvTokens.mutedDim;
        icon = Icons.history_rounded;
        label = context.l10n.tvProgramPast;
      case _ProgState.future:
        bg = TvTokens.sel;
        fg = TvTokens.muted;
        icon = Icons.schedule_rounded;
        label = context.l10n.tvProgramFuture;
    }
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TvTokens.rSmall),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: fg, size: 16),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}
