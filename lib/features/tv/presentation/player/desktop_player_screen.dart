// =========================================================
//  desktop_player_screen.dart — Lecteur plein écran WINDOWS (PC)
// =========================================================
//  Moteur = media_kit (libmpv), le MÊME que VLC / le mobile. Sur PC, le lecteur
//  natif Media3/ExoPlayer (packages/native_video_player) n'existe pas (il est
//  100 % Android) → on lit ici via libmpv, qui décode HLS / MPEG-TS / MP4 en
//  matériel et gère les flux IPTV instables (reconnexion auto, gros cache).
//
// IMPORTANT pour le build Android TV : ce fichier importe media_kit. Il est
//  donc importé UNIQUEMENT par lib/main_windows.dart (qui appelle
//  registerTvPlayer pour l'injecter). Le build TV ne l'atteint JAMAIS → sa
//  fermeture de compilation reste sans media_kit (cf. tv_player_screen.dart).
//
//  Commandes (10/09/2026 — modèle Netflix : tout se cache tout seul) :
//    Espace / K / touches média = PAUSE  (Espace ne montre PLUS les infos :
//                                         sur un PC, Espace = pause partout)
//    Haut/Bas, Page↑/Page↓       = chaîne précédente / suivante
//    chiffres                    = numéro de chaîne
//    H, Entrée, ou un mouvement de souris = barre de contrôle
//    F = favori ; Échap/Retour = quitter
//
//  La barre s'efface seule après 3 s d'inactivité, ET LE CURSEUR AVEC :
//  une flèche blanche immobile au milieu d'un match, c'est ce qui fait
//  qu'un PC branché sur une télé ressemble à un PC.
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
// `PointerHoverEvent` : déclaré explicitement plutôt que supposé réexporté
// par material.dart. Le 09/09, exactement cette supposition sur
// `ValueListenable` a cassé la compilation des quatre builds.
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/curation/title_curator.dart';
import '../../../../core/i18n/l10n_extension.dart';
import '../../../channels/data/recently_watched_repository.dart';
import '../../../channels/domain/channel.dart';
import '../../../playlists/data/favorites_repository.dart';
import '../../../subscription/data/now_playing.dart';
import '../../../subscription/data/subscription_state.dart';
import '../../core/tv_dimens.dart';
import '../../core/tv_tokens.dart';
import '../tv_components.dart';
import 'player_progress.dart';

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

  /// Position dans le flux, pour la réglette de progression. Sur une
  /// chaîne en direct elle avance sans fin et la durée reste nulle : la
  /// barre affiche alors « DIRECT » au lieu d'une progression fausse
  /// (voir `player_progress.dart`).
  Duration _position = Duration.zero;
  Duration _duree = Duration.zero;

  /// Volume 0-100 (échelle de media_kit). Lu depuis le lecteur au
  /// démarrage pour que la réglette parte à la bonne valeur.
  double _volume = 100;
  bool _fatal = false;
  String _numBuffer = '';

  Timer? _hideTimer;
  Timer? _numTimer;
  Timer? _presenceTimer;

  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  // Favoris en direct (le se met à jour tout seul, comme sur TV).
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
      if (!mounted) return;
      if (p && (_buffering || _fatal)) {
        setState(() {
          _buffering = false;
          _fatal = false;
        });
        return;
      }
      // Redessiner à CHAQUE bascule lecture/pause, et pas seulement quand
      // ça repart : c'est ce qui fait apparaître et disparaître le symbole
      // de pause, y compris si la mise en pause vient d'ailleurs que du
      // clavier (touche multimédia captée par le système, par exemple).
      setState(() {});
    }));
    // Position et durée : la réglette de progression s'en nourrit. On ne
    // redessine QUE si la barre est visible — sinon on repeindrait
    // l'écran une fois par seconde pour rien, pendant des heures, sur une
    // machine qui décode déjà de la vidéo.
    _subs.add(_player.stream.position.listen((Duration p) {
      if (!mounted) return;
      _position = p;
      if (_overlay) setState(() {});
    }));
    _subs.add(_player.stream.duration.listen((Duration d) {
      if (mounted) setState(() => _duree = d);
    }));
    _subs.add(_player.stream.volume.listen((double v) {
      if (mounted) setState(() => _volume = v);
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

  //  TROIS SECONDES, et pas six (10/09/2026).
  //
  //  Le modèle demandé est celui de Netflix : « tout est pensé pour
  //  disparaître, l'écran reste propre comme une vraie télé ». Six
  //  secondes, c'est une barre qui traîne — on la voit encore alors qu'on
  //  a fini de s'en servir, et elle mange le bas de l'image.
  void _showOverlayTemporarily() {
    setState(() => _overlay = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      // La souris est POSÉE sur le bouton Retour : on ne referme pas.
      //
      // Sans cette exception, la cible s'effacerait sous le curseur au
      // moment où l'on va cliquer dessus. C'est le genre de détail qui
      // fait dire « ça ne marche pas » d'une chose qui marche.
      if (_surRetour) return;
      setState(() => _overlay = false);
    });
  }

  /// Vrai tant que le curseur repose sur le bouton Retour (voir ci-dessus).
  bool _surRetour = false;

  /// Mouvement de souris : on réveille la barre.
  ///
  /// GARDE-FOU CONTRE LE TREMBLEMENT. Une souris posée sur un bureau
  /// envoie des micro-mouvements en permanence (capteur optique, table
  /// qui vibre). Sans ce filtre, la barre ne se cacherait JAMAIS sur
  /// certains postes — exactement l'inverse du but recherché. On ne
  /// réagit donc qu'à un déplacement franc.
  static const double _seuilSouris = 3;
  Offset? _dernierePosSouris;

  void _onSouris(PointerHoverEvent e) {
    final Offset? avant = _dernierePosSouris;
    _dernierePosSouris = e.position;
    if (avant != null && (e.position - avant).distance < _seuilSouris) return;
    _showOverlayTemporarily();
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
  //  OK = valider / afficher les infos.
  //
  //  ESPACE N'EN FAIT PLUS PARTIE (10/09/2026). Signalé par le
  //  propriétaire : « l'app Windows n'a pas de pause ». Il avait raison,
  //  et le défaut était pire qu'une absence : la barre d'espace était
  //  branchée sur l'AFFICHAGE DES INFOS. Sur un PC, Espace veut dire
  //  pause pour tout le monde — VLC, YouTube, Netflix, le lecteur de
  //  Windows. On appuyait donc dessus en s'attendant à une pause, et on
  //  obtenait un bandeau. Entrée reste là pour valider.
  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter;

  /// Touches de PAUSE, dans l'ordre où un utilisateur les essaie.
  ///
  ///  - `Espace` : le réflexe universel sur ordinateur ;
  ///  - `K`      : celui de YouTube, connu de tous les habitués ;
  ///  - `mediaPlayPause` / `mediaPlay` / `mediaPause` : la touche dédiée
  ///    des claviers multimédia et des télécommandes USB — beaucoup de
  ///    mini-PC branchés sur une télé en ont une.
  bool _isPause(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.space ||
      k == LogicalKeyboardKey.keyK ||
      k == LogicalKeyboardKey.mediaPlayPause ||
      k == LogicalKeyboardKey.mediaPlay ||
      k == LogicalKeyboardKey.mediaPause;

  /// Met en pause ou reprend, et le MONTRE.
  ///
  /// Sur un flux en direct, une pause silencieuse est indiscernable d'un
  /// écran figé par le réseau : l'image s'arrête, et rien ne dit si c'est
  /// voulu. On force donc l'affichage du bandeau, qui porte l'icône de
  /// l'état en cours.
  Future<void> _togglePause() async {
    await _player.playOrPause();
    if (!mounted) return;
    setState(() {});
    _showOverlayTemporarily();
  }

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
    // AVANT `_isOk` : sans cet ordre, Espace serait de nouveau avalé par
    // l'affichage des infos et la pause resterait inatteignable.
    if (_isPause(k)) {
      unawaited(_togglePause());
      return KeyEventResult.handled;
    }
    // H : afficher/masquer la barre. C'est la convention des lecteurs de
    // bureau (VLC, Kodi, mpv) — celui qui la connaît la trouve sans qu'on
    // la lui explique, et celui qui l'ignore ne perd rien.
    if (k == LogicalKeyboardKey.keyH) {
      _toggleOverlay();
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
      //  LE GESTE DE NETFLIX : la barre surgit au mouvement de la souris,
      //  et TOUT disparaît ensuite — la barre ET LE CURSEUR.
      //
      //  Cacher le curseur n'est pas un détail de finition : une flèche
      //  blanche immobile au milieu d'un match, c'est ce qui fait qu'un
      //  PC branché sur une télé ressemble à un PC. C'est exactement la
      //  différence entre « une app » et « une fenêtre de navigateur ».
      child: MouseRegion(
        cursor: _overlay
            ? SystemMouseCursors.basic
            : SystemMouseCursors.none,
        onHover: _onSouris,
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
                          child: Text(
                              context.l10n.tvPlayerRetryQuitHintDesktop,
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
                        enLecture: _player.state.playing,
                        onPlayPause: () => unawaited(_togglePause()),
                        onPrecedent: () => _zap(-1),
                        onSuivant: () => _zap(1),
                        volume: _volume,
                        onVolume: (double v) {
                          // On garde la barre à l'écran pendant qu'on
                          // règle le son : elle se refermerait au milieu
                          // du geste, sinon.
                          _showOverlayTemporarily();
                          unawaited(_player.setVolume(v));
                        },
                        position: _position,
                        duree: _duree,
                      ),
                    ),
                  ),
                ),
              ),
              // PAUSE : un signe AU CENTRE, impossible à rater.
              //
              // Sur un flux en direct, une image arrêtée est ambiguë : le
              // spectateur ne peut pas savoir si c'est sa pause ou le
              // réseau qui a lâché. Ce symbole tranche la question sans
              // qu'il ait à toucher à quoi que ce soit. Il disparaît de
              // lui-même dès que ça repart.
              if (!_player.state.playing && !_buffering && !_fatal)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: const Icon(Icons.pause_rounded,
                        size: 64, color: Colors.white),
                  ),
                ),
              // ----- RETOUR : le bouton qu'une SOURIS peut atteindre -----
              //
              // Sur la box, la télécommande a sa touche Retour et tout le
              // monde la trouve. Sur un PC il n'y a pas de télécommande :
              // Échap fonctionne depuis toujours, mais personne ne devine
              // une touche qui ne s'affiche nulle part. Résultat mesuré :
              // on lance une chaîne et on est enfermé dedans — il ne reste
              // que la croix de la fenêtre, donc quitter l'application.
              //
              // Même place que chez Netflix : en haut à gauche, avec le
              // bandeau. Et il reste visible sur l'écran d'erreur MÊME
              // sans bandeau, parce que c'est précisément le moment où
              // l'on a vraiment besoin de sortir.
              Positioned(
                top: TvDimens.safeV,
                left: TvDimens.safeV,
                child: AnimatedOpacity(
                  opacity: (_overlay || _fatal) ? 1 : 0,
                  duration: TvDimens.focusAnim,
                  child: IgnorePointer(
                    ignoring: !(_overlay || _fatal),
                    child: _BoutonRetour(
                      libelle: context.l10n.buttonBack,
                      onTap: () => Navigator.of(context).maybePop(),
                      onSurvol: (bool dessus) {
                        _surRetour = dessus;
                        // En sortant, on réarme le compte à rebours : le
                        // minuteur précédent est mort pendant le survol.
                        if (!dessus) _showOverlayTemporarily();
                      },
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
      ),
    );
  }
}

/// Barre de lecture sobre (Maison Noir) : logo + nom + DIRECT + n° + favori.
class _DesktopControls extends StatelessWidget {
  const _DesktopControls({
    required this.channel,
    required this.index,
    required this.total,
    required this.isFavorite,
    required this.onFavorite,
    required this.enLecture,
    required this.onPlayPause,
    required this.onPrecedent,
    required this.onSuivant,
    required this.volume,
    required this.onVolume,
    required this.position,
    required this.duree,
  });

  final Channel channel;
  final int index;
  final int total;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final bool enLecture;
  final VoidCallback onPlayPause;
  final VoidCallback onPrecedent;
  final VoidCallback onSuivant;
  final double volume;
  final ValueChanged<double> onVolume;
  final Duration position;
  final Duration duree;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ----- RÉGLETTE DE PROGRESSION, tout en haut de la barre -----
          // En direct, une progression serait un mensonge : elle laisserait
          // croire qu'on peut revenir en arrière. On affiche donc le temps
          // écoulé et un repère « DIRECT » à la place.
          _Progression(position: position, duree: duree),
          const SizedBox(height: 10),
          Row(
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
                      : TitleCurator.curateCategory(channel.category.trim()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: TvTokens.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Favori (souris : clic ; clavier : touche F).
          IconButton(
            onPressed: onFavorite,
            icon: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorite ? TvTokens.gold : TvTokens.text,
              size: 30,
            ),
            tooltip: '${context.l10n.tvPlayerFavorite} (F)',
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
          const SizedBox(height: 8),
          // ----- LES COMMANDES, à la souris comme au clavier -----
          // Chaque bouton porte son raccourci dans son infobulle : c'est
          // ainsi qu'on apprend les touches sans lire de mode d'emploi.
          Row(
            children: <Widget>[
              _BoutonRond(
                icone: Icons.skip_previous_rounded,
                onTap: onPrecedent,
                info: 'Chaîne précédente (↑)',
              ),
              const SizedBox(width: 10),
              // Le plus gros bouton : c'est celui qu'on vise en premier,
              // et souvent sans regarder.
              _BoutonRond(
                icone: enLecture ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onTap: onPlayPause,
                info: enLecture ? 'Pause (Espace)' : 'Lecture (Espace)',
                grand: true,
              ),
              const SizedBox(width: 10),
              _BoutonRond(
                icone: Icons.skip_next_rounded,
                onTap: onSuivant,
                info: 'Chaîne suivante (↓)',
              ),
              const SizedBox(width: 22),
              // ----- VOLUME -----
              Icon(
                volume <= 0
                    ? Icons.volume_off_rounded
                    : (volume < 50
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded),
                color: TvTokens.text,
                size: 24,
              ),
              SizedBox(
                width: 150,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: TvTokens.gold,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: TvTokens.gold,
                  ),
                  child: Slider(
                    value: volume.clamp(0, 100),
                    max: 100,
                    onChanged: onVolume,
                  ),
                ),
              ),
              const Spacer(),
            ],
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

/// Bouton « Retour », en haut à gauche du lecteur PC.
///
/// Volontairement une pastille avec un MOT écrit dedans, pas une simple
/// flèche : une flèche seule se confond avec la décoration, et on ne clique
/// pas sur quelque chose dont on n'est pas sûr. Le raccourci clavier est
/// imprimé à côté — c'est ainsi qu'on apprend « Échap » sans lire de mode
/// d'emploi, exactement comme les infobulles de la barre du bas.
class _BoutonRetour extends StatefulWidget {
  const _BoutonRetour({
    required this.libelle,
    required this.onTap,
    required this.onSurvol,
  });

  final String libelle;
  final VoidCallback onTap;

  /// Prévient l'écran que le curseur entre (`true`) ou sort (`false`), pour
  /// qu'il ne referme pas le bandeau sous la souris.
  final ValueChanged<bool> onSurvol;

  @override
  State<_BoutonRetour> createState() => _BoutonRetourState();
}

class _BoutonRetourState extends State<_BoutonRetour> {
  bool _survol = false;

  void _maj(bool dessus) {
    setState(() => _survol = dessus);
    widget.onSurvol(dessus);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      // On force le curseur : le lecteur le cache quand le bandeau dort,
      // et une cible invisible ne se clique pas.
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _maj(true),
      onExit: (_) => _maj(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: TvDimens.focusAnim,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: _survol ? 0.85 : 0.55),
            borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
            border: Border.all(
              color: _survol ? TvTokens.gold : Colors.white24,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.arrow_back_rounded,
                  size: 24, color: _survol ? TvTokens.gold : TvTokens.text),
              const SizedBox(width: 10),
              Text(
                widget.libelle,
                style: TextStyle(
                  fontSize: TvDimens.body,
                  fontWeight: FontWeight.w800,
                  color: _survol ? TvTokens.gold : TvTokens.text,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Échap',
                style: TextStyle(
                  fontSize: TvDimens.caption,
                  fontWeight: FontWeight.w700,
                  color: TvTokens.mutedDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton rond de la barre de commandes.
///
/// Séparé plutôt que recopié cinq fois : sinon le jour où l'on change la
/// taille de frappe ou la couleur au survol, on la change à quatre
/// endroits sur cinq — et c'est le cinquième qu'on remarque.
class _BoutonRond extends StatelessWidget {
  const _BoutonRond({
    required this.icone,
    required this.onTap,
    required this.info,
    this.grand = false,
  });
  final IconData icone;
  final VoidCallback onTap;
  final String info;
  final bool grand;

  @override
  Widget build(BuildContext context) {
    final double taille = grand ? 56 : 44;
    return Tooltip(
      message: info,
      child: Material(
        color: Colors.white.withValues(alpha: grand ? 0.16 : 0.08),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: taille,
            height: taille,
            child: Icon(icone, color: TvTokens.text, size: grand ? 32 : 24),
          ),
        ),
      ),
    );
  }
}

/// Réglette de progression — ou repère « DIRECT ».
///
/// LA DISTINCTION EST LE POINT IMPORTANT. Une chaîne de télévision n'a pas
/// de fin : y dessiner une barre qui se remplit laisserait croire qu'on
/// peut revenir en arrière ou avancer. On montre donc le temps écoulé
/// depuis qu'on regarde, et un point rouge qui dit ce qu'on est en train
/// de faire. La règle vit dans `player_progress.dart`, testée à part.
class _Progression extends StatelessWidget {
  const _Progression({required this.position, required this.duree});
  final Duration position;
  final Duration duree;

  @override
  Widget build(BuildContext context) {
    if (estDirect(duree)) {
      return Row(
        children: <Widget>[
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text('DIRECT',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: TvTokens.text)),
          const SizedBox(width: 12),
          Text(formatDuree(position),
              style: const TextStyle(fontSize: 12, color: TvTokens.muted)),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Text(formatDuree(position),
            style: const TextStyle(fontSize: 12, color: TvTokens.muted)),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progression(position, duree),
              minHeight: 4,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(TvTokens.gold),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(formatDuree(duree),
            style: const TextStyle(fontSize: 12, color: TvTokens.muted)),
      ],
    );
  }
}
