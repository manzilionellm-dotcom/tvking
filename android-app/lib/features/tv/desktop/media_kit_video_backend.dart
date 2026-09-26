// =========================================================
//  media_kit_video_backend.dart — Lecteur de Zuno sur PC (Windows)
// =========================================================
//  Sur la box, NativeVideoController pilote ExoPlayer (Android). Sur PC, ce
//  fichier fournit le MÊME contrat avec media_kit (libmpv, le moteur de
//  VLC / mpv), décodage matériel (D3D11) : Direct, Films, Séries, reprise,
//  audio, sous-titres, épisode suivant fonctionnent sans changer une ligne
//  des écrans.
//
//  Correspondance des événements (identiques à ceux du natif Android) :
//    position / duration / buffering / playing / ended / error / tracks /
//    cues (texte des sous-titres, affiché par l'app) / firstFrame (1re image :
//    largeur vidéo connue).
//
//  Réglages repris de la box :
//    • User-Agent « VLC » (certains serveurs IPTV ne servent que les
//      lecteurs connus) ;
//    • langue audio / sous-titres préférée (alang / slang de mpv) ;
//    • position de départ (reprise d'un film).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/blackbox/black_box.dart';

class MediaKitVideoBackend implements NativeVideoBackend {
  MediaKitVideoBackend()
      : _player = Player(
          configuration: const PlayerConfiguration(
            title: 'Zuno',
            // Tampon plus généreux que la box (un PC a de la mémoire) :
            // absorbe mieux un Wi-Fi qui faiblit.
            bufferSize: 64 * 1024 * 1024,
          ),
        ) {
    _video = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    unawaited(_configure());
  }

  final Player _player;
  late final VideoController _video;
  NativeVideoController? _c;
  final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];
  final FocusNode _noFocus = FocusNode(skipTraversal: true, canRequestFocus: false);

  // Correspondance index de piste « NativeTrack » ↔ piste media_kit.
  List<AudioTrack> _audio = const <AudioTrack>[];
  List<SubtitleTrack> _texts = const <SubtitleTrack>[];
  bool _firstFrame = false;

  Future<void> _configure() async {
    final PlatformPlayer? p = _player.platform;
    if (p is NativePlayer) {
      try {
        await p.setProperty('user-agent', 'VLC/3.0.20 LibVLC/3.0.20');
        // Reconnexion réseau automatique (coupure brève du serveur IPTV).
        await p.setProperty(
            'stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
      } catch (e) {
        BlackBox.instance.warn('PC', 'réglages libmpv : $e');
      }
    }
  }

  @override
  void bind(NativeVideoController controller) {
    _c = controller;
    final PlayerStream s = _player.stream;
    _subs
      ..add(s.position.listen((Duration d) => _emit('position', d.inMilliseconds)))
      ..add(s.duration.listen((Duration d) {
        if (d > Duration.zero) _emit('duration', d.inMilliseconds);
      }))
      ..add(s.buffering.listen((bool b) => _emit('buffering', b)))
      ..add(s.playing.listen((bool b) => _emit('playing', b)))
      ..add(s.completed.listen((bool done) {
        if (done) _emit('ended', null);
      }))
      ..add(s.error.listen((String e) {
        BlackBox.instance.warn('PC', 'lecture : $e');
        _emit('error', e);
      }))
      ..add(s.width.listen((int? w) {
        if (!_firstFrame && w != null && w > 0) {
          _firstFrame = true;
          _emit('firstFrame', null);
        }
      }))
      ..add(s.subtitle.listen((List<String> lines) =>
          _emit('cues', lines.where((String l) => l.trim().isNotEmpty).join('\n'))))
      ..add(s.tracks.listen((_) => _publishTracks()))
      ..add(s.track.listen((_) => _publishTracks()));
  }

  void _emit(String event, Object? value) => _c?.applyBackendEvent(event, value);

  void _publishTracks() {
    final Tracks all = _player.state.tracks;
    final Track cur = _player.state.track;
    // « auto » et « no » sont des pseudo-pistes de mpv : on ne les liste pas.
    _audio = all.audio.where((AudioTrack t) => t.id != 'auto' && t.id != 'no').toList();
    _texts = all.subtitle.where((SubtitleTrack t) => t.id != 'auto' && t.id != 'no').toList();
    _emit('tracks', <Map<String, Object?>>[
      for (int i = 0; i < _audio.length; i++)
        <String, Object?>{
          'type': 'audio',
          'group': 0,
          'index': i,
          'language': _audio[i].language,
          'label': _audio[i].title,
          'channels': _audio[i].audiochannels ?? _audio[i].channelscount ?? 0,
          'selected': _audio[i].id == cur.audio.id,
        },
      for (int i = 0; i < _texts.length; i++)
        <String, Object?>{
          'type': 'text',
          'group': 1,
          'index': i,
          'language': _texts[i].language,
          'label': _texts[i].title,
          'channels': 0,
          'selected': _texts[i].id == cur.subtitle.id,
        },
    ]);
  }

  @override
  void open(Map<String, dynamic> args) {
    final String url = (args['url'] as String?) ?? '';
    if (url.isEmpty) return;
    _firstFrame = false;
    final int startMs = (args['startMs'] as num?)?.toInt() ?? 0;
    final String? prefAudio = args['preferredAudio'] as String?;
    final String? prefText = args['preferredText'] as String?;
    unawaited(() async {
      final PlatformPlayer? p = _player.platform;
      if (p is NativePlayer) {
        try {
          if (prefAudio != null) await p.setProperty('alang', prefAudio);
          if (prefText != null) await p.setProperty('slang', prefText);
        } catch (_) {}
      }
      await _player.open(
        Media(url, start: startMs > 0 ? Duration(milliseconds: startMs) : null),
        play: true,
      );
    }());
  }

  @override
  void play() => unawaited(_player.play());

  @override
  void pause() => unawaited(_player.pause());

  @override
  void seekTo(Duration position) => unawaited(_player.seek(position));

  @override
  void selectTrack(NativeTrack track) {
    if (track.isAudio) {
      if (track.index >= 0 && track.index < _audio.length) {
        unawaited(_player.setAudioTrack(_audio[track.index]));
      }
    } else if (track.index >= 0 && track.index < _texts.length) {
      unawaited(_player.setSubtitleTrack(_texts[track.index]));
    }
  }

  @override
  void disableSubtitles() => unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));

  @override
  Widget buildView(BuildContext context) => Video(
        controller: _video,
        // Aucune commande media_kit : ce sont celles de Zuno (mêmes que la box).
        controls: null,
        // Les sous-titres sont dessinés par l'app (même rendu que la box).
        subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
        // Ne jamais voler le focus clavier aux écrans de Zuno.
        focusNode: _noFocus,
        fill: Colors.black,
      );

  @override
  void dispose() {
    for (final StreamSubscription<Object?> s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _noFocus.dispose();
    unawaited(_player.dispose());
    _c = null;
  }
}
