// =========================================================
//  desktop_player_screen.dart — Lecteur plein écran WINDOWS (PC)
// =========================================================
//  Moteur = media_kit (libmpv), le MÊME que VLC / le mobile. Sur PC, le lecteur
//  natif Media3/ExoPlayer (packages/native_video_player) n'existe pas (il est
//  100 % Android) → on lit ici via libmpv, qui décode HLS / MPEG-TS / MP4 en
//  matériel et gère les flux IPTV instables (reconnexion auto, gros cache).
//
//  ⚠️ IMPORTANT pour le build Android TV : ce fichier importe media_kit. Il est
//  donc importé UNIQUEMENT par lib/main_windows.dart (qui appelle
//  registerTvPlayer pour l'injecter). Le build TV ne l'atteint JAMAIS → sa
//  fermeture de compilation reste sans media_kit (cf. tv_player_screen.dart).
//
//  Commandes (clavier, façon télécommande) :
//    Haut/Bas (ou Préc/Suiv média) = zap ; chiffres = n° de chaîne ;
//    OK/Entrée/Espace = barre de contrôle ; F = favori ; Échap/Retour = quitter.
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../channels/data/recently_watched_repository.dart';
import '../../../channels/domain/channel.dart';
import '../../../playlists/data/favorites_repository.dart';
import '../../../subscription/data/now_playing.dart';
import '../../../subscription/data/subscription_state.dart';
import '../../core/tv_dimens.dart';
import '../../core/tv_tokens.dart';
import '../tv_components.dart';

/// Lecteur Windows. Même contrat que TvPlayerScreen (liste + index de départ),
/// injecté via registerTvPlayer dans main_windows.dart.
class DesktopPlayerScreen extends StatefulWidget {
  const DesktopPlayerScreen({
    super.key,
    required this.channels,
    required this.startIndex,
  });

  final List<Channel> channels;
  final int startIndex;

  @override
  State<DesktopPlayerScreen> createState() => _DesktopPlayerScreenState();
}

class _DesktopPlayerScreenState extends State<DesktopPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  final FocusNode _focus = FocusNode();

  late int _index = widget.startIndex;
  bool _overlay = true;
  bool _buffering = true;
  bool _fatal = false;
  String _numBuffer = '';

  Timer? _hideTimer;
  Timer? _numTimer;
  Timer? _presenceTimer;

  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  // Favoris en direct (le ❤ se met à jour tout seul, comme sur TV).
  StreamSubscription<Set<String>>? _favSub;
  Set<String> _favIds = FavoritesRepository.instance.current;
  bool get _isFavorite => _favIds.contains(_current.id);

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
    _player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn),
    );
    _videoController = VideoController(_player);

    _subs.add(_player.stream.buffering.listen((bool b) {
      if (mounted) setState(() => _buffering = b);
    }));
    _subs.add(_player.stream.playing.listen((bool p) {
      if (mounted && p && (_buffering || _fatal)) {
        setState(() {
          _buffering = false;
          _fatal = false;
        });
      }
    }));
    _subs.add(_player.stream.error.listen((String e) {
      // libmpv crache beaucoup d'avertissements non fatals sur les flux IPTV.
      // On ne bascule en erreur QUE si rien ne joue (sinon on ignore).
      if (!mounted) return;
      if (_player.state.playing) return;
      final String lower = e.toLowerCase();
      const List<String> nonFatal = <String>[
        'force-seekable', 'demuxer', 'first-frame', 'underrun',
        'discontinuity', 'frame drop',
      ];
      if (nonFatal.any(lower.contains)) return;
      setState(() => _fatal = true);
    }));

    _favSub = FavoritesRepository.instance.favoritesStream.listen((Set<String> ids) {
      if (mounted) setState(() => _favIds = ids);
    });
    FavoritesRepository.instance.initialize();

    _applyMpvOptions();
    _open();

    // Présence : garde l'app « en ligne » + chaîne à jour pendant le visionnage.
    _presenceTimer = Timer.periodic(const Duration(minutes: 3),
        (_) => SubscriptionState.instance.syncWithBackend());
  }

  /// Options libmpv pour des flux IPTV robustes (reconnexion auto, gros cache,
  /// User-Agent type lecteur connu). Best-effort : aucune erreur ne bloque.
  Future<void> _applyMpvOptions() async {
    try {
      // ignore: invalid_use_of_protected_member
      final dynamic native = (_player.platform as dynamic);
      await native?.setProperty('cache', 'yes');
      await native?.setProperty('cache-secs', '30');
      await native?.setProperty('network-timeout', '60');
      await native?.setProperty('keep-open', 'yes');
      await native?.setProperty('user-agent', 'VLC/3.0.20 LibVLC/3.0.20');
      // Reconnexion FFmpeg automatique (le direct IPTV coupe souvent).
      await native?.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=30,'
            'reconnect_at_eof=1,reconnect_on_http_error=4xx,5xx,'
            'reconnect_on_network_error=1',
      );
      await native?.setProperty('demuxer-max-bytes', '201326592'); // 192 MiB
      await native?.setProperty('demuxer-readahead-secs', '20');
    } catch (_) {
      // libmpv non exposé : on garde les défauts.
    }
  }

  void _open() {
    if (mounted) {
      setState(() {
        _buffering = true;
        _fatal = false;
      });
    }
    _player.open(Media(_current.streamUrl));
    RecentlyWatchedRepository.instance.record(_current.id);
    NowPlaying.instance.set(_current.cleanName);
    SubscriptionState.instance.syncWithBackend();
    _showOverlayTemporarily();
  }

  void _zap(int delta) {
    final int n = widget.channels.length;
    if (n <= 1) return;
    setState(() => _index = (_index + delta) % n);
    _open();
  }

  void _retry() {
    setState(() {
      _fatal = false;
      _buffering = true;
    });
    _player.open(Media(_current.streamUrl));
    _showOverlayTemporarily();
  }

  void _toggleFavorite() {
    FavoritesRepository.instance.toggle(_current.id);
    _showOverlayTemporarily();
  }

  void _onDigit(int d) {
    if (_numBuffer.length < 4) _numBuffer += '$d';
    _numTimer?.cancel();
    _numTimer = Timer(const Duration(milliseconds: 1500), _jumpNumber);
    setState(() {});
  }

  void _jumpNumber() {
    final int? n = int.tryParse(_numBuffer);
    _numBuffer = '';
    if (n == null || n <= 0) {
      setState(() {});
      return;
    }
    setState(() => _index = (n - 1).clamp(0, widget.channels.length - 1));
    _open();
  }

  void _showOverlayTemporarily() {
    setState(() => _overlay = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _overlay = false);
    });
  }

  void _toggleOverlay() {
    setState(() => _overlay = !_overlay);
    if (_overlay) _showOverlayTemporarily();
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
      k == LogicalKeyboardKey.space;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;

    if (_fatal && _isOk(k)) {
      _retry();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.exit) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    int di = _digits.indexOf(k);
    if (di < 0) di = _numpad.indexOf(k);
    if (di >= 0) {
      _onDigit(di);
      return KeyEventResult.handled;
    }

    if (_isPrev(k)) {
      _zap(-1);
      return KeyEventResult.handled;
    }
    if (_isNext(k)) {
      _zap(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      _toggleFavorite();
      return KeyEventResult.handled;
    }
    if (_isOk(k)) {
      _toggleOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _numTimer?.cancel();
    _presenceTimer?.cancel();
    _favSub?.cancel();
    for (final StreamSubscription<dynamic> s in _subs) {
      s.cancel();
    }
    NowPlaying.instance.clear();
    SubscriptionState.instance.syncWithBackend();
    _player.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleOverlay,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Surface vidéo media_kit plein écran.
              Center(
                child: Video(
                  controller: _videoController,
                  fit: BoxFit.contain,
                  // Pas de contrôles media_kit : l'overlay TV (D-pad) gère tout.
                  // (builder typé plutôt que NoVideoControls : la constante est
                  // vue `dynamic` selon la version de media_kit_video → refusée
                  // par strict-casts.)
                  controls: (VideoState state) => const SizedBox.shrink(),
                ),
              ),
              // Écran de marque pendant l'ouverture / le zap.
              if (_buffering && !_fatal)
                const ColoredBox(
                  color: TvTokens.bg,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TvLogo(width: 200),
                        SizedBox(height: 28),
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: TvTokens.gold),
                        ),
                      ],
                    ),
                  ),
                ),
              // Écran d'erreur (flux injoignable) → « Réessayer ».
              if (_fatal)
                ColoredBox(
                  color: TvTokens.bg,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.error_outline_rounded,
                            color: TvTokens.mutedDim, size: 56),
                        const SizedBox(height: 16),
                        Text(_current.cleanName,
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: TvTokens.text)),
                        const SizedBox(height: 8),
                        Text(context.l10n.tvChannelUnavailable,
                            style: const TextStyle(
                                fontSize: 16, color: TvTokens.mutedDim)),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                          decoration: BoxDecoration(
                            color: TvTokens.sel,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: TvTokens.gold, width: 2),
                          ),
                          child: Text(context.l10n.playerDesktopRetryQuitHint,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: TvTokens.goldBright)),
                        ),
                      ],
                    ),
                  ),
                ),
              // Barre de lecture (info chaîne + favori).
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                  offset: _overlay ? Offset.zero : const Offset(0, 0.28),
                  duration: TvDimens.focusAnim,
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _overlay ? 1 : 0,
                    duration: TvDimens.focusAnim,
                    child: IgnorePointer(
                      ignoring: !_overlay,
                      child: _DesktopControls(
                        channel: _current,
                        index: _index,
                        total: widget.channels.length,
                        isFavorite: _isFavorite,
                        onFavorite: _toggleFavorite,
                      ),
                    ),
                  ),
                ),
              ),
              // Numéro saisi au clavier (coin haut-droit).
              if (_numBuffer.isNotEmpty)
                Positioned(
                  top: 24,
                  right: 24,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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

/// Barre de lecture sobre (Maison Noir) : logo + nom + DIRECT + n° + ❤ favori.
class _DesktopControls extends StatelessWidget {
  const _DesktopControls({
    required this.channel,
    required this.index,
    required this.total,
    required this.isFavorite,
    required this.onFavorite,
  });

  final Channel channel;
  final int index;
  final int total;
  final bool isFavorite;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Color(0xF2000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            height: 56,
            child: (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: channel.logoUrl!,
                    fit: BoxFit.contain,
                    memCacheWidth: 160,
                    placeholder: (_, __) => _initials(),
                    errorWidget: (_, __, ___) => _initials())
                : _initials(),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(channel.cleanName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: TvTokens.text)),
                const SizedBox(height: 6),
                Text(
                  channel.category.trim().isEmpty
                      ? context.l10n.tvOthers
                      : channel.category.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: TvTokens.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // ❤ Favori (souris : clic ; clavier : touche F).
          IconButton(
            onPressed: onFavorite,
            icon: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorite ? TvTokens.gold : TvTokens.text,
              size: 30,
            ),
            tooltip: context.l10n.playerFavoriteShortcutTooltip,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Text('${index + 1} / $total',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: TvTokens.text)),
          ),
        ],
      ),
    );
  }

  Widget _initials() => Center(
        child: Text(channel.initials,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: TvTokens.muted)),
      );
}
