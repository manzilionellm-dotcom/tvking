// =========================================================
//  tv_player_screen.dart — Lecteur plein écran TV (libVLC)
// =========================================================
//  Moteur = libVLC (flutter_vlc_player), PAS media_kit/mpv : sur certaines
//  box Android TV, mpv donnait « son sans image » (vidéo HEVC non rendue).
//  libVLC rend l'image via une TextureView fiable → image qui s'affiche.
//
//  Réglages stabilité :
//    1) HwAcc.auto : décodage matériel quand dispo (le 100 % logiciel + le
//       no-drop figeaient la box sur du HEVC), drop de trames AUTORISÉ ;
//    2) gros tampon (network/live/file caching = 3000 ms) ;
//    3) watchdog 15 s : aucune progression → reconnexion auto (ré-ouvre l'URL).
//
//  D-pad : Haut/Bas (ou Ch+/Ch-) = zap, chiffres = n° de chaîne, OK = barre,
//  Back = quitter. Logo « The Few » affiché à l'ouverture / au zap.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../subscription/data/now_playing.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import 'tv_components.dart';

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
  late final VlcPlayerController _controller;
  final FocusNode _focus = FocusNode();

  late int _index = widget.startIndex;
  bool _overlay = true;
  bool _buffering = true;
  Timer? _hideTimer;
  Timer? _presenceTimer;
  Timer? _numTimer;
  Timer? _watchdog;
  String _numBuffer = ''; // saisie d'un numéro de chaîne (touches 0-9)

  // Anti-gel : on suit la progression réelle (position qui avance).
  DateTime _lastProgress = DateTime.now();
  Duration _lastPos = Duration.zero;
  bool _recovering = false;
  static const Duration _frozen = Duration(seconds: 15);
  static const Duration _watchEvery = Duration(seconds: 4);

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

  // Options libVLC. On laisse libVLC choisir le décodage (HwAcc.auto :
  // matériel quand dispo, rendu via TextureView fiable) et on AUTORISE le
  // drop de trames (sinon une box trop lente fige tout sur du HEVC). Gros
  // tampon réseau pour limiter les coupures.
  static VlcPlayerOptions _vlcOptions() => VlcPlayerOptions(
        advanced: VlcAdvancedOptions(<String>[
          VlcAdvancedOptions.networkCaching(3000),
          VlcAdvancedOptions.liveCaching(3000),
          VlcAdvancedOptions.fileCaching(3000),
          VlcAdvancedOptions.clockJitter(0),
        ]),
        http: VlcHttpOptions(<String>[
          VlcHttpOptions.httpReconnect(true),
        ]),
      );

  @override
  void initState() {
    super.initState();
    _controller = VlcPlayerController.network(
      _current.streamUrl,
      hwAcc: HwAcc.auto, // matériel si dispo (rendu TextureView fiable côté libVLC)
      autoPlay: true,
      options: _vlcOptions(),
    );
    _controller.addListener(_onVlc);
    _open(reuse: true); // historique / présence pour la 1re chaîne
    // Chien de garde : aucune progression depuis 15 s → reconnexion.
    _watchdog = Timer.periodic(_watchEvery, (_) {
      if (!_recovering && DateTime.now().difference(_lastProgress) > _frozen) {
        _recover();
      }
    });
    // Garde l'app « en ligne » + chaîne à jour pendant le visionnage.
    _presenceTimer = Timer.periodic(const Duration(minutes: 3),
        (_) => SubscriptionState.instance.syncWithBackend());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _presenceTimer?.cancel();
    _numTimer?.cancel();
    _watchdog?.cancel();
    _controller.removeListener(_onVlc);
    NowPlaying.instance.clear();
    SubscriptionState.instance.syncWithBackend(); // on ne regarde plus rien
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Écoute l'état libVLC : progression (anti-gel), buffering (logo), erreurs.
  void _onVlc() {
    final VlcPlayerValue v = _controller.value;
    // Progression réelle → « pas gelé ».
    if (v.position != _lastPos) {
      _lastPos = v.position;
      _lastProgress = DateTime.now();
      _recovering = false;
    }
    final PlayingState st = v.playingState;
    final bool buffering = !v.isInitialized ||
        st == PlayingState.initializing ||
        st == PlayingState.buffering;
    if (mounted && buffering != _buffering) {
      setState(() => _buffering = buffering);
    }
    // Erreur / fin de flux live → reconnexion.
    if (v.hasError || st == PlayingState.error || st == PlayingState.ended) {
      _recover();
    }
  }

  void _open({bool reuse = false}) {
    _lastProgress = DateTime.now();
    _lastPos = Duration.zero;
    if (mounted) setState(() => _buffering = true);
    if (!reuse) {
      // Nouvelle chaîne → on charge la nouvelle URL dans le MÊME lecteur.
      _controller.setMediaFromNetwork(
        _current.streamUrl,
        hwAcc: HwAcc.auto,
        autoPlay: true,
      );
    }
    // Historique (reprise « Continuer à regarder », favoris, reco).
    RecentlyWatchedRepository.instance.record(_current.id);
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

  void _recover() {
    if (_recovering) return;
    _recovering = true;
    _lastProgress = DateTime.now();
    // Ré-ouvre la MÊME URL = reconnexion au direct.
    _controller
        .setMediaFromNetwork(_current.streamUrl,
            hwAcc: HwAcc.auto, autoPlay: true)
        .catchError((_) {});
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

  // Télécommandes universelles : toutes les variantes mènent à l'action.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;

    // BACK / Retour télécommande (toutes variantes) → quitter le lecteur,
    // retour à la liste. On gère explicitement pour ne jamais rester coincé.
    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.exit) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    int di = _digits.indexOf(k);
    if (di < 0) di = _numpad.indexOf(k);
    if (di >= 0) { _onDigit(di); return KeyEventResult.handled; }

    if (_isPrev(k)) { _zap(-1); return KeyEventResult.handled; }
    if (_isNext(k)) { _zap(1); return KeyEventResult.handled; }

    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
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
              // Vidéo libVLC plein écran (16:9 centré sur une TV 16:9).
              Center(
                child: VlcPlayer(
                  controller: _controller,
                  aspectRatio: 16 / 9,
                  placeholder: const ColoredBox(color: Colors.black),
                ),
              ),
              // Écran de marque pendant l'ouverture / le zap / une reconnexion.
              if (_buffering)
                const ColoredBox(
                  color: TvTokens.bg,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TvLogo(width: 200),
                        SizedBox(height: 28),
                        SizedBox(
                          width: 40, height: 40,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: TvTokens.gold),
                        ),
                      ],
                    ),
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
                      color: TvTokens.text),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    if (channel.isLive) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: TvTokens.live,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(context.l10n.tvLiveBadge,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      channel.category.trim().isEmpty
                          ? context.l10n.tvOthers
                          : channel.category.trim(),
                      style: TextStyle(
                          fontSize: TvDimens.label,
                          color: TvTokens.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(context.l10n.tvZapHint,
              style: TextStyle(
                  fontSize: TvDimens.caption, color: TvTokens.mutedDim)),
        ],
      ),
    );
  }

  Widget _initials(Channel c) => Center(
        child: Text(c.initials,
            style: TextStyle(
                fontSize: TvDimens.title,
                fontWeight: FontWeight.w800,
                color: TvTokens.muted)),
      );
}
