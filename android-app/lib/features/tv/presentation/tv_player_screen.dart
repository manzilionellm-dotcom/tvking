// =========================================================
//  tv_player_screen.dart — Lecteur plein écran TV (SurfaceView natif)
// =========================================================
//  Moteur = Media3 / ExoPlayer sur une vraie android.view.SurfaceView, via le
//  plugin local `native_video_player` (Hybrid Composition). PAS media_kit/mpv
//  NI flutter_vlc_player : les deux rendaient la vidéo dans une TEXTURE Flutter
//  et donnaient « son OK / image NOIRE » sur certaines box (trames HEVC
//  décodées par MediaCodec mais jamais affichées). Une SurfaceView native sort
//  la vidéo du chemin texture → l'image passe, comme dans IPTV Smarters & co.
//
//  Réglages stabilité (côté natif, cf. NativeVideoView.kt) :
//    1) décodage vidéo matériel MediaCodec + repli si l'init échoue
//       (pas de décodeur vidéo FFmpeg : il bloquait des chaînes sur le logo) ;
//    2) tampon INCHANGÉ (min 5 s / max 45 s, démarrage 1 s, reprise 2 s) —
//       l'allonger a déjà laissé des chaînes sur le chargement ;
//    3) watchdog 15 s : aucune progression → reconnexion auto (ré-ouvre l'URL).
//       Les événements d'un zap précédent sont ignorés (accusé de génération).
//
//  D-pad : Haut/Bas (ou Ch+/Ch-) = zap, chiffres = n° de chaîne, OK = barre,
//  Back = quitter. Pendant le chargement on affiche le NUMÉRO et le NOM
//  (pas seulement un logo) pour que le zapping reste lisible.
//  Une touche maintenue ne rouvre le flux qu'une fois, à l'arrêt :
//  enchaîner 20 setUrl gelait la box.
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/blackbox/black_box.dart';
import '../core/tv_activity.dart';
import '../core/tv_back_guard.dart';
import '../core/tv_tokens.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../cinema/data/cinema_downloads.dart';
import '../../player/data/local_stream_relay.dart';
import '../../player/domain/live_fallback.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../phone_remote/data/phone_remote_bus.dart';
import '../../phone_remote/data/phone_remote_session.dart';
import '../../phone_remote/domain/remote_command.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../recordings/data/recording_repository.dart';
import '../../recordings/domain/recording.dart';
import '../../subscription/data/now_playing.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import '../core/tv_zap.dart';
import 'tv_channel_guide_screen.dart';

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

class _TvPlayerScreenState extends State<TvPlayerScreen>
    with WidgetsBindingObserver {
  late final NativeVideoController _controller;
  final FocusNode _focus = FocusNode();

  late int _index = widget.startIndex;
  bool _overlay = true;

  // Index du bouton de la barre actuellement « surligné » au D-pad
  // (-1 = aucun). Permet à N'IMPORTE QUELLE télécommande (simple D-pad, sans
  // pointeur) d'atteindre TOUS les boutons : OK ouvre la barre, Gauche/Droite
  // déplacent le surlignage, OK active. Ordre : 0=Retour 1=Préc 2=Lecture/Pause
  // 3=Suiv 4=REC 5=Favori.
  int _btnFocus = -1;
  static const int _btnCount = 3;
  bool _buffering = true;
  Timer? _hideTimer;
  Timer? _presenceTimer;
  Timer? _numTimer;
  Timer? _watchdog;
  Timer? _toastTimer;
  // Zap maintenu : on change le numéro À L'ÉCRAN tout de suite, et on
  // n'ouvre le flux qu'une fois la télécommande relâchée (~180 ms sans
  // nouvel appui). Un seul setUrl au lieu d'un par répétition de touche.
  Timer? _zapSettle;
  bool _zapHolding = false;
  String _numBuffer = ''; // saisie d'un numéro de chaîne (touches 0-9)

  // ----- Enregistrement -----
  // Quand on enregistre, on fait passer la lecture par le MINI-RELAIS local
  // (LocalStreamRelay) : il ouvre UNE seule connexion vers le serveur IPTV et
  // recopie les octets À LA FOIS vers le lecteur ET vers le fichier .ts. Donc
  // le fournisseur ne voit qu'1 connexion (compatible max_connections=1) et le
  // fichier capture EXACTEMENT ce qui est à l'écran. Hors enregistrement, la
  // lecture reste DIRECTE (le relais n'est pas dans le chemin).
  Recording? _activeRecording;
  bool get _isRecording => _activeRecording != null;
  String? _relayPlayUrl; // URL locale 127.0.0.1 utilisée pendant l'enregistrement
  String? _toastMsg; // petit message éphémère (sauvegardé / vide / échec)

  // ----- Favoris -----
  // On suit l'ensemble des IDs favoris en direct (le ❤ du lecteur reflète
  // instantanément l'ajout/retrait, et reste à jour au zap).
  StreamSubscription<Set<String>>? _favSub;
  StreamSubscription<RemoteCommand>? _remoteSub;
  Set<String> _favIds = FavoritesRepository.instance.current;
  bool get _isFavorite => _favIds.contains(_current.id);

  // Anti-gel : on suit la progression réelle (position qui avance).
  DateTime _lastProgress = DateTime.now();
  Duration _lastPos = Duration.zero;
  // Anti double déclenchement (erreur native + chien de garde au même moment).
  DateTime _lastRecoverAt = DateTime.fromMillisecondsSinceEpoch(0);
  // App au premier plan ? (Home / multitâche → lecture en pause : le chien de
  // garde ne doit PAS « réparer » une pause voulue, sinon le son repartirait
  // en arrière-plan.)
  bool _appActive = true;
  static const Duration _frozen = Duration(seconds: 15);
  static const Duration _watchEvery = Duration(seconds: 4);
  // Reconnexion BORNÉE (P1-6) : on compte les ré-ouvertures sur la MÊME chaîne.
  // Au-delà de _kMaxRecover sans reprise, on ARRÊTE la boucle (CPU/réseau/chauffe)
  // et on montre une erreur claire + bouton « Réessayer » au lieu de boucler à
  // l'infini sur un flux mort. Remis à zéro dès qu'une image revient (progression)
  // ou au changement de chaîne.
  int _recoverAttempts = 0;
  static const int _kMaxRecover = 5;
  bool _fatal = false;
  // True dès qu'une vraie image a été affichée pour la chaîne courante. Si on
  // échoue SANS jamais avoir eu d'image → source vide / bloquée par le
  // fournisseur (≠ coupure réseau d'un flux qui jouait). Remis à false à chaque
  // ouverture (_open).
  bool _everShownFrame = false;

  // SECOURS DU DIRECT (LiveFallback) : si la chaîne ne démarre pas, on essaie
  // les autres formats du même serveur puis la même chaîne dans une autre
  // source. [_playingUrl] = l'adresse réellement ouverte ; [_alts] = la liste
  // des adresses à essayer (calculée au 1er échec seulement).
  late String _playingUrl;
  List<String>? _alts;
  int _altIdx = 0;
  bool _altRemembered = false;

  /// Budget de reconnexion : au moins [_kMaxRecover], et assez pour essayer
  /// chaque adresse de secours une fois (+2 pour les coupures réseau).
  int get _maxRecover {
    final int n = (_alts?.length ?? 1) + 2;
    return n > _kMaxRecover ? n : _kMaxRecover;
  }

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
    TvActivity.enter();
    BlackBox.instance.info('SCREEN', 'Lecteur ouvert');
    WidgetsBinding.instance.addObserver(this);
    // Le décodage (MediaCodec matériel + repli logiciel), le tampon réseau et
    // le User-Agent sont gérés côté natif (NativeVideoView.kt). Ici on se
    // contente de piloter l'URL et d'écouter l'état.
    _playingUrl = LiveFallback.preferred(_current.streamUrl);
    _controller = NativeVideoController(initialUrl: _playingUrl);
    // Beaucoup d'abonnements n'autorisent qu'UNE connexion : un
    // téléchargement de film en cours ferait refuser le direct (« le cinéma
    // marche mais pas les chaînes »). On le met en pause le temps du direct,
    // il reprend tout seul en quittant le lecteur.
    unawaited(CinemaDownloads.pauseForLive());
    _controller.addListener(_onPlayer);
    // Favoris en direct (le ❤ se met à jour tout seul).
    FavoritesRepository.instance.initialize();
    _favSub = FavoritesRepository.instance.favoritesStream.listen((Set<String> ids) {
      if (mounted) setState(() => _favIds = ids);
    });
    unawaited(_bindPhoneRemote());
    _open(reuse: true); // historique / présence pour la 1re chaîne
    // Chien de garde : aucune progression depuis 15 s → reconnexion.
    // (Correctif 29/09/2026 : avant, `_recovering` restait vrai après une 1re
    // tentative ratée → plus AUCUNE reconnexion, roue de chargement à
    // l'infini. Désormais chaque tentative ratée en relance une autre 15 s
    // plus tard, jusqu'au budget, puis l'écran « Réessayer ».)
    _watchdog = Timer.periodic(_watchEvery, (_) {
      if (!_appActive) {
        _lastProgress = DateTime.now(); // pause voulue : pas un gel
        return;
      }
      if (DateTime.now().difference(_lastProgress) > _frozen) {
        _recover();
      }
    });
    // Garde l'app « en ligne » + chaîne à jour pendant le visionnage.
    _presenceTimer = Timer.periodic(const Duration(minutes: 3),
        (_) => SubscriptionState.instance.syncWithBackend());
  }

  // Couper le son quand on QUITTE / minimise l'app (Home, multitâche) : pas de
  // lecture en arrière-plan sur TV. Quitter l'app = quitter, point. On reprend
  // le direct au retour dans l'app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _appActive = false;
        _controller.pause();
      case AppLifecycleState.resumed:
        _appActive = true;
        _lastProgress = DateTime.now();
        _controller.play();
      case AppLifecycleState.inactive:
        break; // transitions brèves (dialogue…) → on ne coupe pas
    }
  }

  @override
  void dispose() {
    TvActivity.leave();
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _presenceTimer?.cancel();
    _numTimer?.cancel();
    _watchdog?.cancel();
    _toastTimer?.cancel();
    _zapSettle?.cancel();
    _favSub?.cancel();
    _remoteSub?.cancel();
    // Si on quitte le lecteur en plein enregistrement : on finalise proprement
    // (arrêt du relais + clôture en base), sans toucher au controller détruit.
    if (_activeRecording != null) {
      final Recording rec = _activeRecording!;
      LocalStreamRelay.instance.stopRecording(rec.streamUrl ?? _playingUrl);
      RecordingRepository.instance.finishRecording(rec);
    }
    _controller.removeListener(_onPlayer);
    NowPlaying.instance.clear();
    SubscriptionState.instance.syncWithBackend(); // on ne regarde plus rien
    _controller.dispose();
    unawaited(CinemaDownloads.resumeAfterLive());
    _focus.dispose();
    super.dispose();
  }

  // Écoute l'état du lecteur natif : progression (anti-gel), buffering (logo),
  // erreurs.
  void _onPlayer() {
    // Pendant un zap maintenu, le flux encore ouvert n'est PAS la chaîne
    // affichée. On ignore ses erreurs / sa première image, sinon l'écran
    // croirait que la mauvaise chaîne est prête et lancerait une
    // reconnexion inutile.
    if (_zapHolding) return;
    // Progression réelle → « pas gelé ». La lecture est repartie : on remet à
    // zéro le budget de reconnexion (et on lève un éventuel état d'erreur).
    if (_controller.position != _lastPos) {
      _lastPos = _controller.position;
      _lastProgress = DateTime.now();
      _recoverAttempts = 0;
      if (_fatal && mounted) setState(() => _fatal = false);
      // Une adresse de SECOURS joue : on retient le format pour ce serveur
      // (les chaînes suivantes s'ouvriront directement comme ça).
      if (!_altRemembered && _playingUrl != _current.streamUrl) {
        _altRemembered = true;
        LiveFallback.remember(_current.streamUrl, _playingUrl);
        BlackBox.instance.info('PLAYER', 'secours du direct OK (adresse ${_altIdx + 1}/${_alts?.length ?? 1})');
      }
    }
    // Une vraie image a été dessinée → la source envoie bien de la vidéo.
    if (_controller.firstFrame) _everShownFrame = true;
    // Logo tant qu'on bufferise OU que la 1re trame n'est pas encore dessinée
    // (au zap, firstFrame est remis à false → logo jusqu'à l'image suivante).
    final bool buffering = _controller.isBuffering || !_controller.firstFrame;
    if (mounted && buffering != _buffering) {
      setState(() => _buffering = buffering);
    }
    // Erreur / fin de flux live → reconnexion.
    if (_controller.hasError || _controller.isEnded) {
      _recover();
    }
  }

  /// Le téléphone n'agit que si l'écran du lecteur est devant,
  /// et seulement si l'interrupteur est allumé. Une erreur ici
  /// ne coupe pas la chaîne : on ignore l'ordre.
  Future<void> _bindPhoneRemote() async {
    try {
      await PhoneRemoteSession.flag.load();
      if (!mounted || !PhoneRemoteSession.flag.value) return;
      _remoteSub = PhoneRemoteBus.instance.stream.listen((RemoteCommand command) {
        if (!mounted) return;
        final ModalRoute<Object?>? route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return;
        try {
          switch (command) {
            case RemoteCommand.up:
              _zap(-1);
            case RemoteCommand.down:
              _zap(1);
            case RemoteCommand.left:
              _navBtn(-1);
            case RemoteCommand.right:
              _navBtn(1);
            case RemoteCommand.ok:
              _okPressed();
            case RemoteCommand.back:
              TvBackGuard.markHandled();
              Navigator.of(context).maybePop();
            case RemoteCommand.playPause:
              _togglePlayPause();
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  void _open({bool reuse = false}) {
    _lastProgress = DateTime.now();
    _lastPos = Duration.zero;
    _everShownFrame = false; // nouvelle ouverture → pas encore d'image
    // Nouvelle chaîne → budget de reconnexion neuf, on lève tout état d'erreur.
    _recoverAttempts = 0;
    _alts = null;
    _altIdx = 0;
    _altRemembered = false;
    if (mounted) setState(() {
      _buffering = true;
      _fatal = false;
    });
    if (!reuse) {
      // Nouvelle chaîne → on charge la nouvelle URL dans le MÊME lecteur
      // (dans le format qui a déjà marché sur ce serveur, s'il y en a un).
      _playingUrl = LiveFallback.preferred(_current.streamUrl);
      _controller.setUrl(_playingUrl);
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
    // On ne peut enregistrer qu'1 chaîne à la fois (1 connexion) : changer de
    // chaîne clôt et SAUVEGARDE l'enregistrement en cours.
    if (_isRecording) _finalizeRecording(resumeDirect: false);
    setState(() {
      _index = tvNextZapIndex(_index, delta, n);
      _zapHolding = true;
    });
    _showOverlayTemporarily();
    // 180 ms : sous le délai d'une vraie image (souvent > 0,5 s), donc un
    // appui simple ne paraît pas lent. Une touche maintenue repart le
    // chrono : un seul flux s'ouvre, sur la chaîne où l'on s'arrête.
    _zapSettle?.cancel();
    _zapSettle = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _zapHolding = false;
      _open();
    });
  }

  void _recover() {
    if (_fatal || _zapHolding) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastRecoverAt) < const Duration(seconds: 3)) return;
    _lastRecoverAt = now;
    BlackBox.instance.warn('PLAYER', 'reconnexion (tentative ${_recoverAttempts + 1}/$_maxRecover)'
        '${_controller.hasError ? ' après erreur ExoPlayer' : _controller.isEnded ? ' après fin de flux' : ' après gel 15 s'}');
    // BORNE (P1-6) : au-delà de _kMaxRecover ré-ouvertures sans reprise, on
    // ARRÊTE la boucle de reconnexion et on bascule en erreur explicite avec
    // « Réessayer » manuel — fini la boucle CPU/réseau infinie sur flux mort.
    if (_recoverAttempts >= _maxRecover) {
      if (mounted) setState(() {
        _fatal = true;
        _buffering = false;
      });
      return;
    }
    _recoverAttempts++;
    _lastProgress = DateTime.now();
    // Enregistrement en cours : on ré-ouvre le relais local (on ne change
    // pas de source au milieu d'un fichier).
    if (_relayPlayUrl != null) {
      _controller.setUrl(_relayPlayUrl!);
      return;
    }
    // Chaîne qui JOUAIT puis s'est coupée : 1re tentative sur la même
    // adresse (simple coupure réseau). Chaîne qui n'a JAMAIS démarré, ou
    // 2e échec : on passe à l'adresse de secours suivante.
    if (_everShownFrame && _recoverAttempts == 1) {
      _controller.setUrl(_playingUrl);
      return;
    }
    final List<String> alts = _alts ??= LiveFallback.candidates(
        _current, PlaylistRepository.instance.currentChannels);
    if (alts.length > 1) {
      _altIdx = (_altIdx + 1) % alts.length;
      _playingUrl = alts[_altIdx];
      BlackBox.instance.warn('PLAYER', 'secours du direct : adresse ${_altIdx + 1}/${alts.length}');
    }
    _controller.setUrl(_playingUrl);
  }

  /// « Réessayer » manuel depuis l'écran d'erreur : on repart d'un budget neuf.
  void _manualRetry() {
    _zapSettle?.cancel();
    _zapHolding = false;
    setState(() {
      _fatal = false;
      _recoverAttempts = 0;
      _buffering = true;
    });
    _controller.setUrl(_relayPlayUrl ?? _playingUrl);
    _showOverlayTemporarily();
  }

  // ----- Enregistrement (bouton REC / touche média) -----

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _finalizeRecording(resumeDirect: true);
    } else {
      await _startRecording();
    }
    _showOverlayTemporarily();
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    // L'adresse qui JOUE (éventuellement une adresse de secours).
    final String realUrl = _playingUrl;
    try {
      final String path = await RecordingRepository.instance
          .createFilePath(channelName: _current.cleanName);

      // 1) On bascule D'ABORD la lecture sur le relais : le lecteur lâche la
      //    connexion DIRECTE et le relais ouvre L'UNIQUE connexion vers le
      //    serveur. On évite ainsi d'avoir 2 connexions en même temps
      //    (incompatible avec les fournisseurs max_connections=1).
      final String localUrl =
          await LocalStreamRelay.instance.playUrlFor(realUrl);
      _relayPlayUrl = localUrl;
      _controller.setUrl(localUrl);

      // 2) On attache l'écriture fichier à CETTE MÊME session relais (pas de
      //    nouvelle connexion : le tee recopie juste les octets vers le .ts).
      final bool ok = await LocalStreamRelay.instance
          .startRecording(realUrl: realUrl, filePath: path);
      if (!ok) {
        _relayPlayUrl = null;
        _controller.setUrl(realUrl); // on revient au direct
        _flash('Échec démarrage enregistrement');
        return;
      }

      // 3) On enregistre la fiche en base (liste « Enregistrements »).
      final Recording rec = await RecordingRepository.instance.startRecording(
        channelId: _current.id,
        channelName: _current.cleanName,
        filePath: path,
        channelLogoUrl: _current.logoUrl,
        streamUrl: realUrl,
      );
      if (mounted) {
        setState(() => _activeRecording = rec);
        _flash(context.l10n.tvRecordingStarted);
      }
    } catch (e) {
      if (mounted) _flash(context.l10n.tvRecordingError);
    }
  }

  /// Clôt l'enregistrement en cours. [resumeDirect] = on rebascule la lecture
  /// en direct (bouton stop) ; à false quand l'appelant va lui-même rouvrir
  /// une autre source (zap).
  Future<void> _finalizeRecording({required bool resumeDirect}) async {
    final Recording? rec = _activeRecording;
    if (rec == null) return;
    // UI immédiate : on n'est plus « en train d'enregistrer ».
    if (mounted) {
      setState(() => _activeRecording = null);
    } else {
      _activeRecording = null;
    }
    _relayPlayUrl = null;
    final String realUrl = rec.streamUrl ?? _playingUrl;
    int bytes = 0;
    bool failed = false;
    try {
      bytes = await LocalStreamRelay.instance.stopRecording(realUrl);
      await RecordingRepository.instance.finishRecording(rec);
    } catch (_) {
      failed = true;
    }
    if (resumeDirect && mounted) {
      _controller.setUrl(_playingUrl);
    }
    if (mounted) {
      if (failed) {
        _flash('L\'enregistrement n\'a pas pu être fermé. Le fichier peut être incomplet.');
      } else {
        _flash(bytes > 0
            ? context.l10n.tvRecordingSaved(_humanSize(bytes))
            : context.l10n.tvRecordingEmpty);
      }
    }
  }

  // Petit message éphémère en bas de l'écran (~3 s).
  void _flash(String msg) {
    setState(() => _toastMsg = msg);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMsg = null);
    });
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} Go';
  }

  void _showOverlayTemporarily() {
    setState(() => _overlay = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() {
        _overlay = false;
        _btnFocus = -1; // on oublie le surlignage quand la barre se masque
      });
    });
  }

  // Affiche/masque la barre (tap sur l'écran tactile). Au masquage on retire
  // le surlignage D-pad.
  void _toggleOverlay() {
    setState(() {
      _overlay = !_overlay;
      if (!_overlay) _btnFocus = -1;
    });
    if (_overlay) _showOverlayTemporarily();
  }

  // OK / centre du D-pad : ouvre la barre (et surligne Lecture/Pause), ou
  // active le bouton surligné si la barre est déjà ouverte.
  void _okPressed() {
    if (!_overlay || _btnFocus < 0) {
      setState(() {
        _overlay = true;
        if (_btnFocus < 0) _btnFocus = 1; // REC par défaut (bouton central)
      });
      _showOverlayTemporarily();
      return;
    }
    _activateBtn(_btnFocus);
  }

  // Déplace le surlignage Gauche/Droite. Si la barre est masquée, on l'ouvre.
  void _navBtn(int delta) {
    if (!_overlay) {
      setState(() {
        _overlay = true;
        if (_btnFocus < 0) _btnFocus = 1;
      });
      _showOverlayTemporarily();
      return;
    }
    setState(() {
      _btnFocus = (_btnFocus < 0 ? 1 : _btnFocus + delta).clamp(0, _btnCount - 1);
    });
    _showOverlayTemporarily();
  }

  // Exécute l'action du bouton surligné.
  void _activateBtn(int i) {
    switch (i) {
      case 0:
        _openGuide();
        break;
      case 1:
        _toggleRecording();
        break;
      case 2:
        _toggleFavorite();
        break;
    }
  }

  // Ouvre le GUIDE de la chaîne en cours : émission actuelle + « à suivre »,
  // avec possibilité de poser une ALARME (rappel) sur un programme.
  void _openGuide() {
    // Si l'utilisateur tient encore Haut/Bas, on ouvre d'abord la chaîne
    // affichée : le guide et l'image doivent parler de la même chaîne.
    if (_zapSettle?.isActive ?? false) {
      _zapSettle!.cancel();
      _zapHolding = false;
      _open();
    }
    unawaited(Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvChannelGuideScreen(channel: _current),
      ),
    ).then((_) {
      // Au retour, le focus clavier était parti avec la route du guide.
      if (mounted) _focus.requestFocus();
    }));
    _showOverlayTemporarily();
  }

  // Lecture/pause (touche média OU bouton tactile). setState pour rafraîchir
  // l'icône ▶/⏸ des contrôles tactiles.
  void _togglePlayPause() {
    if (_controller.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    _showOverlayTemporarily();
    setState(() {});
  }

  // Ajoute / retire la chaîne courante des favoris (bouton ❤ / touche F).
  void _toggleFavorite() {
    final bool wasFav = _isFavorite;
    FavoritesRepository.instance.toggle(_current.id);
    _flash(wasFav ? context.l10n.tvRemovedFromFavorites : context.l10n.tvAddedToFavorites);
    _showOverlayTemporarily();
  }

  // ----- Saisie d'un numéro de chaîne (0-9) → zap après ~1,5 s -----
  void _onDigit(int d) {
    if (_numBuffer.length < 4) _numBuffer += '$d';
    _numTimer?.cancel();
    _numTimer = Timer(const Duration(milliseconds: 1500), _jumpNumber);
    setState(() {});
  }

  void _jumpNumber() {
    _zapSettle?.cancel();
    _zapHolding = false;
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
  // OK / centre du D-pad — toutes les variantes de télécommandes. (Gauche/
  // Droite ne sont PLUS « OK » : ils déplacent le surlignage entre boutons.)
  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA ||
      k == LogicalKeyboardKey.space;

  // Télécommandes universelles : toutes les variantes mènent à l'action.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // On prend l'appui ET la répétition (touche maintenue). Le relâchement
    // (KeyUp) est ignoré. Le flux, lui, n'est ouvert qu'une fois dans _zap.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey k = event.logicalKey;

    // ÉCRAN D'ERREUR (P1-6) : OK = Réessayer ; le Retour reste géré plus bas
    // (quitter le lecteur). On capte OK ici pour ne pas ouvrir la barre.
    if (_fatal && _isOk(k)) {
      _manualRetry();
      return KeyEventResult.handled;
    }

    // BACK / Retour télécommande (toutes variantes) → quitter le lecteur,
    // retour à la liste. On gère explicitement pour ne jamais rester coincé.
    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.exit) {
      // Retour = quitter le lecteur (convention YouTube/Netflix). La
      // navigation des boutons se fait à Gauche/Droite + OK.
      // markHandled : le « retour système » du MÊME appui ne doit pas
      // fermer aussi la liste Direct (retour un à un).
      TvBackGuard.markHandled();
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    int di = _digits.indexOf(k);
    if (di < 0) di = _numpad.indexOf(k);
    if (di >= 0) { _onDigit(di); return KeyEventResult.handled; }

    // Haut/Bas (et Ch+/Ch-) = zap direct, même quand la barre est ouverte.
    if (_isPrev(k)) { _zap(-1); return KeyEventResult.handled; }
    if (_isNext(k)) { _zap(1); return KeyEventResult.handled; }

    // Gauche/Droite = déplacer le surlignage entre les boutons de la barre.
    if (k == LogicalKeyboardKey.arrowLeft) {
      _navBtn(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _navBtn(1);
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaStop) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRecord || k == LogicalKeyboardKey.keyR) {
      _toggleRecording();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      _toggleFavorite();
      return KeyEventResult.handled;
    }
    if (_isOk(k)) {
      _okPressed();
      return KeyEventResult.handled;
    }
    _showOverlayTemporarily();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Material TRANSPARENT obligatoire : le lecteur est poussé comme route
    // SÉPARÉE (hors de TvShell). Sans Material ancêtre, Flutter dessine tout
    // texte avec son style d'ERREUR (police machine à écrire + double
    // soulignement jaune) — c'était le rendu vu sur la box pour « Guide /
    // REC / Favori » et le bandeau de chaîne. Aucun autre changement visuel :
    // les styles TvTokens prévus s'appliquent enfin.
    return Material(
      type: MaterialType.transparency,
      child: PopScope(
      canPop: true,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        // TACTILE (TV/tablette à écran tactile) : tap = affiche/masque la
        // barre ; glissé vertical = zap. Les boutons de la barre captent leur
        // propre tap (ils gagnent l'arène des gestes) avant ce fond.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleOverlay,
          onVerticalDragEnd: (DragEndDetails d) {
            final double v = d.primaryVelocity ?? 0;
            if (v < -250) {
              _zap(1); // glissé vers le HAUT → chaîne suivante
            } else if (v > 250) {
              _zap(-1); // glissé vers le BAS → chaîne précédente
            }
          },
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
              // Vidéo SurfaceView native plein écran (16:9 centré sur TV 16:9).
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: NativeVideoView(controller: _controller),
                ),
              ),
              // Le temps que l'image arrive (ou qu'on lâche Haut/Bas), on dit
              // QUELLE chaîne est visée. Un logo seul ne permettait pas de
              // zapper « à l'aveugle » sans se perdre.
              if (_zapHolding || (_buffering && !_fatal)) _loadingCard(),
              // Écran d'ERREUR : la reconnexion automatique a été épuisée.
              // On ARRÊTE de boucler. OK réessaie, Haut/Bas change de chaîne,
              // Retour quitte. Masqué pendant un zap : la personne est déjà
              // en train d'en choisir une autre. Le texte (chaîne coupée ou
              // chaîne vide) reste celui des traductions, lisible à 3 m.
              if (_fatal && !_zapHolding) _errorCard(),
              // Panneau de lecture (façon YouTube / Netflix) : glisse depuis le
              // bas + fondu, masqué automatiquement après 5 s. Contient l'info
              // chaîne + tous les contrôles (dont REC et ❤ en bas).
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
                      child: _ControlsBar(
                        channel: _current,
                        index: _index,
                        total: widget.channels.length,
                        isRecording: _isRecording,
                        isFavorite: _isFavorite,
                        focusedIndex: _btnFocus,
                        onGuide: _openGuide,
                        onRecord: _toggleRecording,
                        onFavorite: _toggleFavorite,
                      ),
                    ),
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
              // Pastille « ● REC » visible en permanence pendant l'enregistrement
              // (même quand la barre est masquée).
              if (_isRecording)
                Positioned(
                  top: TvDimens.safeV + 8,
                  left: TvDimens.safeH,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: TvTokens.live),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.fiber_manual_record_rounded,
                            color: TvTokens.live, size: 16),
                        const SizedBox(width: 8),
                        Text('REC',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: TvTokens.text)),
                      ],
                    ),
                  ),
                ),
              // Message éphémère (sauvegardé / vide / échec).
              if (_toastMsg != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: TvDimens.safeV + 120,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(_toastMsg!,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: TvTokens.text)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Carte de chargement : numéro géant + nom + consigne de zap.
  /// Lisible à 3 m, et elle suit la chaîne AFFICHÉE même si le flux
  /// n'est pas encore ouvert (zap maintenu).
  Widget _loadingCard() {
    final Channel c = _current;
    return ColoredBox(
      color: TvTokens.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('${_index + 1}',
                  style: TvTokens.display(TvDimens.displayL,
                      color: TvTokens.accentBright)),
              const SizedBox(height: 8),
              Text(c.cleanName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.display(TvDimens.headline, color: TvTokens.text)),
              if (_isFavorite) ...<Widget>[
                const SizedBox(height: 8),
                const Icon(Icons.favorite_rounded,
                    color: TvTokens.accent, size: 22),
              ],
              const SizedBox(height: 22),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: TvTokens.accent),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.tvPlayerLoading,
                  style: TvTokens.ui(TvDimens.body, color: TvTokens.muted)),
              const SizedBox(height: 6),
              Text(context.l10n.tvZapHint,
                  style: TvTokens.ui(TvDimens.label, color: TvTokens.mutedDim)),
            ],
          ),
        ),
      ),
    );
  }

  /// Erreur claire : ce qui s'est passé, et les trois touches utiles.
  Widget _errorCard() {
    return ColoredBox(
      color: TvTokens.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline_rounded,
                  color: TvTokens.accentBright, size: 56),
              const SizedBox(height: 12),
              Text('${_index + 1}',
                  style: TvTokens.display(TvDimens.displayM,
                      color: TvTokens.accentBright)),
              const SizedBox(height: 6),
              Text(_current.cleanName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.display(TvDimens.title, color: TvTokens.text)),
              const SizedBox(height: 10),
              Text(
                _everShownFrame
                    ? context.l10n.tvPlayerFatalDown
                    : context.l10n.tvPlayerFatalEmpty,
                textAlign: TextAlign.center,
                style: TvTokens.ui(TvDimens.body, color: TvTokens.muted),
              ),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: TvTokens.sel,
                  borderRadius: BorderRadius.circular(TvTokens.rButton),
                  border: Border.all(
                      color: TvTokens.accent, width: TvDimens.focusOutline),
                ),
                child: Text(context.l10n.tvPlayerFatalHint,
                    style: TvTokens.ui(TvDimens.titleS,
                        weight: FontWeight.w700, color: TvTokens.accentBright)),
              ),
              const SizedBox(height: 10),
              Text(context.l10n.tvPlayerFatalNav,
                  style: TvTokens.ui(TvDimens.label, color: TvTokens.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Programme « maintenant » sous le nom, dans la barre du lecteur.
/// Une requête indexée par chaîne : au zap on ne recharge que celle-ci.
class _LiveEpgLine extends StatefulWidget {
  const _LiveEpgLine({required this.channelId});
  final String channelId;

  @override
  State<_LiveEpgLine> createState() => _LiveEpgLineState();
}

class _LiveEpgLineState extends State<_LiveEpgLine> {
  Timer? _wait;
  EpgProgram? _shown;

  @override
  void initState() {
    super.initState();
    _load(widget.channelId);
  }

  @override
  void didUpdateWidget(covariant _LiveEpgLine old) {
    super.didUpdateWidget(old);
    if (old.channelId == widget.channelId) return;
    // Zap rapide : on efface tout de suite le programme de la chaîne
    // précédente (sinon il s'affiche sous le mauvais nom), et on ne
    // requête la base qu'une fois le zapping calmé.
    _wait?.cancel();
    _shown = null;
    final String id = widget.channelId;
    _wait = Timer(const Duration(milliseconds: 200), () => _load(id));
  }

  void _load(String id) {
    // Un guide absent ou une base occupée ne doit pas faire tomber
    // le lecteur : on cache simplement la ligne.
    EpgRepository.instance.currentProgram(id).then((EpgProgram? p) {
      if (!mounted || widget.channelId != id) return;
      setState(() => _shown = p);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EpgProgram? p = _shown;
    if (p == null || p.title.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '${context.l10n.tvEpgNow}  ·  ${p.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TvTokens.ui(TvDimens.label, color: TvTokens.accentBright),
      ),
    );
  }
}

/// Panneau de lecture moderne (façon YouTube / Netflix) : dégradé sombre en
/// bas, infos chaîne (logo + nom + DIRECT + n° de chaîne) puis une rangée de
/// commandes « verre » animées. À droite (« en bas ») : REC et ❤ favori.
/// Boutons NON focusables → le D-pad zappe directement (Haut/Bas) ; ils
/// servent au doigt (tablette / TV tactile) et de repères visuels.
class _ControlsBar extends StatelessWidget {
  const _ControlsBar({
    required this.channel,
    required this.index,
    required this.total,
    required this.isRecording,
    required this.isFavorite,
    required this.focusedIndex,
    required this.onGuide,
    required this.onRecord,
    required this.onFavorite,
  });

  final Channel channel;
  final int index;
  final int total;
  final bool isRecording;
  final bool isFavorite;

  /// Index du bouton surligné au D-pad (-1 = aucun). 0=Guide 1=REC 2=Favori.
  final int focusedIndex;
  final VoidCallback onGuide;
  final VoidCallback onRecord;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          TvDimens.safeH, 44, TvDimens.safeH, TvDimens.safeV + 14),
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
          // ---- Ligne info chaîne ----
          Row(
            children: <Widget>[
              _logo(),
              const SizedBox(width: 16),
              Expanded(child: _info(context)),
              const SizedBox(width: 12),
              _channelNumber(),
            ],
          ),
          const SizedBox(height: 18),
          // ---- Commandes utiles en DIRECT uniquement : Guide, REC, Favori ----
          // (Lecture/pause et avance/retour n'ont aucun sens en live → retirés.)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CtrlButton(
                icon: Icons.calendar_month_rounded,
                label: context.l10n.tvGuideBtn,
                onTap: onGuide,
                focused: focusedIndex == 0,
              ),
              const SizedBox(width: 34),
              _CtrlButton(
                icon: isRecording
                    ? Icons.stop_rounded
                    : Icons.fiber_manual_record_rounded,
                label: isRecording ? context.l10n.tvStop : context.l10n.tvRec,
                onTap: onRecord,
                accent: TvTokens.live,
                active: isRecording,
                focused: focusedIndex == 1,
              ),
              const SizedBox(width: 34),
              _CtrlButton(
                icon: isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: context.l10n.tvFavoriteBtn,
                onTap: onFavorite,
                accent: TvTokens.accent,
                active: isFavorite,
                focused: focusedIndex == 2,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _logo() => SizedBox(
        width: 56,
        height: 56,
        child: (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: channel.logoUrl!,
                fit: BoxFit.contain,
                memCacheWidth: 160,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => _initials(),
                errorWidget: (_, __, ___) => _initials())
            : _initials(),
      );

  Widget _initials() => Center(
        child: Text(channel.initials,
            style: TextStyle(
                fontSize: TvDimens.title,
                fontWeight: FontWeight.w800,
                color: TvTokens.muted)),
      );

  Widget _info(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(channel.cleanName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: TvDimens.headline,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.text)),
          // Programme en cours, sous le nom : le guide sans quitter l'image.
          _LiveEpgLine(channelId: channel.id),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              if (channel.isLive) ...<Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: TvTokens.live,
                      borderRadius: BorderRadius.circular(5)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.fiber_manual_record_rounded,
                          color: Colors.white, size: 11),
                      const SizedBox(width: 5),
                      Text(context.l10n.tvLiveBadge,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Text(
                  channel.category.trim().isEmpty
                      ? context.l10n.tvOthers
                      : channel.category.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: TvDimens.label, color: TvTokens.muted),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _channelNumber() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Text('${index + 1} / $total',
            style: TextStyle(
                fontSize: TvDimens.label,
                fontWeight: FontWeight.w800,
                color: TvTokens.text)),
      );
}

/// Bouton de commande « verre » avec animation d'appui (scale), façon lecteur
/// moderne. Non focusable : répond au doigt ; le D-pad zappe directement.
class _CtrlButton extends StatefulWidget {
  const _CtrlButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.primary = false,
    this.accent,
    this.active = false,
    this.focused = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? label; // libellé sous le bouton (Guide / REC / Favori)
  final bool primary;
  final Color? accent; // teinte quand actif (rouge REC / or favori)
  final bool active;
  final bool focused; // surligné au D-pad (n'importe quelle télécommande)

  @override
  State<_CtrlButton> createState() => _CtrlButtonState();
}

class _CtrlButtonState extends State<_CtrlButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final double d = widget.primary ? 76 : 62;
    final Color accent = widget.accent ?? TvTokens.accent;
    // Surlignage D-pad = anneau OR épais + halo : visible sur N'IMPORTE quelle
    // télécommande (le repère « où je suis »).
    final Color borderColor = widget.focused
        ? TvTokens.accent
        : (widget.active ? accent : Colors.white24);
    final Color bg = widget.focused
        ? TvTokens.accent.withValues(alpha: 0.28)
        : (widget.active
            ? accent.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.42));
    final Color iconColor = widget.focused
        ? TvTokens.accent
        : (widget.active ? accent : TvTokens.text);
    final Color labelColor = widget.focused
        ? TvTokens.accent
        : (widget.active ? accent : TvTokens.muted);

    final double scale = _down ? 0.9 : (widget.focused ? 1.12 : 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: widget.focused ? 2 : 1),
                boxShadow: widget.focused
                    ? <BoxShadow>[
                        BoxShadow(
                            color: TvTokens.accent.withValues(alpha: 0.45),
                            blurRadius: 24,
                            spreadRadius: -2),
                      ]
                    : null,
              ),
              child: Icon(widget.icon, color: iconColor, size: widget.primary ? 42 : 30),
            ),
            if (widget.label != null) ...<Widget>[
              const SizedBox(height: 7),
              Text(widget.label!,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: labelColor)),
            ],
          ],
        ),
      ),
    );
  }
}
