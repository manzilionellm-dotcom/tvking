// =========================================================
//  playback_probe_main.dart — lecture d'un flux PUBLIC de test
// =========================================================
//  Point d'entrée UNIQUEMENT pour un APK de diagnostic. Il n'est pas
//  le main de production (celui-ci reste lib/main_tv.dart) et ne contient
//  aucune playlist IPTV, aucun identifiant client, aucune MAC.
//
//  La mire est un fichier H.264 local (testsrc2), poussé dans le dossier
//  externe de l'app. On l'ouvre avec le MÊME lecteur que la box
//  (NativeVideoView, hybrid composition, ExoPlayer).
//
//  Build :
//    flutter build apk --debug --target=lib/dev/playback_probe_main.dart
// =========================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:path_provider/path_provider.dart';

/// Nom du fichier de mire poussé dans le dossier externe de l'app
/// (`adb push probe_bars.mp4` vers ce dossier). testsrc2 H.264, aucun
/// identifiant client. Le seau Google public répond 403 au User-Agent
/// VLC du lecteur, donc la preuve lit ce fichier local.
const String kProbeFileName = 'probe_bars.mp4';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PlaybackProbeApp());
}

class PlaybackProbeApp extends StatelessWidget {
  const PlaybackProbeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PlaybackProbeScreen(),
    );
  }
}

class PlaybackProbeScreen extends StatefulWidget {
  const PlaybackProbeScreen({super.key});

  @override
  State<PlaybackProbeScreen> createState() => _PlaybackProbeScreenState();
}

class _PlaybackProbeScreenState extends State<PlaybackProbeScreen> {
  NativeVideoController? _controller;
  String _note = 'préparation de la mire…';

  @override
  void initState() {
    super.initState();
    // Même forme que le lecteur TV : fichier fini (vod), contraste demandé
    // comme en production (allumé par défaut).
    NativeVideoController.defaultLightContrast = true;
    _open();
  }

  Future<void> _open() async {
    final Directory dir = (await getExternalStorageDirectory())!;
    final File file = File('${dir.path}/$kProbeFileName');
    if (!file.existsSync()) {
      setState(() => _note = 'fichier absent : ${file.path}');
      return;
    }
    final NativeVideoController controller = NativeVideoController(
      initialUrl: file.uri.toString(),
      openAsVod: true,
    )..addListener(_onPlayer);
    setState(() {
      _controller = controller;
      _note = file.uri.toString();
    });
  }

  void _onPlayer() {
    final NativeVideoController? c = _controller;
    if (c == null) return;
    debugPrint(
      'PROBE firstFrame=${c.firstFrame} playing=${c.isPlaying} '
      'buffering=${c.isBuffering} error=${c.hasError} '
      'contrast=${c.contrastApplied} reason=${c.contrastReason}',
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayer);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NativeVideoController? c = _controller;
    // Pas de bandeau opaque : il masquait toute la surface et un screencap
    // ne pouvait plus dire si les pixels vidéo étaient là. L'état part dans
    // logcat (PROBE ...). Le fond noir est le même que le lecteur TV.
    return ColoredBox(
      color: Colors.black,
      child: c == null
          ? Center(
              child: Text(_note, style: const TextStyle(color: Colors.white)),
            )
          : Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: NativeVideoView(controller: c),
              ),
            ),
    );
  }
}
