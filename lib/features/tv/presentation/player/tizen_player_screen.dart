// =========================================================
//  tizen_player_screen.dart — Lecteur plein écran SAMSUNG TV (Tizen)
// =========================================================
//  Moteur = video_player_avplay (AVPlay / PlusPlayer natif Samsung). C'est LE
//  lecteur recommandé par flutter-tizen pour la TV : décodage matériel, et
//  surtout streaming ADAPTATIF natif (HLS / MPEG-DASH / MPEG-TS) — exactement
//  ce qu'il faut pour l'IPTV. Ni media_kit (pas de backend Tizen), ni le lecteur
//  Media3/ExoPlayer (100 % Android).
//
// IMPORTANT pour les autres builds : ce fichier importe video_player_avplay,
//  un paquet présent UNIQUEMENT dans le build Tizen (injecté par le workflow CI).
//  Il n'est importé QUE par lib/main_tizen.dart → les builds Android et Windows
//  ne l'atteignent jamais (il n'est pas dans leur fermeture de compilation).
//
//  Commandes (télécommande Samsung) :
//    Haut/Bas (ou Ch+/Ch-) = zap ; chiffres = n° de chaîne ; OK = barre ;
//    Retour = quitter.
// =========================================================
import 'dart:async';
import 'dart:math' show Random;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_avplay/video_player.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../channels/data/recently_watched_repository.dart';
import '../../../channels/domain/channel.dart';
import '../../../playlists/data/favorites_repository.dart';
import '../../../subscription/data/now_playing.dart';
import '../../../subscription/data/subscription_state.dart';
import '../../core/tv_dimens.dart';
import '../../core/tv_tokens.dart';
import '../tv_components.dart';

/// Lecteur Samsung TV. Même contrat que TvPlayerScreen (liste + index de
/// départ), injecté via registerTvPlayer dans main_tizen.dart.
class TizenPlayerScreen extends StatefulWidget {
  const TizenPlayerScreen({
    super.key,
    required this.channels,
    required this.startIndex,
  });

  final List<Channel> channels;
  final int startIndex;

  @override
  State<TizenPlayerScreen> createState() => _TizenPlayerScreenState();
}

class _TizenPlayerScreenState extends State<TizenPlayerScreen> {
  VideoPlayerController? _controller;
  final FocusNode _focus = FocusNode();

  late int _index = widget.startIndex;
  bool _overlay = true;
  bool _buffering = true;
  bool _fatal = false;
  String _numBuffer = '';

  Timer? _hideTimer;
  Timer? _numTimer;
  Timer? _presenceTimer;

  // =====================================================================
  //  RECONNEXION AUTOMATIQUE (parité avec la « forteresse » Android TV).
  //  Avant : la MOINDRE erreur AVPlay affichait l'écran « Réessayer » et
  //  attendait que le CLIENT appuie sur OK. Désormais : jusqu'à 3 relances
  //  SILENCIEUSES avec back-off + jitter (0,5 → 1 → 2 s ±25 %) — le client
  //  ne voit que « chargement ». L'écran fatal (OK = réessayer) ne reste
  //  que comme FILET après épuisement du budget. Le jitter évite que
  //  toutes les TV Samsung qui perdent le même serveur re-frappent au
  //  même instant (thundering herd).
  //  + CHIEN DE GARDE : AVPlay peut rester « buffering » sans fin sans
  //  jamais lever d'erreur (flux gelé) → 15 s de chargement continu sur
  //  une ouverture = traité comme une erreur (relance silencieuse).
  // =====================================================================
  static const int _maxSilentRetries = 3;
  int _silentRetries = 0;
  Timer? _retryTimer;
  Timer? _stuckTimer;
  final Random _rng = Random();

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
    _favSub = FavoritesRepository.instance.favoritesStream.listen((Set<String> ids) {
      if (mounted) setState(() => _favIds = ids);
    });
    FavoritesRepository.instance.initialize();
    _open();
    _presenceTimer = Timer.periodic(const Duration(minutes: 3),
        (_) => SubscriptionState.instance.syncWithBackend());
  }

  Future<void> _open() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _stuckTimer?.cancel();
    if (mounted) {
      setState(() {
        _buffering = true;
        _fatal = false;
      });
    }
    // On détruit l'ancien lecteur AVANT d'en ouvrir un nouveau (1 décodeur).
    final VideoPlayerController? old = _controller;
    _controller = null;
    await old?.dispose();

    final VideoPlayerController c =
        VideoPlayerController.network(_current.streamUrl);
    _controller = c;
    c.addListener(_onPlayer);
    try {
      await c.initialize();
      if (!mounted) return;
      await c.play();
      setState(() => _buffering = false);
      _silentRetries = 0; // lecture partie → budget de relance rechargé
    } catch (_) {
      _onPlaybackError();
      return;
    }
    // Chien de garde : toujours en chargement 15 s après l'ouverture
    // (AVPlay gelé sans erreur) → relance silencieuse.
    _stuckTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _buffering && !_fatal) _onPlaybackError();
    });

    RecentlyWatchedRepository.instance.record(_current.id);
    NowPlaying.instance.set(_current.cleanName);
    SubscriptionState.instance.syncWithBackend();
    _showOverlayTemporarily();
  }

  void _onPlayer() {
    final VideoPlayerController? c = _controller;
    if (c == null || !mounted) return;
    final VideoPlayerValue v = c.value;
    final bool buffering = v.isBuffering || !v.isInitialized;
    if (buffering != _buffering) setState(() => _buffering = buffering);
    if (!buffering && !v.hasError) {
      // Image à l'écran : le chien de garde n'a plus lieu d'être et le
      // budget de relance se recharge (les erreurs passées sont pardonnées).
      _stuckTimer?.cancel();
      _silentRetries = 0;
    }
    // Une relance à la fois : si un back-off est déjà programmé
    // (_retryTimer non nul), les hasError répétés du même incident
    // n'empilent pas de relances.
    if (v.hasError && !_fatal && _retryTimer == null) _onPlaybackError();
  }

  /// Erreur ou gel du lecteur : relance SILENCIEUSE avec back-off + jitter
  /// tant qu'il reste du budget, sinon écran fatal (OK = réessayer).
  void _onPlaybackError() {
    if (!mounted || _fatal) return;
    if (_silentRetries < _maxSilentRetries) {
      _silentRetries++;
      final int base = 500 * (1 << (_silentRetries - 1));
      final int jittered = (base * (0.75 + _rng.nextDouble() * 0.5)).round();
      setState(() {
        _buffering = true;
        _fatal = false;
      });
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(milliseconds: jittered), () {
        _retryTimer = null;
        if (mounted) _open();
      });
    } else {
      setState(() => _fatal = true);
    }
  }

  void _zap(int delta) {
    final int n = widget.channels.length;
    if (n <= 1) return;
    _silentRetries = 0; // nouvelle chaîne = budget de relance neuf
    setState(() => _index = (_index + delta) % n);
    _open();
  }

  void _retry() {
    _silentRetries = 0; // relance MANUELLE : le client a droit à un cycle complet
    setState(() {
      _fatal = false;
      _buffering = true;
    });
    _open();
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
    _silentRetries = 0; // nouvelle chaîne = budget de relance neuf
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
    _retryTimer?.cancel();
    _stuckTimer?.cancel();
    _favSub?.cancel();
    _controller?.removeListener(_onPlayer);
    _controller?.dispose();
    NowPlaying.instance.clear();
    SubscriptionState.instance.syncWithBackend();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? c = _controller;
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
              if (c != null && c.value.isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio == 0
                        ? 16 / 9
                        : c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
                ),
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
                          child: Text(
                              context.l10n.tvRetryQuitHint,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: TvTokens.goldBright)),
                        ),
                      ],
                    ),
                  ),
                ),
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
                      child: _TizenControls(
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

/// Barre de lecture sobre (Maison Noir) : logo + nom + catégorie + n° + .
class _TizenControls extends StatelessWidget {
  const _TizenControls({
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
                    // Même fade que tv_player_screen (150 ms) — revue V1.
                    fadeInDuration: const Duration(milliseconds: 150),
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
          IconButton(
            onPressed: onFavorite,
            icon: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorite ? TvTokens.gold : TvTokens.text,
              size: 30,
            ),
            tooltip: context.l10n.tvPlayerFavorite,
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
