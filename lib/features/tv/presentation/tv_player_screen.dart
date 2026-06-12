// =========================================================
//  tv_player_screen.dart — Lecteur plein écran TV (§8 player_overlay)
// =========================================================
//  • Vidéo plein écran (moteur media_kit/mpv, réutilisé du mobile).
//  • Barre de chaînes en bas : logo + n° + nom (+ programme à venir),
//    AUTO-MASQUÉE après ~5 s d'inactivité (réapparaît à tout appui).
//  • D-pad : Haut/Bas (ou Ch+/Ch-) = zap, OK = afficher/masquer la barre,
//    Back = quitter.
//  • Reporte la chaîne en cours au panel (« En ligne → Regarde »).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme/app_colors.dart';
import '../../channels/domain/channel.dart';
import '../../subscription/data/now_playing.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';

class TvPlayerScreen extends StatefulWidget {
  const TvPlayerScreen({
    super.key,
    required this.channels,
    required this.startIndex,
  });

  /// Liste pour le zap (Haut/Bas) — généralement la catégorie courante.
  final List<Channel> channels;
  final int startIndex;

  @override
  State<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends State<TvPlayerScreen> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final FocusNode _focus = FocusNode();

  late int _index = widget.startIndex;
  bool _overlay = true;
  bool _buffering = true;
  Timer? _hideTimer;
  Timer? _presenceTimer;
  StreamSubscription<bool>? _bufSub;

  Channel get _current => widget.channels[_index];

  @override
  void initState() {
    super.initState();
    _bufSub = _player.stream.buffering.listen((bool b) {
      if (mounted) setState(() => _buffering = b);
    });
    _open();
    // Garde l'app « en ligne » + chaîne à jour pendant le visionnage.
    _presenceTimer = Timer.periodic(const Duration(minutes: 3),
        (_) => SubscriptionState.instance.syncWithBackend());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _presenceTimer?.cancel();
    _bufSub?.cancel();
    NowPlaying.instance.clear();
    SubscriptionState.instance.syncWithBackend(); // on ne regarde plus rien
    _player.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open() {
    setState(() => _buffering = true);
    _player.open(Media(_current.streamUrl));
    // Rapporte la chaîne au panel.
    NowPlaying.instance.set(_current.cleanName);
    SubscriptionState.instance.syncWithBackend();
    _showOverlayTemporarily();
  }

  void _zap(int delta) {
    final int n = widget.channels.length;
    if (n <= 1) return;
    setState(() => _index = (_index + delta) % n);
    if (_index < 0) _index += n;
    _open();
  }

  void _showOverlayTemporarily() {
    setState(() => _overlay = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _overlay = false);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;

    if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.channelUp) {
      _zap(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.channelDown) {
      _zap(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.gameButtonA) {
      setState(() => _overlay = !_overlay);
      if (_overlay) _showOverlayTemporarily();
      return KeyEventResult.handled;
    }
    // Tout autre appui réveille la barre.
    _showOverlayTemporarily();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Video(controller: _video, controls: NoVideoControls),
              if (_buffering)
                const Center(
                  child: SizedBox(
                    width: 56, height: 56,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              // Barre de chaînes (auto-masquée).
              AnimatedOpacity(
                opacity: _overlay ? 1 : 0,
                duration: TvDimens.focusAnim,
                child: IgnorePointer(
                  ignoring: !_overlay,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _ChannelBar(channel: _current, index: _index),
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

class _ChannelBar extends StatelessWidget {
  const _ChannelBar({required this.channel, required this.index});
  final Channel channel;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          TvDimens.safeH, 20, TvDimens.safeH, TvDimens.safeV + 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Color(0xE6000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: <Widget>[
          // Logo
          SizedBox(
            width: 64, height: 64,
            child: (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                ? Image.network(channel.logoUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _initials(channel))
                : _initials(channel),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  channel.cleanName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: TvDimens.headline,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    if (channel.isLive) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.live,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('DIRECT',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      channel.prettyCategory,
                      style: TextStyle(
                          fontSize: TvDimens.label,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text('Haut/Bas pour zapper',
              style: TextStyle(
                  fontSize: TvDimens.caption, color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  Widget _initials(Channel c) => Center(
        child: Text(c.initials,
            style: TextStyle(
                fontSize: TvDimens.title,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary)),
      );
}
