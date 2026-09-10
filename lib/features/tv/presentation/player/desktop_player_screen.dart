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
//    Gauche/Droite               = reculer / avancer de 10 s  (films seuls)
//    clic ou glisser sur la réglette = se rendre à cet endroit (films seuls)
//    chiffres                    = numéro de chaîne
//    H, Entrée, ou un mouvement de souris = barre de contrôle
//    F11 ou double-clic         = plein écran (couvre tout, comme une télé)
//    F = favori ; Échap/Retour = quitter le plein écran, puis la chaîne
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
import 'desktop_fullscreen.dart';
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

    // On DEMANDE son état à la fenêtre au lieu de supposer « pas en plein
    // écran » : si le client était déjà en plein écran sur l'écran d'avant,
    // le bouton doit s'ouvrir avec la bonne icône, pas avec l'inverse.
    unawaited(DesktopFullscreen.actif().then((bool a) {
      if (mounted) setState(() => _pleinEcran = a);
    }));

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
      // Un geste est en cours : on ne referme pas.
      //
      // Sans cette exception, la cible s'effacerait sous le curseur au
      // moment où l'on va cliquer dessus, ou la réglette s'évanouirait au
      // milieu d'un déplacement. C'est le genre de détail qui fait dire
      // « ça ne marche pas » d'une chose qui marche.
      if (_bandeauRetenu) return;
      setState(() => _overlay = false);
    });
  }

  /// Le curseur repose sur le bouton Retour.
  bool _surRetour = false;

  /// On tient la poignée de la réglette de progression.
  bool _enDeplacement = false;

  /// Vrai tant qu'un geste en cours doit garder le bandeau ouvert.
  bool get _bandeauRetenu => _surRetour || _enDeplacement;

  /// Se rendre à un endroit précis du film.
  ///
  /// Borné des deux côtés : libmpv accepte une position négative ou
  /// au-delà de la fin, et se met alors dans un état dont il ne revient
  /// pas toujours. Le clic sur la toute fin de la réglette est le cas
  /// qu'on rencontre pour de vrai.
  Future<void> _allerA(Duration cible) async {
    if (estDirect(_duree)) return; // Le direct ne se rembobine pas.
    final Duration borne = positionApresSaut(cible, _duree, 0);
    _position = borne; // Réponse immédiate à l'écran, avant libmpv.
    setState(() {});
    _showOverlayTemporarily();
    try {
      await _player.seek(borne);
    } catch (_) {
      // Flux non repositionnable : on ne casse pas la lecture pour ça.
    }
  }

  /// Avancer / reculer de quelques secondes (flèches ← →, boutons ±10 s).
  void _sauter(int secondes) =>
      unawaited(_allerA(positionApresSaut(_position, _duree, secondes)));

  // ----- PLEIN ÉCRAN -----
  //
  // L'état est gardé ici plutôt que relu à chaque image : interroger la
  // fenêtre native est un aller-retour asynchrone, et on redessine cette
  // barre plusieurs fois par seconde. On le resynchronise à chaque
  // bascule, à partir de ce que la fenêtre a VRAIMENT fait.
  bool _pleinEcran = false;

  Future<void> _basculerPleinEcran() async {
    final bool desormais = await DesktopFullscreen.basculer();
    if (!mounted) return;
    setState(() => _pleinEcran = desormais);
    _showOverlayTemporarily();
  }

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
    // F11 : le plein écran, comme dans tous les navigateurs et tous les
    // lecteurs du monde PC. Celui qui connaît la touche la trouve sans
    // qu'on la lui explique.
    if (k == LogicalKeyboardKey.f11) {
      unawaited(_basculerPleinEcran());
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.exit) {
      // ÉCHAP SORT D'ABORD DU PLEIN ÉCRAN, et seulement ensuite de la
      // chaîne. C'est la convention partout, et surtout c'est ce qui évite
      // la panique : en plein écran il n'y a plus ni barre de titre ni
      // croix, et le réflexe universel quand on s'y sent coincé est
      // d'appuyer sur Échap. Si cette touche quittait le lecteur d'un coup
      // en laissant la fenêtre étalée sur l'écran, on se croirait bloqué.
      if (_pleinEcran) {
        unawaited(_basculerPleinEcran());
        return KeyEventResult.handled;
      }
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    int di = _digits.indexOf(k);
    if (di < 0) di = _numpad.indexOf(k);
    if (di >= 0) {
      _onDigit(di);
      return KeyEventResult.handled;
    }

    // ← → : reculer / avancer de 10 s, comme partout ailleurs sur un PC.
    //
    // AVANT le zapping : sur un film, Haut/Bas ne mènent nulle part (il n'y
    // a qu'un seul « canal »), tandis que Gauche/Droite est le geste que
    // tout le monde fait sans y penser. En direct, la fonction n'existe
    // pas et la touche retombe sur le comportement normal.
    if (!estDirect(_duree)) {
      if (k == LogicalKeyboardKey.arrowLeft) {
        _sauter(-10);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        _sauter(10);
        return KeyEventResult.handled;
      }
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
    // On rend sa fenêtre au client en quittant la chaîne. Se retrouver dans
    // un menu qui occupe encore tout l'écran, sans barre de titre ni croix
    // de fermeture, c'est se sentir enfermé dans son propre ordinateur.
    unawaited(DesktopFullscreen.quitter());
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
        // DOUBLE-CLIC = PLEIN ÉCRAN. C'est le geste que tout le monde fait
        // déjà sur YouTube, VLC et Netflix, sans y penser et sans l'avoir
        // appris. Il coûte un délai de ~300 ms au simple clic (Flutter doit
        // attendre l'éventuel second) — sans conséquence ici : la barre
        // apparaît déjà toute seule au moindre mouvement de souris.
        onDoubleTap: () => unawaited(_basculerPleinEcran()),
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
                        pleinEcran: _pleinEcran,
                        onPleinEcran: () => unawaited(_basculerPleinEcran()),
                        onAllerA: (Duration d) => unawaited(_allerA(d)),
                        onReculer: () => _sauter(-10),
                        onAvancer: () => _sauter(10),
                        onDeplacement: (bool encours) {
                          _enDeplacement = encours;
                          // En lâchant, on réarme le compte à rebours : le
                          // minuteur précédent est mort pendant le geste.
                          if (!encours) _showOverlayTemporarily();
                        },
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
    required this.onAllerA,
    required this.onReculer,
    required this.onAvancer,
    required this.onDeplacement,
    required this.pleinEcran,
    required this.onPleinEcran,
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
  final ValueChanged<Duration> onAllerA;
  final VoidCallback onReculer;
  final VoidCallback onAvancer;
  final ValueChanged<bool> onDeplacement;
  final bool pleinEcran;
  final VoidCallback onPleinEcran;

  @override
  Widget build(BuildContext context) {
    // Deux capacités indépendantes (voir le pavé plus bas) : on zappe s'il
    // y a plusieurs chaînes, on se déplace si le flux annonce une durée.
    final bool peutZapper = total > 1;
    final bool peutSeDeplacer = !estDirect(duree);
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
          _Progression(
            position: position,
            duree: duree,
            onAllerA: onAllerA,
            onDeplacement: onDeplacement,
          ),
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
              // DEUX QUESTIONS SÉPARÉES, ET C'EST TOUT L'ENJEU (10/09/2026).
              //
              // « Peut-on zapper ? » et « peut-on se déplacer ? » n'ont rien
              // à voir l'une avec l'autre, et une première version les avait
              // confondues : elle remplaçait le zapping par les ±10 s dès
              // que le flux annonçait une durée. Photo à l'appui, TNT Sports
              // 7/19 en direct : le flux annonçait 1:05 de tampon glissant,
              // donc les boutons de chaîne AVAIENT DISPARU sur une liste de
              // dix-neuf chaînes.
              //
              // On zappe s'il y a plus d'une chaîne. On se déplace si le
              // flux le permet. Sur un match en direct avec du tampon, les
              // deux sont vrais — et c'est très bien : on revoit le but,
              // puis on zappe.
              if (peutZapper) ...<Widget>[
                _BoutonRond(
                  icone: Icons.skip_previous_rounded,
                  onTap: onPrecedent,
                  info: 'Chaîne précédente (↑)',
                ),
                const SizedBox(width: 10),
              ],
              if (peutSeDeplacer) ...<Widget>[
                _BoutonRond(
                  icone: Icons.replay_10_rounded,
                  onTap: onReculer,
                  info: 'Reculer de 10 s (←)',
                ),
                const SizedBox(width: 10),
              ],
              // Le plus gros bouton : c'est celui qu'on vise en premier,
              // et souvent sans regarder.
              _BoutonRond(
                icone: enLecture ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onTap: onPlayPause,
                info: enLecture ? 'Pause (Espace)' : 'Lecture (Espace)',
                grand: true,
              ),
              if (peutSeDeplacer) ...<Widget>[
                const SizedBox(width: 10),
                _BoutonRond(
                  icone: Icons.forward_10_rounded,
                  onTap: onAvancer,
                  info: 'Avancer de 10 s (→)',
                ),
              ],
              if (peutZapper) ...<Widget>[
                const SizedBox(width: 10),
                _BoutonRond(
                  icone: Icons.skip_next_rounded,
                  onTap: onSuivant,
                  info: 'Chaîne suivante (↓)',
                ),
              ],
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
              // ----- PLEIN ÉCRAN, tout à droite -----
              // C'est sa place chez YouTube, chez VLC et chez Netflix. On
              // ne la choisit pas par imitation : c'est le coin où la main
              // va le chercher sans réfléchir, parce qu'elle l'y a trouvé
              // partout ailleurs.
              _BoutonRond(
                icone: pleinEcran
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                onTap: onPleinEcran,
                info: pleinEcran
                    ? 'Quitter le plein écran (F11 ou Échap)'
                    : 'Plein écran (F11 ou double-clic)',
              ),
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
/// (10/09/2026) ELLE SE MANIPULE À LA SOURIS.
///
/// Jusqu'ici c'était un `LinearProgressIndicator` : un dessin, rien de
/// plus. On voyait où l'on en était dans un film, et on ne pouvait pas s'y
/// déplacer — il fallait tout regarder d'affilée. Le propriétaire l'a
/// résumé en une phrase : « je pense que c'est conçu pour tactile ».
/// C'était pire que ça : ça n'était conçu pour rien.
class _Progression extends StatefulWidget {
  const _Progression({
    required this.position,
    required this.duree,
    required this.onAllerA,
    required this.onDeplacement,
  });

  final Duration position;
  final Duration duree;

  /// Se rendre à cet endroit du film.
  final ValueChanged<Duration> onAllerA;

  /// Prévient l'écran qu'un geste commence (`true`) ou finit (`false`),
  /// pour qu'il ne referme pas le bandeau au milieu du déplacement.
  final ValueChanged<bool> onDeplacement;

  @override
  State<_Progression> createState() => _ProgressionState();
}

class _ProgressionState extends State<_Progression> {
  /// Position visée pendant qu'on tient la poignée, en 0..1.
  ///
  /// Tant qu'on déplace, c'est ELLE qu'on affiche et pas la position
  /// réelle : sinon la poignée reviendrait en arrière sous le doigt à
  /// chaque battement du lecteur, une seconde sur deux.
  double? _vise;

  bool _survol = false;

  Duration get _cible => positionDepuisRatio(_vise!, widget.duree);

  void _debut(double dx, double largeur) {
    widget.onDeplacement(true);
    setState(() => _vise = ratioDepuisX(dx, largeur));
  }

  void _pendant(double dx, double largeur) =>
      setState(() => _vise = ratioDepuisX(dx, largeur));

  void _fin() {
    // On ne demande le saut qu'au RELÂCHEMENT, jamais pendant le geste.
    // Un saut par pixel parcouru, c'est des dizaines de requêtes à libmpv
    // en une seconde : l'image se fige et le son hachure. C'est aussi ce
    // que fait Netflix — on choisit d'abord, on y va ensuite.
    final double? v = _vise;
    setState(() => _vise = null);
    widget.onDeplacement(false);
    if (v != null) widget.onAllerA(positionDepuisRatio(v, widget.duree));
  }

  @override
  Widget build(BuildContext context) {
    final Duration position = widget.position;
    final Duration duree = widget.duree;
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
    // Pendant le déplacement, le chiffre de gauche suit la poignée : c'est
    // lui qui dit où l'on va atterrir, sans avoir besoin d'une bulle.
    final bool tient = _vise != null;
    final double ratio = tient ? _vise! : progression(position, duree);
    final Duration affichee = tient ? _cible : position;
    final bool actif = tient || _survol;

    return Row(
      children: <Widget>[
        // Largeur figée : sans elle, « 9:59 » puis « 10:00 » décalent toute
        // la réglette d'un caractère, et la barre tremble à chaque minute.
        SizedBox(
          width: 62,
          child: Text(
            formatDuree(affichee),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: tient ? FontWeight.w800 : FontWeight.w400,
              color: tient ? TvTokens.goldBright : TvTokens.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _survol = true),
            onExit: (_) => setState(() => _survol = false),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final double largeur = c.maxWidth;
                return GestureDetector(
                  // `opaque` : la zone sensible fait 22 px de haut alors
                  // que le trait n'en fait que 4. Viser un trait de 4 px à
                  // la souris est un exercice, pas une commande.
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails d) {
                    // Un simple clic sur la piste y emmène directement.
                    widget.onAllerA(positionDepuisRatio(
                        ratioDepuisX(d.localPosition.dx, largeur), duree));
                  },
                  onHorizontalDragStart: (DragStartDetails d) =>
                      _debut(d.localPosition.dx, largeur),
                  onHorizontalDragUpdate: (DragUpdateDetails d) =>
                      _pendant(d.localPosition.dx, largeur),
                  onHorizontalDragEnd: (DragEndDetails _) => _fin(),
                  onHorizontalDragCancel: _fin,
                  child: SizedBox(
                    height: 22,
                    width: largeur,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: <Widget>[
                        // La piste, épaissie au survol : elle se signale
                        // comme vivante avant même qu'on clique.
                        //
                        // Les largeurs sont données EN PIXELS, calculées
                        // depuis `largeur`. Dans un Stack, un enfant non
                        // positionné reçoit des contraintes lâches : une
                        // boîte sans largeur explicite s'y réduit à zéro et
                        // la barre disparaîtrait purement et simplement.
                        AnimatedContainer(
                          duration: TvDimens.focusAnim,
                          width: largeur,
                          height: actif ? 6 : 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Container(
                          width: largeur * ratio,
                          height: actif ? 6 : 4,
                          decoration: BoxDecoration(
                            color: TvTokens.gold,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        // La poignée. Elle n'apparaît qu'au survol : au
                        // repos, l'écran reste une image de film et pas un
                        // tableau de bord.
                        if (actif)
                          Positioned(
                            left: (ratio * largeur - 8)
                                .clamp(0.0, (largeur - 16).clamp(0.0, largeur)),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: TvTokens.goldBright,
                                shape: BoxShape.circle,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 62,
          child: Text(formatDuree(duree),
              style: const TextStyle(fontSize: 12, color: TvTokens.muted)),
        ),
      ],
    );
  }
}
