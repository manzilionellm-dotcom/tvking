// =========================================================
//  startup_ad_screen.dart — Lecture de la pub vidéo de démarrage
// =========================================================
//  Joue la vidéo pub (media_kit) en plein écran. Un bouton « Passer »
//  apparaît après N secondes (réglé au panel). La vidéo finie OU « Passer »
//  OU une erreur de lecture appellent `onDone` (jamais de blocage de
//  l'utilisateur). media_kit est déjà initialisé au boot. Zéro cast.
// =========================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/startup_ad_repository.dart';

class StartupAdScreen extends StatefulWidget {
  const StartupAdScreen({
    super.key,
    required this.config,
    required this.onDone,
  });

  final AdConfig config;
  final VoidCallback onDone;

  @override
  State<StartupAdScreen> createState() => _StartupAdScreenState();
}

class _StartupAdScreenState extends State<StartupAdScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Duration>? _progressSub;
  bool _markedShown = false;
  Timer? _skipTimer;
  Timer? _safetyTimer;
  bool _canSkip = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = Player();
    _controller = VideoController(_player);

    // Révèle « Passer » après le délai configuré.
    _skipTimer = Timer(Duration(seconds: widget.config.skip), () {
      if (mounted) setState(() => _canSkip = true);
    });
    // Filet de sécurité : si la vidéo ne démarre jamais, on libère au bout
    // de 20 s (skip + marge) pour ne JAMAIS bloquer l'utilisateur.
    _safetyTimer = Timer(Duration(seconds: widget.config.skip + 20), _finish);

    // Fin de vidéo → on continue vers l'app.
    _completedSub = _player.stream.completed.listen((bool c) {
      if (c) _finish();
    });
    // Erreur de lecture → on ne bloque pas, on passe.
    _errorSub = _player.stream.error.listen((_) => _finish());
    // Une panne n'épuise pas le droit quotidien. On mémorise seulement
    // après une progression réelle du lecteur, jamais dans onDone.
    _progressSub = _player.stream.position.listen((Duration position) {
      if (!_done &&
          !_markedShown &&
          position > Duration.zero &&
          _player.state.playing) {
        _markedShown = true;
        unawaited(StartupAdRepository.instance.markShown());
      }
    });
    // Les écouteurs sont en place AVANT l'ouverture : une erreur immédiate
    // ou un refus du moteur libère aussi l'accueil.
    unawaited(
      _player.open(Media(widget.config.url)).catchError((Object _) {
        _finish();
      }),
    );
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _finish();
    }
  }

  @override
  void dispose() {
    _done = true;
    WidgetsBinding.instance.removeObserver(this);
    _skipTimer?.cancel();
    _safetyTimer?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    _progressSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Video(
              controller: _controller,
              // Même forme typée que le player principal (video_player_screen):
              // `NoVideoControls` est exposé en `dynamic` par la version
              // installée de media_kit_video → erreur d'analyse. Le builder
              // explicite « pas de contrôles » est équivalent et compile.
              controls: (VideoState _) => const SizedBox.shrink(),
              fit: BoxFit.contain,
            ),
          ),
          // Bouton « Passer » (en haut à droite, après le délai).
          if (_canSkip)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 14,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _finish,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Passer',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.skip_next_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
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
