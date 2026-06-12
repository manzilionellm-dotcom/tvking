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
  Timer? _numTimer;
  String _numBuffer = ''; // saisie d'un numéro de chaîne (touches 0-9)
  StreamSubscription<bool>? _bufSub;

  Channel get _current => widget.channels[_index];

  static const List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static const List<LogicalKeyboardKey> _numpad = <LogicalKeyboardKey>[
    LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

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
    _numTimer?.cancel();
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

  // ----- Saisie d'un numéro de chaîne (0-9) → zap après ~1,5 s -----
  void _onDigit(int d) {
    if (_numBuffer.length < 4) _numBuffer += '$d';
    _numTimer?.cancel();
    _numTimer = Timer(const Duration(milliseconds: 1500), _jumpNumber);
    setState(() {});
  }

  void _jumpNumber() {
    final int? n = int.tryParse(_numBuffer);
    _numBuffer = '';
    if (n == null || n <= 0) { setState(() {}); return; }
    setState(() => _index = (n - 1).clamp(0, widget.channels.length - 1));
    _open();
  }

  bool _isPrev(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.channelUp ||
      k == LogicalKeyboardKey.pageUp ||
      k == LogicalKeyboardKey.mediaTrackPrevious;
  bool _isNext(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowDown ||
      k == LogicalKeyboardKey.channelDown ||
      k == LogicalKeyboardKey.pageDown ||
      k == LogicalKeyboardKey.mediaTrackNext;
  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA ||
      k == LogicalKeyboardKey.contextMenu ||
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight;

  // Gestion UNIVERSELLE des télécommandes (Android TV, Fire TV, box,
  // télécommandes universelles) : toutes les variantes de touches mènent
  // à l'action attendue.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;

    // Chiffres (clavier + pavé numérique).
    int di = _digits.indexOf(k);
    if (di < 0) di = _numpad.indexOf(k);
    if (di >= 0) { _onDigit(di); return KeyEventResult.handled; }

    if (_isPrev(k)) { _zap(-1); return KeyEventResult.handled; }
    if (_isNext(k)) { _zap(1); return KeyEventResult.handled; }

    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      _player.playOrPause();
      _showOverlayTemporarily();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaStop) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (_isOk(k)) {
      setState(() => _overlay = !_overlay);
      if (_overlay) _showOverlayTemporarily();
      return KeyEventResult.handled;
    }
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
              // Numéro saisi à la télécommande (coin haut-droit).
              if (_numBuffer.isNotEmpty)
                Positioned(
                  top: TvDimens.safeV + 8,
                  right: TvDimens.safeH,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(_numBuffer,
                        style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 4)),
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
                      channel.category.trim().isEmpty ? 'Autres' : channel.category.trim(),
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
