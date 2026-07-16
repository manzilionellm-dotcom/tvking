// =========================================================
//  tv_guide_screen.dart — Guide TV (grille EPG)
// =========================================================
//  Layout style TiviMate :
//    - Colonne gauche fixe : logo + nom de chaîne (110 px)
//    - À droite : timeline horizontale 24h, scrollable
//      synchronisée entre toutes les lignes
//    - Ligne rouge verticale = heure courante
//    - Chaque programme = card cliquable (tap → joue la chaîne
//      si en cours, info si futur)
//
//  Perf 20k chaînes : on n'affiche que les chaînes d'une
//  PAGE de 50 à la fois (paginated vertical list).
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/presentation/cast_button.dart';
import '../../channels/domain/channel.dart';
import '../../channels/presentation/widgets/channel_logo.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/playlist_repository.dart';
import '../data/catchup_url_builder.dart';
import '../data/epg_repository.dart';
import '../domain/epg_program.dart';
import 'epg_format.dart';

class TvGuideScreen extends StatefulWidget {
  const TvGuideScreen({super.key});

  @override
  State<TvGuideScreen> createState() => _TvGuideScreenState();
}

class _TvGuideScreenState extends State<TvGuideScreen> {
  /// Largeur d'une heure dans la timeline (en pixels logiques).
  static const double _kHourWidth = 220;

  /// Hauteur de chaque ligne (chaîne).
  static const double _kRowHeight = 72;

  /// Largeur du panneau "chaîne" à gauche.
  static const double _kChannelColumnWidth = 130;

  late DateTime _timelineStart; // début de la timeline (heure pile)
  late DateTime _timelineEnd; // 24 h plus tard

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  List<Channel> _channels = const <Channel>[];
  StreamSubscription<List<Channel>>? _channelsSub;
  StreamSubscription<void>? _epgSub;

  // Tick pour la ligne rouge "now"
  Timer? _nowTicker;
  DateTime _now = DateTime.now();

  /// Incrémentée à chaque événement EPG (sync terminée…). Les lignes
  /// s'en servent pour savoir quand relancer leur requête mémorisée.
  int _epgVersion = 0;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _timelineStart = DateTime(now.year, now.month, now.day, now.hour);
    _timelineEnd = _timelineStart.add(const Duration(hours: 24));

    _channels = PlaylistRepository.instance.currentChannels;
    if (_channels.isEmpty) {
      PlaylistRepository.instance.getAllChannels().then((List<Channel> ch) {
        if (mounted) setState(() => _channels = ch);
      });
    }
    _channelsSub = PlaylistRepository.instance.channelsStream
        .listen((List<Channel> ch) {
      if (mounted) setState(() => _channels = ch);
    });
    _epgSub = EpgRepository.instance.changes.listen((_) {
      // FLUIDITÉ : la version EPG sert de CLÉ aux futures mémorisés des
      // lignes (_ProgramsRow). Seul un vrai changement de données EPG
      // invalide les requêtes — pas le tic d'horloge de 30 s.
      if (mounted) setState(() => _epgVersion++);
    });

    _nowTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    // Centre la timeline sur l'heure actuelle après le first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToNow();
    });
  }

  @override
  void dispose() {
    _channelsSub?.cancel();
    _epgSub?.cancel();
    _nowTicker?.cancel();
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _scrollToNow() {
    if (!_horizontalController.hasClients) return;
    final double offset = _xForTime(_now);
    final double target =
        (offset - 80).clamp(0, _horizontalController.position.maxScrollExtent);
    _horizontalController.jumpTo(target);
  }

  /// Convertit un DateTime en X dans la timeline.
  double _xForTime(DateTime t) {
    final int ms = t.millisecondsSinceEpoch -
        _timelineStart.millisecondsSinceEpoch;
    final double hours = ms / (1000 * 60 * 60);
    return hours * _kHourWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.guideTitle),
        actions: <Widget>[
          const CastButton(),
          IconButton(
            icon: const Icon(Icons.my_location_rounded),
            tooltip: context.l10n.guideGoToNow,
            onPressed: _scrollToNow,
          ),
        ],
      ),
      body: _channels.isEmpty
          ? _empty(context.l10n.guideNoChannel)
          : Column(
              children: <Widget>[
                _TimeRuler(
                  timelineStart: _timelineStart,
                  hourWidth: _kHourWidth,
                  channelColWidth: _kChannelColumnWidth,
                  horizontalController: _horizontalController,
                  now: _now,
                ),
                Expanded(
                  child: _GuideBody(
                    channels: _channels,
                    timelineStart: _timelineStart,
                    timelineEnd: _timelineEnd,
                    hourWidth: _kHourWidth,
                    rowHeight: _kRowHeight,
                    channelColWidth: _kChannelColumnWidth,
                    verticalController: _verticalController,
                    horizontalController: _horizontalController,
                    now: _now,
                    epgVersion: _epgVersion,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _empty(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.event_note_rounded,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(msg, style: AppTextStyles.bodyLarge),
            const SizedBox(height: 6),
            Text(
              context.l10n.guideEmptyHint,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  En-tête : règle horaire avec marqueur "now"
// ============================================================

class _TimeRuler extends StatelessWidget {
  const _TimeRuler({
    required this.timelineStart,
    required this.hourWidth,
    required this.channelColWidth,
    required this.horizontalController,
    required this.now,
  });

  final DateTime timelineStart;
  final double hourWidth;
  final double channelColWidth;
  final ScrollController horizontalController;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: channelColWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(Icons.access_time, size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  context.l10n.guideSchedule,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.accent,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: AppColors.border,
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: horizontalController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: hourWidth * 24,
                height: 36,
                child: CustomPaint(
                  painter: _RulerPainter(
                    // Les libellés d'heures sont préparés ICI (le painter
                    // n'a pas de BuildContext) : la marque « 20h » suit
                    // ainsi la langue de l'app via guideHourMark.
                    hourLabels: List<String>.generate(
                      25,
                      (int h) => context.l10n.guideHourMark(
                        timelineStart
                            .add(Duration(hours: h))
                            .hour
                            .toString()
                            .padLeft(2, '0'),
                      ),
                    ),
                    hourWidth: hourWidth,
                    color: AppColors.textMuted,
                    accent: AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.hourLabels,
    required this.hourWidth,
    required this.color,
    required this.accent,
  });

  /// Libellés LOCALISÉS des 25 graduations horaires, fournis par le
  /// widget parent (un CustomPainter n'a pas de BuildContext).
  final List<String> hourLabels;
  final double hourWidth;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final TextStyle style = TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    );
    for (int h = 0; h < hourLabels.length; h++) {
      final double x = h * hourWidth;
      // Trait de graduation
      final Paint tick = Paint()..color = color.withValues(alpha: 0.3);
      canvas.drawLine(
        Offset(x, size.height - 8),
        Offset(x, size.height),
        tick,
      );
      // Label
      final TextPainter tp = TextPainter(
        text: TextSpan(text: hourLabels[h], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 4, 6));
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      !listEquals(oldDelegate.hourLabels, hourLabels);
}

// ============================================================
//  Corps de la grille
// ============================================================

class _GuideBody extends StatelessWidget {
  const _GuideBody({
    required this.channels,
    required this.timelineStart,
    required this.timelineEnd,
    required this.hourWidth,
    required this.rowHeight,
    required this.channelColWidth,
    required this.verticalController,
    required this.horizontalController,
    required this.now,
    required this.epgVersion,
  });

  final List<Channel> channels;
  final DateTime timelineStart;
  final DateTime timelineEnd;
  final double hourWidth;
  final double rowHeight;
  final double channelColWidth;
  final ScrollController verticalController;
  final ScrollController horizontalController;
  final DateTime now;

  /// Version des données EPG (incrémentée par l'écran à chaque sync) :
  /// clé d'invalidation des requêtes mémorisées des lignes.
  final int epgVersion;

  double _xForTime(DateTime t) {
    final int ms =
        t.millisecondsSinceEpoch - timelineStart.millisecondsSinceEpoch;
    return (ms / (1000 * 60 * 60)) * hourWidth;
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: verticalController,
      itemCount: channels.length,
      itemExtent: rowHeight,
      physics: const BouncingScrollPhysics(),
      cacheExtent: 800,
      itemBuilder: (BuildContext context, int index) {
        final Channel ch = channels[index];
        return RepaintBoundary(
          child: SizedBox(
            height: rowHeight,
            child: Row(
              children: <Widget>[
                // Colonne fixe gauche : la chaîne
                _ChannelCell(
                  channel: ch,
                  width: channelColWidth,
                  height: rowHeight,
                  onTap: () =>
                      playChannel(context, ch, zapPlaylist: channels),
                ),
                Container(
                  width: 1,
                  color: AppColors.border,
                ),
                // Ligne programmes (scroll horizontal synchronisé)
                Expanded(
                  child: SingleChildScrollView(
                    controller: _SyncedScrollController(
                      horizontalController,
                    ),
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: _ProgramsRow(
                      channelId: ch.id,
                      timelineStart: timelineStart,
                      timelineEnd: timelineEnd,
                      hourWidth: hourWidth,
                      rowHeight: rowHeight,
                      now: now,
                      epgVersion: epgVersion,
                      onProgramTap: (EpgProgram p) {
                        final int nowMs = now.millisecondsSinceEpoch;
                        if (p.isLiveAt(now)) {
                          // En cours → live direct
                          playChannel(context, ch, zapPlaylist: channels);
                        } else if (p.stopTime <= nowMs) {
                          // Passé → on tente le catch-up
                          final String? catchupUrl =
                              CatchupUrlBuilder.build(
                            channel: ch,
                            program: p,
                          );
                          if (catchupUrl != null) {
                            playChannel(
                              context,
                              ch,
                              overrideUrl: catchupUrl,
                              overrideTitle: p.title,
                            );
                          } else {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.surfaceHigh,
                                behavior: SnackBarBehavior.floating,
                                content: Text(
                                  context.l10n
                                      .guideCatchupUnavailable(ch.cleanName),
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ),
                            );
                          }
                        } else {
                          // Futur → on programme un RAPPEL (~5 min avant le
                          // début) et on confirme à l'utilisateur.
                          // Heure de début LOCALISÉE (12h/24h selon la
                          // locale) via le helper presentation.
                          final String start = epgStartTime(context, p);
                          NotificationService.instance
                              .scheduleProgramReminder(
                            channelId: p.channelId,
                            channelName: ch.cleanName,
                            title: p.title,
                            startMs: p.startTime,
                          )
                              .then((bool ok) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.surfaceHigh,
                                behavior: SnackBarBehavior.floating,
                                content: Text(
                                  ok
                                      ? context.l10n
                                          .guideReminderSet(p.title, start)
                                      : context.l10n.guideReminderStartsAt(
                                          p.title, start),
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ),
                            );
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChannelCell extends StatelessWidget {
  const _ChannelCell({
    required this.channel,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final Channel channel;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            child: Row(
              children: <Widget>[
                ChannelLogo(
                  channel: channel,
                  size: ChannelLogoSize.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    channel.cleanName,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// FLUIDITÉ — StatefulWidget avec FUTURE MÉMORISÉ : avant, chaque
/// rebuild (tic « now » 30 s, événement EPG, scroll parent) recréait la
/// requête `programsBetween` de CHAQUE ligne visible → rafales SQLite
/// périodiques alors que les bornes de la timeline sont FIXES (posées
/// une fois en initState de l'écran). Le future ne se recrée que si la
/// chaîne ou la version des données EPG change (didUpdateWidget).
class _ProgramsRow extends StatefulWidget {
  const _ProgramsRow({
    required this.channelId,
    required this.timelineStart,
    required this.timelineEnd,
    required this.hourWidth,
    required this.rowHeight,
    required this.now,
    required this.epgVersion,
    required this.onProgramTap,
  });

  final String channelId;
  final DateTime timelineStart;
  final DateTime timelineEnd;
  final double hourWidth;
  final double rowHeight;
  final DateTime now;

  /// Version des données EPG : quand elle change (sync terminée), la
  /// requête mémorisée est relancée. Le tic d'horloge, lui, ne touche
  /// à rien.
  final int epgVersion;
  final void Function(EpgProgram) onProgramTap;

  @override
  State<_ProgramsRow> createState() => _ProgramsRowState();
}

class _ProgramsRowState extends State<_ProgramsRow> {
  late Future<List<EpgProgram>> _progs;

  @override
  void initState() {
    super.initState();
    _progs = _load();
  }

  @override
  void didUpdateWidget(_ProgramsRow old) {
    super.didUpdateWidget(old);
    if (old.channelId != widget.channelId ||
        old.epgVersion != widget.epgVersion ||
        old.timelineStart != widget.timelineStart ||
        old.timelineEnd != widget.timelineEnd) {
      _progs = _load();
    }
  }

  Future<List<EpgProgram>> _load() => EpgRepository.instance.programsBetween(
        widget.channelId,
        widget.timelineStart.millisecondsSinceEpoch,
        widget.timelineEnd.millisecondsSinceEpoch,
      );

  double _xForTime(DateTime t) {
    final int ms =
        t.millisecondsSinceEpoch - widget.timelineStart.millisecondsSinceEpoch;
    return (ms / (1000 * 60 * 60)) * widget.hourWidth;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<EpgProgram>>(
      future: _progs,
      builder: (BuildContext context,
          AsyncSnapshot<List<EpgProgram>> snap) {
        final List<EpgProgram> progs = snap.data ?? <EpgProgram>[];
        final double totalWidth = widget.hourWidth * 24;
        return SizedBox(
          width: totalWidth,
          height: widget.rowHeight,
          child: Stack(
            children: <Widget>[
              // Grille verticale subtile toutes les heures
              CustomPaint(
                size: Size(totalWidth, widget.rowHeight),
                painter: _HourGridPainter(
                  hourWidth: widget.hourWidth,
                  color: AppColors.border,
                ),
              ),
              // Programmes
              ...progs.map((EpgProgram p) {
                final double left = _xForTime(p.startDateTime).clamp(0, totalWidth);
                final double right =
                    _xForTime(p.stopDateTime).clamp(0, totalWidth);
                final double width = (right - left).clamp(40, totalWidth);
                final bool isLive = p.isLiveAt(widget.now);
                return Positioned(
                  left: left,
                  top: 4,
                  width: width,
                  bottom: 4,
                  child: _ProgramCell(
                    program: p,
                    isLive: isLive,
                    onTap: () => widget.onProgramTap(p),
                  ),
                );
              }),
              // Ligne "now" rouge verticale
              Positioned(
                left: _xForTime(widget.now),
                top: 0,
                bottom: 0,
                width: 2,
                child: Container(color: AppColors.live),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgramCell extends StatelessWidget {
  const _ProgramCell({
    required this.program,
    required this.isLive,
    required this.onTap,
  });

  final EpgProgram program;
  final bool isLive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isLive
                ? AppColors.accentSurface
                : AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isLive
                  ? AppColors.accent
                  : AppColors.border,
              width: isLive ? 1.2 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                program.title,
                style: AppTextStyles.bodyLarge.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isLive
                      ? AppColors.accent
                      : AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                // Plage horaire localisée (suit le format 12h/24h de
                // la locale) au lieu du repli FR du domain.
                epgTimeRange(context, program),
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 9,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HourGridPainter extends CustomPainter {
  _HourGridPainter({required this.hourWidth, required this.color});

  final double hourWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = color;
    for (int h = 0; h <= 24; h++) {
      final double x = h * hourWidth;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HourGridPainter oldDelegate) => false;
}

/// Petit ScrollController qui se laisse contrôler par un autre.
/// On l'utilise pour que chaque ligne horizontale soit synchronisée
/// avec le ScrollController du _TimeRuler (sans permettre de scroller
/// indépendamment).
class _SyncedScrollController extends ScrollController {
  _SyncedScrollController(this._master) {
    _master.addListener(_onMaster);
  }

  final ScrollController _master;

  void _onMaster() {
    if (hasClients) {
      jumpTo(_master.offset);
    }
  }

  @override
  void dispose() {
    _master.removeListener(_onMaster);
    super.dispose();
  }
}
