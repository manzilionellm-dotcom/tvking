// =========================================================
//  tv_catchup_player_screen.dart — Lecteur REPLAY / catch-up (10-foot)
// =========================================================
//  Joue une émission PASSÉE via l'URL catch-up du fournisseur, construite par
//  CatchupUrlBuilder (timeshift Xtream auto-détecté, template M3U
//  `catchup-source`, ou paramètres par défaut `?utc=&lutc=`).
//
//  POURQUOI un lecteur DÉDIÉ (et pas TvPlayerScreen) : le lecteur live est
//  taillé pour le DIRECT — watchdog anti-gel, reconnexion auto sur fin de
//  flux, zap Haut/Bas... Ici, la « fin de flux » est NORMALE (fin de
//  l'émission) et on veut surtout le SEEK. Même moteur natif (ExoPlayer).
//
//  Télécommande : OK / lecture-pause = pause-reprise ; ◀ / ▶ = -30 s / +30 s ;
//  Retour = quitter. Une barre de progression s'affiche avec l'overlay.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../channels/domain/channel.dart';
import '../../epg/domain/epg_program.dart';
import '../core/tv_tokens.dart';

class TvCatchupPlayerScreen extends StatefulWidget {
  const TvCatchupPlayerScreen({
    super.key,
    required this.channel,
    required this.program,
    required this.url,
  });

  final Channel channel;
  final EpgProgram program;

  /// URL catch-up déjà construite (CatchupUrlBuilder.build).
  final String url;

  @override
  State<TvCatchupPlayerScreen> createState() => _TvCatchupPlayerScreenState();
}

class _TvCatchupPlayerScreenState extends State<TvCatchupPlayerScreen> {
  late final NativeVideoController _controller =
      NativeVideoController(initialUrl: widget.url)..addListener(_onPlayer);
  final FocusNode _focus = FocusNode();

  bool _buffering = true;
  bool _playing = true;
  bool _ended = false;
  bool _error = false;
  bool _overlay = true; // infos + barre de progression (auto-masquées)
  Timer? _hideTimer;

  static const Duration _seekStep = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _showOverlayTemporarily();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_onPlayer);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onPlayer() {
    if (!mounted) return;
    final bool buffering = _controller.isBuffering || !_controller.firstFrame;
    // setState global : l'écran affiche la position/durée en continu quand
    // l'overlay est visible — rebuild léger (peu de widgets), acceptable ici.
    setState(() {
      _buffering = buffering;
      _playing = _controller.isPlaying;
      if (_controller.isEnded) _ended = true;
      // Le replay n'a PAS de reconnexion auto : une erreur = message clair
      // (l'URL catch-up est valide quelques heures/jours, pas éternellement).
      if (_controller.hasError) {
        _error = true;
        _buffering = false;
      }
    });
  }

  void _showOverlayTemporarily() {
    setState(() => _overlay = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _overlay = false);
    });
  }

  void _togglePlay() {
    if (_controller.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    _showOverlayTemporarily();
  }

  void _seekBy(Duration delta) {
    Duration target = _controller.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    final Duration d = _controller.duration;
    if (d > Duration.zero && target > d) target = d;
    _controller.seekTo(target);
    _showOverlayTemporarily();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-_seekStep);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(_seekStep);
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static String _fmt(Duration d) {
    final int h = d.inHours;
    final String m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final Duration pos = _controller.position;
    final Duration dur = _controller.duration;
    final double? progress = dur > Duration.zero
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : null;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showOverlayTemporarily,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (!_error)
                Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: NativeVideoView(controller: _controller),
                  ),
                ),

              if (_buffering && !_error && !_ended)
                const Center(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: TvTokens.gold),
                  ),
                ),

              if (_error)
                const _Message(
                  icon: Icons.error_outline_rounded,
                  title: 'Replay indisponible',
                  body: 'Cette émission n\'est plus disponible en replay '
                      'chez le fournisseur.',
                ),

              if (_ended && !_error)
                const _Message(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Fin de l\'émission',
                  body: 'Appuie sur Retour pour revenir au guide.',
                ),

              // ----- Overlay infos + progression (auto-masqué) -----
              AnimatedOpacity(
                opacity: _overlay ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_overlay,
                  child: Column(
                    children: <Widget>[
                      // Bandeau haut : REPLAY + chaîne + titre de l'émission.
                      Container(
                        padding: const EdgeInsets.fromLTRB(28, 22, 28, 34),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.black.withValues(alpha: 0.72),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: TvTokens.gold,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('REPLAY',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                      color: Colors.black)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                '${widget.channel.cleanName} · '
                                '${widget.program.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            Icon(
                              _playing
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              color: TvTokens.gold,
                              size: 30,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Barre de progression + temps + aide télécommande.
                      Container(
                        padding: const EdgeInsets.fromLTRB(28, 34, 28, 22),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: <Color>[
                              Colors.black.withValues(alpha: 0.72),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.18),
                                color: TvTokens.gold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
                                Text(_fmt(pos),
                                    style: TextStyle(
                                        color: TvTokens.text, fontSize: 14)),
                                const Spacer(),
                                Text(
                                  '◀ -30 s   ·   OK lecture/pause   ·   +30 s ▶',
                                  style: TextStyle(
                                      color: TvTokens.mutedDim, fontSize: 13),
                                ),
                                const Spacer(),
                                Text(dur > Duration.zero ? _fmt(dur) : '--:--',
                                    style: TextStyle(
                                        color: TvTokens.text, fontSize: 14)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: TvTokens.mutedDim, size: 52),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: TvTokens.mutedDim, fontSize: 16)),
        ],
      ),
    );
  }
}
