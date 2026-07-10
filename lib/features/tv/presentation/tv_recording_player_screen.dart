// =========================================================
//  tv_recording_player_screen.dart — Lecteur d'ENREGISTREMENT (10-foot)
// =========================================================
//  Joue un fichier .ts enregistré DANS l'app, via le MÊME moteur natif
//  (ExoPlayer/Media3) que le direct — surtout PAS via un lecteur externe.
//
//  POURQUOI ce lecteur dédié (et pas TvPlayerScreen) :
//   • Avant, « Lire » déléguait à open_filex (intent VIEW). Sur cette box, le
//     seul gestionnaire de .ts était la Galerie Android (gallery3d), qui crashe
//     (FATAL EXCEPTION) et tue l'app. Confirmé par logcat. On joue donc EN
//     INTERNE.
//   • On ne réutilise PAS TvPlayerScreen car il est taillé pour le DIRECT :
//     chien de garde anti-gel, reconnexion auto sur fin de flux, zapping,
//     bouton REC, heartbeat de présence… Pour une VOD locale, « fin de flux »
//     est NORMAL (fin du fichier) — la reconnexion live relancerait en boucle.
//     Ici : lecture simple, OK = Pause/Lecture, Retour = quitter.
//
//  Le natif ouvre les fichiers locaux grâce à DefaultDataSource (cf.
//  NativeVideoView.kt). On passe une URI `file://` pour être explicite.
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../recordings/domain/recording.dart';
import '../core/tv_tokens.dart';

class TvRecordingPlayerScreen extends StatefulWidget {
  const TvRecordingPlayerScreen({super.key, required this.recording});

  final Recording recording;

  @override
  State<TvRecordingPlayerScreen> createState() =>
      _TvRecordingPlayerScreenState();
}

class _TvRecordingPlayerScreenState extends State<TvRecordingPlayerScreen> {
  NativeVideoController? _controller;
  final FocusNode _focus = FocusNode();

  bool _buffering = true;
  bool _playing = true;
  bool _ended = false;
  // États d'échec EXPLICITES (jamais d'écran noir muet).
  bool _missing = false; // fichier absent / vide
  bool _error = false; // ExoPlayer n'a pas pu décoder

  @override
  void initState() {
    super.initState();
    _verifyThenOpen();
  }

  /// Vérifie que le fichier EXISTE et n'est pas vide AVANT d'ouvrir : on
  /// préfère un message clair à un écran noir.
  Future<void> _verifyThenOpen() async {
    bool ok = false;
    try {
      final File f = File(widget.recording.filePath);
      ok = await f.exists() && (await f.length()) > 0;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _missing = true;
        _buffering = false;
      });
      return;
    }
    // `file://` explicite → DefaultDataSource (natif) ouvre le fichier local.
    final String fileUri = Uri.file(widget.recording.filePath).toString();
    final NativeVideoController c =
        NativeVideoController(initialUrl: fileUri)..addListener(_onPlayer);
    setState(() => _controller = c);
  }

  void _onPlayer() {
    final NativeVideoController? c = _controller;
    if (c == null || !mounted) return;
    final bool buffering = c.isBuffering || !c.firstFrame;
    if (buffering != _buffering) setState(() => _buffering = buffering);
    if (c.isPlaying != _playing) setState(() => _playing = c.isPlaying);
    // Fin du fichier = NORMAL pour une VOD : on s'arrête proprement (pas de
    // reconnexion live), on propose Retour.
    if (c.isEnded && !_ended) setState(() => _ended = true);
    // Erreur réelle de décodage → message clair (pas de boucle).
    if (c.hasError && !_error) {
      setState(() {
        _error = true;
        _buffering = false;
      });
    }
  }

  void _togglePlay() {
    final NativeVideoController? c = _controller;
    if (c == null) return;
    if (c.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayer);
    _controller?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String title =
        (widget.recording.programTitle != null &&
                widget.recording.programTitle!.isNotEmpty)
            ? '${widget.recording.channelName} · ${widget.recording.programTitle}'
            : widget.recording.channelName;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (_controller != null && !_missing && !_error)
              NativeVideoView(controller: _controller!),

            // ----- Spinner de chargement -----
            if (_buffering && !_missing && !_error)
              const Center(
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: TvTokens.gold),
                ),
              ),

            // ----- États d'échec EXPLICITES -----
            if (_missing || _error)
              _Message(
                icon: Icons.error_outline_rounded,
                title: _missing
                    ? context.l10n.tvRecNotFoundTitle
                    : context.l10n.tvRecPlayErrorTitle,
                body: _missing
                    ? context.l10n.tvRecNotFoundBody
                    : context.l10n.tvRecDecodeErrorBody,
              ),

            // ----- Fin de lecture -----
            if (_ended && !_missing && !_error)
              _Message(
                icon: Icons.check_circle_outline_rounded,
                title: context.l10n.tvRecEndedTitle,
                body: context.l10n.tvRecEndedBody,
              ),

            // ----- Bandeau titre (haut) -----
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(_playing ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: TvTokens.gold, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
