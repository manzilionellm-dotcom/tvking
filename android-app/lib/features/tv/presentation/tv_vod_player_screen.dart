// =========================================================
//  tv_vod_player_screen.dart — Lecteur Films / Épisodes (télécommande)
// =========================================================
//  Même moteur que le Direct (SurfaceView + ExoPlayer, décodage matériel),
//  en MODE FILM : reprise à la seconde, avance/retour, audio, sous-titres.
//
//  TÉLÉCOMMANDE (pensée pour qu'un enfant s'y retrouve) :
//    OK / ⏯          Lecture ⇄ Pause
//    ◀ / ▶ , ⏪ / ⏩   Recule / avance de 10 s (maintenu : 30 s puis 60 s) ;
//                    les appuis s'additionnent, le saut se fait à la pause.
//    ▼               Boutons : Audio et sous-titres · Recommencer · Suivant
//    ▲               Retour à la barre de temps
//    Retour          Ferme ce qui est ouvert, sinon quitte (position gardée)
//
//  NETFLIX-LIKE :
//    • reprise automatique (5 s avant l'endroit quitté) ;
//    • position enregistrée toutes les 10 s + à la pause + en quittant ;
//    • fin de l'épisode : carte « Épisode suivant dans N s » (OK = tout de
//      suite, Retour = rester) et enchaînement automatique ;
//    • épisode fini + téléchargé → effacé, et le suivant se télécharge
//      tout seul en Wi-Fi (« Téléchargement intelligent ») ;
//    • choix audio / sous-titres retenu pour les films suivants.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../cinema/data/cinema_downloads.dart';
import '../../cinema/data/watch_progress.dart';
import '../../cinema/domain/cinema_language.dart';
import '../../cinema/domain/cinema_models.dart';
import '../core/tv_activity.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_cinema_common.dart';

class TvVodPlayerScreen extends StatefulWidget {
  const TvVodPlayerScreen({
    super.key,
    required this.item,
    this.startAt = Duration.zero,
    this.localPath,
    this.series,
    this.seriesTitle,
  });

  final VodPlayItem item;
  final Duration startAt;

  /// Fichier téléchargé (lecture hors ligne) — prioritaire sur le flux.
  final String? localPath;

  /// Contexte série (épisode suivant, téléchargement intelligent).
  final SeriesDetails? series;
  final CinemaTitle? seriesTitle;

  @override
  State<TvVodPlayerScreen> createState() => _TvVodPlayerScreenState();
}

enum _Zone { timeline, buttons }

class _TvVodPlayerScreenState extends State<TvVodPlayerScreen>
    with WidgetsBindingObserver {
  late NativeVideoController _c;
  late VodPlayItem _item;
  final FocusNode _focus = FocusNode();

  bool _overlay = true;
  Timer? _hideTimer;
  _Zone _zone = _Zone.timeline;
  int _btn = 0;

  // Avance / retour cumulés.
  Duration? _seekTarget;
  Timer? _seekTimer;
  int _repeat = 0;

  // Panneau audio / sous-titres.
  bool _tracksOpen = false;
  int _trackIdx = 0;

  // Carte « Épisode suivant ».
  CinemaEpisode? _next;
  bool _nextCard = false;
  bool _nextDismissed = false;
  int _countdown = 0;
  Timer? _countdownTimer;

  // Reprise affichée brièvement (« Reprise à 42:10 »).
  String? _toast;
  Timer? _toastTimer;

  Timer? _saveTimer;
  bool _finishHandled = false;
  bool _endHandled = false;
  bool _fatal = false;
  DateTime _lastBack = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TvActivity.enter();
    _item = widget.item;
    _c = NativeVideoController()..addListener(_onPlayer);
    _next = _computeNext();
    unawaited(_start(_item, widget.startAt, local: widget.localPath));
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
    _armHide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _c.pause();
        _saveProgress(flush: true);
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break; // reprise manuelle (OK) : pas de son surprise au retour
    }
  }

  @override
  void dispose() {
    _saveProgress(flush: true);
    WidgetsBinding.instance.removeObserver(this);
    TvActivity.leave();
    _hideTimer?.cancel();
    _seekTimer?.cancel();
    _countdownTimer?.cancel();
    _toastTimer?.cancel();
    _saveTimer?.cancel();
    _c.removeListener(_onPlayer);
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------
  //  Démarrage / enchaînement
  // ---------------------------------------------------------

  Future<void> _start(VodPlayItem item, Duration startAt, {String? local}) async {
    final String? audioPref = await CinemaTrackPrefs.audio();
    final String? textPref = await CinemaTrackPrefs.text();
    if (!mounted) return;
    final String appLang = Localizations.localeOf(context).languageCode;
    BlackBox.instance.breadcrumb('Cinéma : lecture ${item.title} ${item.subtitle ?? ''}');
    BlackBox.instance.info('CINEMA',
        'lecture ${item.id} ${local != null ? '(hors ligne)' : ''} à ${startAt.inSeconds}s');
    _c.setUrl(
      local ?? item.url,
      vod: true,
      startAt: startAt,
      preferredAudio: audioPref ?? appLang,
      preferredText: (textPref == null || textPref == 'off') ? null : textPref,
    );
    if (startAt > const Duration(seconds: 10)) {
      _showToast(context.l10n.tvCinemaResumedAt(formatClock(startAt)));
    }
  }

  CinemaEpisode? _computeNext() {
    final SeriesDetails? s = widget.series;
    if (s == null || !_item.isEpisode) return null;
    for (final CinemaEpisode e in s.allInOrder) {
      if (e.id == _item.id) return s.nextAfter(e);
    }
    return null;
  }

  Future<void> _playNext() async {
    final CinemaEpisode? n = _next;
    final CinemaTitle? st = widget.seriesTitle;
    if (n == null || st == null) return;
    _saveProgress(flush: true);
    _countdownTimer?.cancel();
    final VodPlayItem ni = VodPlayItem.episode(n, st);
    final WatchEntry? prev = WatchProgressRepository.instance.get(ni.id);
    final String? local = await offlinePathFor(ni.id);
    if (!mounted) return;
    setState(() {
      _item = ni;
      _next = _computeNext();
      _nextCard = false;
      _nextDismissed = false;
      _finishHandled = false;
      _endHandled = false;
      _fatal = false;
      _zone = _Zone.timeline;
      _tracksOpen = false;
    });
    await _start(ni, prev?.resumeAt ?? Duration.zero, local: local);
    _showOverlay();
  }

  // ---------------------------------------------------------
  //  État du lecteur
  // ---------------------------------------------------------

  void _onPlayer() {
    if (!mounted) return;
    if (_c.hasError && !_fatal) {
      BlackBox.instance.warn('CINEMA', 'lecture impossible ${_item.id}');
      _fatal = true;
      _overlay = true;
    }
    final Duration d = _c.duration;
    final Duration p = _c.position;
    if (d > Duration.zero && _item.isEpisode && _next != null && !_nextDismissed) {
      final Duration left = d - p;
      if (!_nextCard && (left <= const Duration(seconds: 20) || _c.isEnded) &&
          d > const Duration(minutes: 5)) {
        _openNextCard(left);
      }
    }
    if (_c.isEnded && !_endHandled) {
      _endHandled = true;
      _saveProgress(flush: true, ended: true);
      if (_next == null || _nextDismissed) {
        // Fin d'un film (ou de la série) : on sort proprement.
        Future<void>.microtask(() {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
    setState(() {});
  }

  void _openNextCard(Duration left) {
    _nextCard = true;
    _countdown = left.inSeconds.clamp(8, 20);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return t.cancel();
      if (_c.isPlaying || _c.isEnded) {
        setState(() => _countdown--);
      }
      if (_countdown <= 0) {
        t.cancel();
        unawaited(_playNext());
      }
    });
  }

  /// Enregistre la position ; gère la fin (suivant proposé, téléchargement
  /// intelligent) une seule fois par épisode.
  void _saveProgress({bool flush = false, bool ended = false}) {
    final int dur = _c.duration.inMilliseconds;
    int pos = _c.position.inMilliseconds;
    if (ended && dur > 0) pos = dur;
    if (pos <= 0 || dur <= 0) return;
    final WatchEntry stored = WatchProgressRepository.instance
        .record(_item.toEntry(posMs: pos, durMs: dur), flushNow: flush);
    if (stored.finished && !_finishHandled) {
      _finishHandled = true;
      _onFinished();
    }
  }

  void _onFinished() {
    final CinemaEpisode? n = _next;
    final CinemaTitle? st = widget.seriesTitle;
    VodPlayItem? ni;
    if (n != null && st != null) {
      ni = VodPlayItem.episode(n, st);
      WatchProgressRepository.instance.proposeNext(ni.toEntry(posMs: 0, durMs: n.durationSec * 1000));
    }
    if (_item.isEpisode) {
      unawaited(CinemaDownloads.onEpisodeFinished(
        finishedId: _item.id,
        next: ni?.toVodMovie(),
      ));
    }
  }

  // ---------------------------------------------------------
  //  Barre / toasts
  // ---------------------------------------------------------

  void _showOverlay() {
    if (!_overlay) setState(() => _overlay = true);
    _armHide();
  }

  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _tracksOpen || _fatal || !_c.isPlaying) return;
      setState(() {
        _overlay = false;
        _zone = _Zone.timeline;
      });
    });
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toast = msg);
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ---------------------------------------------------------
  //  Avance / retour
  // ---------------------------------------------------------

  void _seekBy(int direction, {bool repeat = false}) {
    _repeat = repeat ? _repeat + 1 : 0;
    final int step = _repeat > 15 ? 60 : (_repeat > 5 ? 30 : 10);
    final Duration base = _seekTarget ?? _c.position;
    Duration t = base + Duration(seconds: step * direction);
    final Duration d = _c.duration;
    if (t < Duration.zero) t = Duration.zero;
    if (d > Duration.zero && t > d - const Duration(seconds: 2)) {
      t = d - const Duration(seconds: 2);
    }
    setState(() => _seekTarget = t);
    _showOverlay();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 650), () {
      final Duration? target = _seekTarget;
      if (target == null || !mounted) return;
      _c.seekTo(target);
      setState(() => _seekTarget = null);
      _saveProgress();
    });
  }

  void _togglePlay() {
    if (_c.isPlaying) {
      _c.pause();
      _saveProgress(flush: true);
    } else {
      _c.play();
    }
    _showOverlay();
  }

  // ---------------------------------------------------------
  //  Boutons (zone du bas)
  // ---------------------------------------------------------

  List<({IconData icon, String label, VoidCallback run})> _buttons(BuildContext context) =>
      <({IconData icon, String label, VoidCallback run})>[
        (
          icon: Icons.subtitles_rounded,
          label: context.l10n.tvCinemaAudioSubs,
          run: _openTracks,
        ),
        (
          icon: Icons.replay_rounded,
          label: context.l10n.tvCinemaRestart,
          run: () {
            _c.seekTo(Duration.zero);
            _c.play();
            _showOverlay();
          },
        ),
        if (_next != null)
          (
            icon: Icons.skip_next_rounded,
            label: context.l10n.tvCinemaNextEpisode,
            run: () => unawaited(_playNext()),
          ),
      ];

  // ---------------------------------------------------------
  //  Audio / sous-titres
  // ---------------------------------------------------------

  List<NativeTrack> get _audio => _c.tracks.where((NativeTrack t) => t.isAudio).toList();
  List<NativeTrack> get _texts => _c.tracks.where((NativeTrack t) => !t.isAudio).toList();

  /// Entrées du panneau : audio…, « Sous-titres désactivés », sous-titres…
  int get _trackCount => _audio.length + 1 + _texts.length;

  void _openTracks() {
    setState(() {
      _tracksOpen = true;
      final int sel = _audio.indexWhere((NativeTrack t) => t.selected);
      _trackIdx = sel < 0 ? 0 : sel;
    });
    _hideTimer?.cancel();
  }

  void _chooseTrack(int i) {
    final List<NativeTrack> a = _audio;
    final List<NativeTrack> t = _texts;
    if (i < a.length) {
      _c.selectTrack(a[i]);
      unawaited(CinemaTrackPrefs.setAudio(
          a[i].language == null ? null : CinemaLanguage.normalizeCode(a[i].language!)));
    } else if (i == a.length) {
      _c.disableSubtitles();
      unawaited(CinemaTrackPrefs.setText(null));
    } else {
      final NativeTrack tr = t[i - a.length - 1];
      _c.selectTrack(tr);
      unawaited(CinemaTrackPrefs.setText(
          tr.language == null ? null : CinemaLanguage.normalizeCode(tr.language!)));
    }
    setState(() => _tracksOpen = false);
    _showOverlay();
  }

  String _trackLabel(BuildContext context, NativeTrack t, int n) {
    final String? lang = CinemaLanguage.labelFor(t.language);
    final List<String> parts = <String>[
      lang ?? context.l10n.tvCinemaTrackUnknown(n.toString()),
      if (t.label != null && t.label!.trim().isNotEmpty && t.label != lang) t.label!.trim(),
      if (t.isAudio && t.channels >= 6) '5.1',
    ];
    return parts.join(' · ');
  }

  // ---------------------------------------------------------
  //  Télécommande
  // ---------------------------------------------------------

  static bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.space ||
      k == LogicalKeyboardKey.gameButtonA;

  static bool _isBack(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.goBack ||
      k == LogicalKeyboardKey.escape ||
      k == LogicalKeyboardKey.browserBack ||
      k == LogicalKeyboardKey.exit;

  void _handleBack() {
    final DateTime now = DateTime.now();
    if (now.difference(_lastBack) < const Duration(milliseconds: 300)) return;
    _lastBack = now;
    if (_tracksOpen) {
      setState(() => _tracksOpen = false);
      _armHide();
    } else if (_nextCard && !_c.isEnded) {
      _countdownTimer?.cancel();
      setState(() {
        _nextCard = false;
        _nextDismissed = true;
      });
    } else if (_zone == _Zone.buttons) {
      setState(() => _zone = _Zone.timeline);
    } else if (_overlay && _c.isPlaying && !_fatal) {
      setState(() => _overlay = false);
    } else {
      _saveProgress(flush: true);
      Navigator.of(context).pop();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bool repeat = event is KeyRepeatEvent;
    final LogicalKeyboardKey k = event.logicalKey;

    if (_isBack(k)) {
      if (!repeat) _handleBack();
      return KeyEventResult.handled;
    }

    if (_fatal) {
      if (_isOk(k) && !repeat) {
        setState(() {
          _fatal = false;
          _endHandled = false;
        });
        unawaited(_start(_item, _c.position, local: null));
      }
      return KeyEventResult.handled;
    }

    // ----- Panneau audio / sous-titres -----
    if (_tracksOpen) {
      if (k == LogicalKeyboardKey.arrowDown) {
        setState(() => _trackIdx = (_trackIdx + 1).clamp(0, _trackCount - 1));
      } else if (k == LogicalKeyboardKey.arrowUp) {
        setState(() => _trackIdx = (_trackIdx - 1).clamp(0, _trackCount - 1));
      } else if (_isOk(k) && !repeat) {
        _chooseTrack(_trackIdx);
      } else if (k == LogicalKeyboardKey.arrowLeft) {
        setState(() => _tracksOpen = false);
      }
      return KeyEventResult.handled;
    }

    // ----- Carte « Épisode suivant » -----
    if (_nextCard && _zone == _Zone.timeline && _isOk(k) && !repeat) {
      unawaited(_playNext());
      return KeyEventResult.handled;
    }

    // ----- Touches média -----
    if (k == LogicalKeyboardKey.mediaPlayPause) {
      if (!repeat) _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      _c.play();
      _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPause || k == LogicalKeyboardKey.mediaStop) {
      _c.pause();
      _saveProgress(flush: true);
      _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-1, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(1, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackNext && _next != null) {
      unawaited(_playNext());
      return KeyEventResult.handled;
    }

    // ----- Zone des boutons -----
    if (_zone == _Zone.buttons) {
      final int n = _buttons(context).length;
      if (k == LogicalKeyboardKey.arrowLeft) {
        setState(() => _btn = (_btn - 1).clamp(0, n - 1));
      } else if (k == LogicalKeyboardKey.arrowRight) {
        setState(() => _btn = (_btn + 1).clamp(0, n - 1));
      } else if (k == LogicalKeyboardKey.arrowUp) {
        setState(() => _zone = _Zone.timeline);
      } else if (_isOk(k) && !repeat) {
        _buttons(context)[_btn.clamp(0, n - 1)].run();
      }
      _armHide();
      return KeyEventResult.handled;
    }

    // ----- Barre de temps -----
    if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-1, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(1, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (_isOk(k)) {
      if (!repeat) _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_overlay) {
        setState(() {
          _zone = _Zone.buttons;
          _btn = 0;
        });
      }
      _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _showOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------
  //  Rendu
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Material transparent : route séparée hors TvShell (sinon texte en
    // style d'erreur jaune souligné — cf. lecteur du Direct).
    return Material(
      type: MaterialType.transparency,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) _handleBack();
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlay,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: NativeVideoView(controller: _c),
                    ),
                  ),
                  if (!_c.firstFrame && !_fatal) _buildLoading(),
                  if (_c.cues.isNotEmpty) _buildSubtitles(),
                  if (_overlay || _fatal) _buildOverlay(context),
                  if (_toast != null) _buildToast(),
                  if (_nextCard && _next != null) _buildNextCard(context),
                  if (_tracksOpen) _buildTracks(context),
                  if (_fatal) _buildError(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() => const Center(
        child: SizedBox(
          width: 46,
          height: 46,
          child: CircularProgressIndicator(strokeWidth: 3, color: TvTokens.accent),
        ),
      );

  Widget _buildSubtitles() => Positioned(
        left: 120,
        right: 120,
        bottom: _overlay ? 170 : 60,
        child: Text(
          _c.cues,
          textAlign: TextAlign.center,
          style: TvTokens.ui(30, weight: FontWeight.w600, color: TvTokens.text).copyWith(
            shadows: const <Shadow>[
              Shadow(blurRadius: 6, color: Colors.black),
              Shadow(offset: Offset(0, 2), blurRadius: 3, color: Colors.black),
            ],
          ),
        ),
      );

  Widget _buildOverlay(BuildContext context) {
    final Duration d = _c.duration;
    final Duration p = _seekTarget ?? _c.position;
    final double frac = d > Duration.zero ? (p.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0) : 0;
    final List<({IconData icon, String label, VoidCallback run})> btns = _buttons(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Voile haut + titre.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(60, 34, 60, 50),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.black.withValues(alpha: 0.75), Colors.transparent],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.display(34, color: TvTokens.text)),
                if (_item.subtitle != null)
                  Text(_item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.ui(TvDimens.title, color: TvTokens.muted)),
              ],
            ),
          ),
        ),
        // Voile bas + temps + barre + boutons.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(60, 60, 60, 34),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: <Color>[Colors.black.withValues(alpha: 0.85), Colors.transparent],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      _c.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: _zone == _Zone.timeline ? TvTokens.accentBright : TvTokens.muted,
                      size: 34,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: _zone == _Zone.timeline ? 8 : 5,
                        decoration: BoxDecoration(
                          color: TvTokens.line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: frac,
                          child: Container(
                            decoration: BoxDecoration(
                              color: TvTokens.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      d > Duration.zero ? '${formatClock(p)} / ${formatClock(d)}' : formatClock(p),
                      style: TvTokens.mono(18,
                          color: _seekTarget != null ? TvTokens.accentBright : TvTokens.text),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < btns.length; i++) ...<Widget>[
                      _PlayerButton(
                        icon: btns[i].icon,
                        label: btns[i].label,
                        focused: _zone == _Zone.buttons && _btn == i,
                      ),
                      const SizedBox(width: 14),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToast() => Positioned(
        top: 120,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: TvTokens.surface3.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(TvTokens.rButton),
            ),
            child: Text(_toast!,
                style: TvTokens.ui(TvDimens.titleS, weight: FontWeight.w600, color: TvTokens.text)),
          ),
        ),
      );

  Widget _buildNextCard(BuildContext context) {
    final CinemaEpisode n = _next!;
    return Positioned(
      right: 60,
      bottom: _overlay ? 170 : 60,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: TvTokens.surface3.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(TvTokens.rCard),
          border: Border.all(color: TvTokens.accent, width: TvDimens.focusOutline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(context.l10n.tvCinemaNextIn(_countdown.clamp(0, 99).toString()),
                style: TvTokens.ui(TvDimens.label, weight: FontWeight.w700, color: TvTokens.accentBright)),
            const SizedBox(height: 6),
            Text(episodeLabel(n),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.ui(TvDimens.titleS, weight: FontWeight.w700, color: TvTokens.text)),
            const SizedBox(height: 10),
            Text(context.l10n.tvCinemaNextHint,
                style: TvTokens.ui(TvDimens.caption, color: TvTokens.mutedDim)),
          ],
        ),
      ),
    );
  }

  Widget _buildTracks(BuildContext context) {
    final List<NativeTrack> a = _audio;
    final List<NativeTrack> t = _texts;
    final bool textOn = t.any((NativeTrack x) => x.selected);
    final List<Widget> rows = <Widget>[];
    int idx = 0;
    Widget row(String label, bool selected, int i) => Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _trackIdx == i ? TvTokens.sel : Colors.transparent,
            borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
            border: _trackIdx == i
                ? Border.all(color: TvTokens.accent, width: TvDimens.focusOutline)
                : null,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 28,
                child: selected
                    ? const Icon(Icons.check_rounded, color: TvTokens.accentBright, size: 22)
                    : null,
              ),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(TvDimens.body,
                        weight: FontWeight.w600,
                        color: _trackIdx == i ? TvTokens.accentBright : TvTokens.text)),
              ),
            ],
          ),
        );
    Widget header(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
          child: Text(s.toUpperCase(),
              style: TvTokens.ui(12, weight: FontWeight.w700, color: TvTokens.mutedDim, spacing: 2)),
        );

    rows.add(header(context.l10n.tvCinemaAudio));
    for (int i = 0; i < a.length; i++) {
      rows.add(row(_trackLabel(context, a[i], i + 1), a[i].selected, idx++));
    }
    rows.add(header(context.l10n.tvCinemaSubtitles));
    rows.add(row(context.l10n.tvCinemaSubtitlesOff, !textOn, idx++));
    for (int i = 0; i < t.length; i++) {
      rows.add(row(_trackLabel(context, t[i], i + 1), t[i].selected, idx++));
    }
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 420,
        padding: const EdgeInsets.fromLTRB(22, 40, 22, 30),
        color: TvTokens.panel.withValues(alpha: 0.97),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(context.l10n.tvCinemaAudioSubs,
                  style: TvTokens.display(28, color: TvTokens.text)),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 26),
          decoration: BoxDecoration(
            color: TvTokens.surface3.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(TvTokens.rCard),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline_rounded, color: TvTokens.live, size: 44),
              const SizedBox(height: 12),
              Text(context.l10n.tvPlaybackImpossible,
                  style: TvTokens.display(28, color: TvTokens.text)),
              const SizedBox(height: 14),
              Text(context.l10n.tvPlayerFatalHint,
                  style: TvTokens.ui(TvDimens.titleS, weight: FontWeight.w700, color: TvTokens.accentBright)),
            ],
          ),
        ),
      );
}

class _PlayerButton extends StatelessWidget {
  const _PlayerButton({required this.icon, required this.label, required this.focused});
  final IconData icon;
  final String label;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final Color fg = focused ? TvTokens.onAccent : TvTokens.text;
    return AnimatedContainer(
      duration: TvDimens.focusAnim,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: focused ? TvTokens.accent : TvTokens.sel.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(TvTokens.rButton),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 22, color: fg),
          const SizedBox(width: 8),
          Text(label, style: TvTokens.ui(TvDimens.label, weight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}
