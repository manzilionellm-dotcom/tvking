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
//    1) décodage matériel MediaCodec + repli logiciel (decoder fallback) ;
//    2) gros tampon (min 5 s / max 30 s, démarrage 1,5 s) ;
//    3) watchdog 15 s : aucune progression → reconnexion auto (ré-ouvre l'URL).
//
//  D-pad : Haut/Bas (ou Ch+/Ch-) = zap, chiffres = n° de chaîne, OK = barre,
//  Back = quitter. Logo « The Few » affiché à l'ouverture / au zap.
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../core/tv_tokens.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../player/data/local_stream_relay.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../recordings/data/recording_repository.dart';
import '../../recordings/domain/recording.dart';
import '../../subscription/data/now_playing.dart';
import '../../subscription/data/subscription_state.dart';
import '../core/tv_dimens.dart';
import 'tv_channel_programs_screen.dart';
import 'tv_components.dart';
import 'tv_multiview_screen.dart';

/// Signature d'un constructeur de lecteur plein écran (pour une liste de
/// chaînes + un index de départ). Permet à CHAQUE plateforme d'injecter SON
/// moteur de lecture sans que le code partagé ne connaisse media_kit/AVPlay.
typedef TvPlayerBuilder = Widget Function(
    List<Channel> channels, int startIndex);

/// Lecteur injecté par la plateforme (null = on utilise le lecteur natif
/// Android ci-dessous). Posé AVANT runApp par chaque point d'entrée :
///   • Android TV (main_tv)  → rien à poser : défaut = NativeTvPlayerScreen
///     (Media3/ExoPlayer SurfaceView).
///   • Windows (main_windows) → un lecteur media_kit (libmpv).
///   • Samsung (main_tizen)   → un lecteur video_player_avplay (AVPlay natif).
/// AVANTAGE CLÉ : le fichier du lecteur media_kit / AVPlay n'est importé QUE par
/// son main_* respectif → le build Android TV ne voit JAMAIS media_kit (sa
/// fermeture de compilation reste propre, cf. build-tv.yml qui strippe media_kit).
TvPlayerBuilder? _injectedPlayer;

/// Enregistre le lecteur de la plateforme (appelé une fois au démarrage).
void registerTvPlayer(TvPlayerBuilder builder) => _injectedPlayer = builder;

/// Lecteur plein écran TV. Façade FINE : si une plateforme a injecté son moteur
/// (Windows/Tizen), on l'utilise ; sinon on retombe sur le lecteur natif Android
/// (NativeTvPlayerScreen) — comportement Android STRICTEMENT inchangé.
class TvPlayerScreen extends StatelessWidget {
  const TvPlayerScreen({
    super.key,
    required this.channels,
    required this.startIndex,
  });

  /// Liste pour le zap (Haut/Bas) — généralement la catégorie courante.
  final List<Channel> channels;
  final int startIndex;

  @override
  Widget build(BuildContext context) {
    final TvPlayerBuilder? injected = _injectedPlayer;
    if (injected != null) return injected(channels, startIndex);
    return NativeTvPlayerScreen(channels: channels, startIndex: startIndex);
  }
}

/// Lecteur NATIF Android (Media3 / ExoPlayer sur SurfaceView) — l'implémentation
/// historique, inchangée. C'est le défaut quand aucune plateforme n'injecte de
/// moteur (donc TOUJOURS sur Android TV / Fire TV).
class NativeTvPlayerScreen extends StatefulWidget {
  const NativeTvPlayerScreen({
    super.key,
    required this.channels,
    required this.startIndex,
  });

  /// Liste pour le zap (Haut/Bas) — généralement la catégorie courante.
  final List<Channel> channels;
  final int startIndex;

  @override
  State<NativeTvPlayerScreen> createState() => _NativeTvPlayerScreenState();
}

class _NativeTvPlayerScreenState extends State<NativeTvPlayerScreen>
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
  static const int _btnCount = 4;
  bool _buffering = true;
  Timer? _hideTimer;
  Timer? _presenceTimer;
  Timer? _numTimer;
  Timer? _watchdog;
  Timer? _toastTimer;
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
  Set<String> _favIds = FavoritesRepository.instance.current;
  bool get _isFavorite => _favIds.contains(_current.id);

  // Anti-gel : on suit la progression réelle (position qui avance).
  DateTime _lastProgress = DateTime.now();
  Duration _lastPos = Duration.zero;
  bool _recovering = false;
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

  // Pause = position qui n'avance plus, mais ce n'est PAS un gel : le watchdog
  // ne doit alors NI reconnecter NI relancer la lecture tout seul (sinon le son
  // repartait même app minimisée). On distingue la pause volontaire (touche
  // lecture/pause) de la mise en arrière-plan (Home / multitâche).
  bool _userPaused = false;
  bool _inBackground = false;
  DateTime? _pausedAt; // début de la pause → rejoindre le direct si elle a duré

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
    WidgetsBinding.instance.addObserver(this);
    // Le décodage (MediaCodec matériel + repli logiciel), le tampon réseau et
    // le User-Agent sont gérés côté natif (NativeVideoView.kt). Ici on se
    // contente de piloter l'URL et d'écouter l'état.
    _controller = NativeVideoController(initialUrl: _current.streamUrl);
    _controller.addListener(_onPlayer);
    // Favoris en direct (le ❤ se met à jour tout seul).
    FavoritesRepository.instance.initialize();
    _favSub = FavoritesRepository.instance.favoritesStream.listen((Set<String> ids) {
      if (mounted) setState(() => _favIds = ids);
    });
    _open(reuse: true); // historique / présence pour la 1re chaîne
    // Chien de garde : aucune progression depuis 15 s → reconnexion.
    _watchdog = Timer.periodic(_watchEvery, (_) {
      // En PAUSE (volontaire ou app en arrière-plan), la position n'avance
      // plus : ce n'est PAS un gel. Sans ce garde, le watchdog rechargeait le
      // flux après 15 s et la lecture redémarrait TOUTE SEULE (son compris,
      // même app minimisée). On repousse simplement l'échéance.
      if (_userPaused || _inBackground) {
        _lastProgress = DateTime.now();
        return;
      }
      if (!_recovering && DateTime.now().difference(_lastProgress) > _frozen) {
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
        _inBackground = true;
        _pausedAt ??= DateTime.now();
        _controller.pause();
      case AppLifecycleState.resumed:
        _inBackground = false;
        _lastProgress = DateTime.now(); // pas de reconnexion-éclair au retour
        if (!_userPaused) _resumePlayback();
      case AppLifecycleState.inactive:
        break; // transitions brèves (dialogue…) → on ne coupe pas
    }
  }

  /// Reprend la lecture après une pause. Sur du DIRECT, une pause de plus de
  /// quelques secondes rend la connexion serveur douteuse (tampon plein,
  /// socket coupée côté fournisseur) : reprendre « où on en était » = image
  /// qui repart quelques secondes puis GÈLE en attendant le watchdog. On
  /// RE-OUVRE donc le flux (retour au direct immédiat, sans gel). Pour une
  /// micro-pause, un simple play() suffit (aucune interruption visuelle).
  static const Duration _staleAfterPause = Duration(seconds: 8);
  void _resumePlayback() {
    final DateTime? since = _pausedAt;
    _pausedAt = null;
    _lastProgress = DateTime.now();
    if (since != null &&
        DateTime.now().difference(since) > _staleAfterPause) {
      _controller.setUrl(_relayPlayUrl ?? _current.streamUrl);
    } else {
      _controller.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _presenceTimer?.cancel();
    _numTimer?.cancel();
    _watchdog?.cancel();
    _toastTimer?.cancel();
    _favSub?.cancel();
    // Si on quitte le lecteur en plein enregistrement : on finalise proprement
    // (arrêt du relais + clôture en base), sans toucher au controller détruit.
    if (_activeRecording != null) {
      final Recording rec = _activeRecording!;
      LocalStreamRelay.instance.stopRecording(rec.streamUrl ?? _current.streamUrl);
      RecordingRepository.instance.finishRecording(rec);
    }
    _controller.removeListener(_onPlayer);
    NowPlaying.instance.clear();
    SubscriptionState.instance.syncWithBackend(); // on ne regarde plus rien
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Écoute l'état du lecteur natif : progression (anti-gel), buffering (logo),
  // erreurs.
  void _onPlayer() {
    // Progression réelle → « pas gelé ». La lecture est repartie : on remet à
    // zéro le budget de reconnexion (et on lève un éventuel état d'erreur).
    if (_controller.position != _lastPos) {
      _lastPos = _controller.position;
      _lastProgress = DateTime.now();
      _recovering = false;
      _recoverAttempts = 0;
      if (_fatal && mounted) setState(() => _fatal = false);
    }
    // Logo tant qu'on bufferise OU que la 1re trame n'est pas encore dessinée
    // (au zap, firstFrame est remis à false → logo jusqu'à l'image suivante).
    final bool buffering = _controller.isBuffering || !_controller.firstFrame;
    if (mounted && buffering != _buffering) {
      setState(() => _buffering = buffering);
    }
    // Erreur / fin de flux live → reconnexion. Une erreur signifie que
    // l'essai EN COURS a définitivement échoué (le natif a épuisé ses
    // reconnexions silencieuses) : on lève donc le verrou _recovering, sinon
    // plus AUCUNE reconnexion ne partait (ni ici ni au watchdog, tous deux
    // bloqués par le verrou) → logo infini au lieu des essais bornés puis de
    // l'écran « Réessayer ».
    if (_controller.hasError || _controller.isEnded) {
      _recovering = false;
      _recover();
    }
  }

  void _open({bool reuse = false}) {
    _lastProgress = DateTime.now();
    _lastPos = Duration.zero;
    // Nouvelle chaîne → budget de reconnexion neuf, on lève tout état d'erreur.
    _recoverAttempts = 0;
    _recovering = false;
    // Zapper = vouloir regarder : on sort de l'état « en pause ».
    _userPaused = false;
    _pausedAt = null;
    if (mounted) setState(() {
      _buffering = true;
      _fatal = false;
    });
    if (!reuse) {
      // Nouvelle chaîne → on charge la nouvelle URL dans le MÊME lecteur.
      _controller.setUrl(_current.streamUrl);
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
    // En Dart, `a % n` est TOUJOURS dans [0, n) pour n > 0 → pas de wrap négatif
    // à corriger (l'ancienne ligne `if (_index < 0)` était du code mort).
    setState(() => _index = (_index + delta) % n);
    _open();
  }

  void _recover() {
    if (_recovering || _fatal) return;
    // BORNE (P1-6) : au-delà de _kMaxRecover ré-ouvertures sans reprise, on
    // ARRÊTE la boucle de reconnexion et on bascule en erreur explicite avec
    // « Réessayer » manuel — fini la boucle CPU/réseau infinie sur flux mort.
    if (_recoverAttempts >= _kMaxRecover) {
      if (mounted) setState(() {
        _fatal = true;
        _buffering = false;
      });
      return;
    }
    _recoverAttempts++;
    _recovering = true;
    _lastProgress = DateTime.now();
    // Ré-ouvre la MÊME source : l'URL locale du relais si on enregistre, sinon
    // l'URL directe. = reconnexion au direct sans casser l'enregistrement.
    _controller.setUrl(_relayPlayUrl ?? _current.streamUrl);
  }

  /// « Réessayer » manuel depuis l'écran d'erreur : on repart d'un budget neuf.
  void _manualRetry() {
    setState(() {
      _fatal = false;
      _recoverAttempts = 0;
      _buffering = true;
    });
    _controller.setUrl(_relayPlayUrl ?? _current.streamUrl);
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
    final String realUrl = _current.streamUrl;
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
        _flash('Enregistrement en cours…');
      }
    } catch (e) {
      _flash('Erreur enregistrement');
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
    final String realUrl = rec.streamUrl ?? _current.streamUrl;
    int bytes = 0;
    try {
      bytes = await LocalStreamRelay.instance.stopRecording(realUrl);
      await RecordingRepository.instance.finishRecording(rec);
    } catch (_) {}
    if (resumeDirect && mounted) {
      _controller.setUrl(_current.streamUrl);
    }
    if (mounted) {
      _flash(bytes > 0
          ? 'Enregistrement sauvegardé (${_humanSize(bytes)})'
          : 'Enregistrement vide');
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
      case 3:
        _openMultiView();
        break;
    }
  }

  // MULTI-VUE (2 chaînes) : réservée aux box assez puissantes (2 décodeurs).
  // Sur une petite box, on n'essaie PAS (message) → on protège la stabilité.
  void _openMultiView() {
    if (!multiViewSupported()) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Multi-vue indisponible : appareil trop limité '
              '(2 flux simultanés non garantis).'),
          duration: Duration(seconds: 3),
        ),
      );
      _showOverlayTemporarily();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvMultiViewScreen(
          channels: widget.channels,
          startIndex: _index,
        ),
      ),
    );
    _showOverlayTemporarily();
  }

  // Ouvre le GUIDE de la chaîne en cours : émission actuelle + « à suivre »,
  // avec possibilité de poser une ALARME (rappel) sur un programme.
  void _openGuide() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvChannelProgramsScreen(channel: _current),
      ),
    );
    _showOverlayTemporarily();
  }

  // Lecture/pause (touche média OU bouton tactile). setState pour rafraîchir
  // l'icône ▶/⏸ des contrôles tactiles.
  void _togglePlayPause() {
    if (_controller.isPlaying) {
      _userPaused = true;
      _pausedAt ??= DateTime.now();
      _controller.pause();
    } else {
      _userPaused = false;
      _resumePlayback(); // pause longue → on rejoint le direct (pas de gel)
    }
    _showOverlayTemporarily();
    setState(() {});
  }

  // Ajoute / retire la chaîne courante des favoris (bouton ❤ / touche F).
  void _toggleFavorite() {
    final bool wasFav = _isFavorite;
    FavoritesRepository.instance.toggle(_current.id);
    _flash(wasFav ? 'Retiré des favoris' : 'Ajouté aux favoris ❤');
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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
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
    return PopScope(
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
              // Écran de marque UNIQUEMENT tant que la 1re image de la chaîne
              // n'est pas rendue (ouverture / zap / reconnexion, où setUrl
              // remet firstFrame à false). Un re-buffering EN COURS de lecture
              // ne couvre PLUS tout l'écran : la dernière image reste affichée
              // (SurfaceView) avec un petit spinner discret par-dessus → une
              // micro-coupure réseau d'1 s ne « casse » plus la séance.
              if (!_controller.firstFrame && !_fatal)
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
              // Re-buffering en cours de lecture : spinner discret, image gardée.
              if (_controller.firstFrame && _buffering && !_fatal)
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const CircularProgressIndicator(
                        strokeWidth: 3, color: TvTokens.gold),
                  ),
                ),
              // Écran d'ERREUR (P1-6) : la reconnexion automatique a été épuisée
              // (flux durablement injoignable). On ARRÊTE de boucler et on offre
              // un « Réessayer » manuel (OK) ou « Quitter » (Retour).
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
                            style: TextStyle(
                                fontSize: TvDimens.title,
                                fontWeight: FontWeight.w800,
                                color: TvTokens.text)),
                        const SizedBox(height: 8),
                        Text('Chaîne indisponible pour le moment.',
                            style: TextStyle(
                                fontSize: TvDimens.body,
                                color: TvTokens.mutedDim)),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                          decoration: BoxDecoration(
                            color: TvTokens.sel,
                            borderRadius:
                                BorderRadius.circular(TvTokens.rButton),
                            border: Border.all(
                                color: TvTokens.gold,
                                width: TvDimens.focusOutline),
                          ),
                          child: Text('OK : Réessayer   ·   Retour : Quitter',
                              style: TextStyle(
                                  fontSize: TvDimens.titleS,
                                  fontWeight: FontWeight.w700,
                                  color: TvTokens.goldBright)),
                        ),
                      ],
                    ),
                  ),
                ),
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
                        onMulti: _openMultiView,
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
    required this.onMulti,
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
  final VoidCallback onMulti;

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
                label: 'Guide',
                onTap: onGuide,
                focused: focusedIndex == 0,
              ),
              const SizedBox(width: 34),
              _CtrlButton(
                icon: isRecording
                    ? Icons.stop_rounded
                    : Icons.fiber_manual_record_rounded,
                label: isRecording ? 'Stop' : 'REC',
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
                label: 'Favori',
                onTap: onFavorite,
                accent: TvTokens.gold,
                active: isFavorite,
                focused: focusedIndex == 2,
              ),
              const SizedBox(width: 34),
              _CtrlButton(
                icon: Icons.grid_view_rounded,
                label: 'Multi',
                onTap: onMulti,
                focused: focusedIndex == 3,
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
    final Color accent = widget.accent ?? TvTokens.gold;
    // Surlignage D-pad = anneau OR épais + halo : visible sur N'IMPORTE quelle
    // télécommande (le repère « où je suis »).
    final Color borderColor = widget.focused
        ? TvTokens.gold
        : (widget.active ? accent : Colors.white24);
    final Color bg = widget.focused
        ? TvTokens.gold.withValues(alpha: 0.28)
        : (widget.active
            ? accent.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.42));
    final Color iconColor = widget.focused
        ? TvTokens.gold
        : (widget.active ? accent : TvTokens.text);
    final Color labelColor = widget.focused
        ? TvTokens.gold
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
                            color: TvTokens.gold.withValues(alpha: 0.45),
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
