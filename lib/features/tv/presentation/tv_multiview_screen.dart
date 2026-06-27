// =========================================================
//  tv_multiview_screen.dart — Multi-vue 2 chaînes (sport)
// =========================================================
//  Affiche DEUX chaînes côte à côte (chacune son propre lecteur ExoPlayer).
//  ◀ ▶ : change la tuile ACTIVE (celle qui a le SON ; l'autre est muette).
//  OK  : ouvre la tuile active en plein écran. Retour : ferme la multi-vue.
//
//  ANTI-OOM / STABILITÉ : décoder 2 flux HD simultanément demande du matériel.
//  On RÉSERVE donc la multi-vue aux box assez puissantes (RAM ≥ ~2 Go, hors
//  mode « low RAM ») — sur une petite box (type Fire Stick 1 Go), on n'essaie
//  même pas (message clair) plutôt que de risquer un plantage. C'est cohérent
//  avec la promesse « ça ne crashe jamais ».
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:native_video_player/native_video_player.dart';

import '../../../core/app/device_memory.dart';
import '../../channels/domain/channel.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_player_screen.dart';

/// Vrai si la box est jugée assez puissante pour 2 flux simultanés.
bool multiViewSupported() =>
    DeviceMemory.isLoaded &&
    !DeviceMemory.lowRam &&
    DeviceMemory.totalMb >= 2048;

class TvMultiViewScreen extends StatefulWidget {
  const TvMultiViewScreen({
    required this.channels,
    required this.startIndex,
    super.key,
  });

  final List<Channel> channels;
  final int startIndex;

  @override
  State<TvMultiViewScreen> createState() => _TvMultiViewScreenState();
}

class _TvMultiViewScreenState extends State<TvMultiViewScreen> {
  final FocusNode _focus = FocusNode();
  late final List<Channel> _two;
  late final List<NativeVideoController> _ctrl;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    final int n = widget.channels.length;
    final Channel a = widget.channels[widget.startIndex.clamp(0, n - 1)];
    final Channel b = widget.channels[(widget.startIndex + 1) % n];
    _two = <Channel>[a, b];
    _ctrl = <NativeVideoController>[
      NativeVideoController(initialUrl: a.streamUrl),
      NativeVideoController(initialUrl: b.streamUrl),
    ];
    // La tuile 1 (droite) démarre MUETTE : une seule source audio à la fois.
    _ctrl[1].setVolume(0);
  }

  @override
  void dispose() {
    for (final NativeVideoController c in _ctrl) {
      c.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  void _setActive(int i) {
    if (i == _active) return;
    setState(() => _active = i);
    for (int k = 0; k < _ctrl.length; k++) {
      _ctrl[k].setVolume(k == i ? 1.0 : 0.0);
    }
  }

  void _fullscreenActive() {
    // Ouvre la tuile active en plein écran (lecteur normal). On quitte la
    // multi-vue pour libérer le 2e décodeur.
    final Channel ch = _two[_active];
    final int idx = widget.channels.indexOf(ch);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(
          channels: widget.channels,
          startIndex: idx < 0 ? 0 : idx,
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _setActive(0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _setActive(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.gameButtonA) {
      _fullscreenActive();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Row(
          children: <Widget>[
            Expanded(child: _tile(0)),
            const SizedBox(width: 4),
            Expanded(child: _tile(1)),
          ],
        ),
      ),
    );
  }

  Widget _tile(int i) {
    final bool active = i == _active;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        NativeVideoView(controller: _ctrl[i]),
        // Cadre or sur la tuile active (celle qui a le son).
        IgnorePointer(
          child: AnimatedContainer(
            duration: TvDimens.focusAnim,
            decoration: BoxDecoration(
              border: Border.all(
                color: active ? TvTokens.gold : Colors.transparent,
                width: 3,
              ),
            ),
          ),
        ),
        // Bandeau nom + pastille son.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xB3000000),
            child: Row(
              children: <Widget>[
                Icon(active ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    size: 16,
                    color: active ? TvTokens.gold : TvTokens.mutedDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _two[i].cleanName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.label,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
