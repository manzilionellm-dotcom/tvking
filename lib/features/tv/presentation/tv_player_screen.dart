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
import 'dart:io'
    show File, HttpClient, HttpClientRequest, HttpClientResponse;
import 'dart:typed_data' show ByteData, Uint8List;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/observability/structured_logger.dart';
import '../core/tv_tokens.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../player/data/local_stream_relay.dart';
import '../../player/data/player_settings.dart';
import '../../player/presentation/aspect_mode_label.dart';
import '../../player/presentation/track_language_label.dart';
import '../../player/data/stream_blocked_fallback.dart';
import '../../player/data/stream_diagnostics.dart';
import '../../player/data/xtream_url_variants.dart';
import '../../playlists/data/xtream_url_format_store.dart';
import '../../playlists/domain/playlist.dart' as pl;
import '../../playlists/data/favorites_repository.dart';
import '../../recordings/data/recording_repository.dart';
import '../../recordings/domain/recording.dart';
import '../../subscription/data/now_playing.dart';
import '../../subscription/data/subscription_state.dart';
import '../../vod/data/playback_position_repository.dart';
import '../../vod/data/vod_download_service.dart';
import '../../hue/data/hue_service.dart';
import '../data/autoplay_policy.dart';
import '../data/cine_perf.dart';
import '../data/failure_explainer.dart';
import '../data/freeze_recovery_policy.dart';
import '../data/playback_failure_log.dart';
import '../data/quality_ladder.dart';
import '../data/stream_stability_monitor.dart';
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
  // déplacent le surlignage, OK active.
  // Ordre : 0=Guide 1=REC 2=Favori 3=Multi 4=Pistes.
  int _btnFocus = -1;
  static const int _btnCount = 5;

  // ----- Feuille « Pistes & format d'image » (audio/sous-titres/ratio) ---
  // Panneau latéral focus-émulé (même modèle que la carte « À suivre ») :
  // quand il est visible, _onKey lui détourne tout le D-pad.
  bool _tracksVisible = false;
  int _tracksFocus = 0;

  /// Mode d'affichage courant (persisté via PlayerSettings — partagé
  /// avec le lecteur mobile, SANS dépendre de media_kit).
  AspectRatioMode _aspect = PlayerSettings.instance.aspectMode;
  bool _buffering = true;
  Timer? _hideTimer;
  Timer? _presenceTimer;
  Timer? _numTimer;
  Timer? _watchdog;
  Timer? _toastTimer;
  Timer? _zapSettle;
  String _numBuffer = ''; // saisie d'un numéro de chaîne (touches 0-9)

  // ----- « Dernière chaîne » (recall, style câble US) -----
  // Index de la chaîne d'AVANT le dernier changement : « 0 » seul y retourne
  // (match ↔ film en un appui). Un numéro de chaîne ne commence jamais par 0.
  int? _prevIndex;

  // ----- « Tu regardes encore ? » (anti-gaspillage bande passante) -----
  // Après _kStillAfter SANS toucher la télécommande, on met en PAUSE et on
  // demande. N'importe quelle touche reprend la lecture. Jamais pendant un
  // enregistrement. (Netflix fait pareil ; ici ça évite au client de laisser
  // le flux tourner toute la nuit → économise le serveur et la data.)
  static const Duration _kStillAfter = Duration(hours: 4);
  DateTime _lastUserAction = DateTime.now();
  Timer? _stillTimer;
  bool _askStillWatching = false;

  // ----- « À suivre » (autoplay épisode suivant — pilier du binge) -----
  // Toute la DÉCISION (épisode avec suivant ? garde-fou 3 enchaînements ?
  // annulation mémorisée ?) vit dans AutoplayPolicy, une machine à états
  // PURE et testée (cf. autoplay_policy.dart) — ici il ne reste que la
  // plomberie : un Timer d'1 s pour le compte à rebours et la carte.
  // AUCUN effet en live ni pour un film isolé (gardé par la policy).
  final AutoplayPolicy _autoplay = AutoplayPolicy();
  Timer? _upNextTimer;

  /// Fermeture auto de la feuille « Pistes » (10 s d'inactivité).
  Timer? _tracksAutoClose;
  bool _upNextVisible = false;
  bool _upNextAuto = true; // false = garde-fou atteint → attend un OK
  int _upNextSeconds = 0;
  int _upNextBtn = 0; // bouton surligné : 0 = Lire maintenant, 1 = Annuler

  // ----- Enregistrement -----
  // Quand on enregistre, on fait passer la lecture par le MINI-RELAIS local
  // (LocalStreamRelay) : il ouvre UNE seule connexion vers le serveur IPTV et
  // recopie les octets À LA FOIS vers le lecteur ET vers le fichier .ts. Donc
  // le fournisseur ne voit qu'1 connexion (compatible max_connections=1) et le
  // fichier capture EXACTEMENT ce qui est à l'écran. Hors enregistrement, la
  // lecture reste DIRECTE (le relais n'est pas dans le chemin).
  Recording? _activeRecording;
  bool get _isRecording => _activeRecording != null;
  String?
      _relayPlayUrl; // URL locale 127.0.0.1 utilisée pendant l'enregistrement
  String? _toastMsg; // petit message éphémère (sauvegardé / vide / échec)

  // ----- Favoris -----
  // On suit l'ensemble des IDs favoris en direct (le du lecteur reflète
  // instantanément l'ajout/retrait, et reste à jour au zap).
  StreamSubscription<Set<String>>? _favSub;
  Set<String> _favIds = FavoritesRepository.instance.current;
  bool get _isFavorite => _favIds.contains(_current.id);

  // ----- Reprise de lecture VOD (« Reprendre à 42:15 », façon Netflix) -----
  // Position sauvegardée à appliquer dès que le flux est PRÊT (durée connue).
  // On ne seek PAS avant : un seekTo lancé pendant la préparation d'ExoPlayer
  // peut être ignoré — la durée n'est émise par le natif qu'une fois le média
  // préparé et seekable, c'est donc LE signal fiable. `_resumeApplied` évite
  // de re-seeker après (reconnexion anti-gel, seek manuel de l'utilisateur).
  Duration? _pendingResume;
  bool _resumeApplied = false;

  // ----- Seek Netflix : double-appui = 30 s + bulle de temps -----
  // Deux appuis Gauche/Droite RAPPROCHÉS (même sens, < 500 ms) passent le
  // pas de 10 s à 30 s — pour traverser un générique sans marteler. La
  // bulle au-dessus de la barre montre le TEMPS CIBLE pendant qu'on seek.
  DateTime? _lastSeekTapAt;
  int _lastSeekDir = 0; // -1 recul, +1 avance, 0 = aucun seek récent
  Duration? _seekPreview; // temps cible affiché dans la bulle (null = cachée)
  Timer? _seekPreviewTimer;

  // ----- « Épisode suivant » pendant le générique (30 dernières secondes) --
  // La pastille apparaît en bas à droite sur la FIN d'un épisode : OK =
  // enchaîner tout de suite (regarder le générique = ne rien faire). Retour
  // possible en arrière → elle disparaît. Remis à zéro à chaque _open.
  bool _endPillVisible = false;

  // Anti-gel : on suit la progression réelle (position qui avance).
  Duration _lastPos = Duration.zero;
  static const Duration _watchEvery = Duration(seconds: 4);
  // Machine à états anti-gel EXTRAITE + TESTÉE (cf. freeze_recovery_policy.dart
  // et son test unitaire) : gel détecté après 15 s sans progression, 5
  // reconnexions bornées (P1-6) avant l'écran d'erreur avec « Réessayer ».
  // Le bug du spinner infini (2026-07-06 : verrou jamais relâché, borne
  // inatteignable) vivait dans cette logique — elle est désormais isolée du
  // widget pour ne plus jamais régresser silencieusement.
  final FreezeRecoveryPolicy _freeze =
      FreezeRecoveryPolicy(now: DateTime.now());
  bool _fatal = false;
  // True dès qu'une vraie image a été affichée pour la chaîne courante. Si on
  // échoue SANS jamais avoir eu d'image → source vide / bloquée par le
  // fournisseur (≠ coupure réseau d'un flux qui jouait). Remis à false à chaque
  // ouverture (_open).
  bool _everShownFrame = false;
  // Erreur ExoPlayer déjà journalisée pour cette ouverture (le listener
  // est appelé à chaque tick — on n'écrit qu'une fois). Remis à false
  // dans _open.
  bool _errorLoggedThisOpen = false;
  // `true` si le diagnostic a conclu à un blocage RÉSEAU (DNS/timeout)
  // plutôt qu'à un souci de signature — affiche un indice VPN/FAI en plus
  // du message existant. Remis à false à chaque ouverture (_open).
  bool _fatalNetworkHint = false;

  // `true` quand l'écran fatal vient d'un EXCÈS DE REBUFFERING (ça « tourne »
  // trop) : on affiche alors au client, noir sur blanc, que sa connexion est
  // trop faible (problème réseau côté client/fournisseur, pas l'app). Remis à
  // false à chaque ouverture (_open).
  bool _weakConnectionFatal = false;

  // ----- STABILITÉ « pro » (façon Netflix) : 2 garde-fous anti-spinner -----
  // 1) COUPURE RAPIDE SUR FLUX MORT : si AUCUNE image n'est dessinée en
  //    [_kStartupTimeout] après l'ouverture, on ne laisse PAS le spinner
  //    tourner ~75 s (5×15 s du watchdog anti-gel) → on déclenche tout de
  //    suite le diagnostic/cascade (_declareChannelBlocked), qui aboutit à un
  //    flux de secours OU à l'écran « Réessayer ». Armé à chaque _open,
  //    désarmé dès la 1re image.
  Timer? _startupWatchdog;
  static const Duration _kStartupTimeout = Duration(seconds: 20);

  // 2) GARDE-FOU ANTI-BOUCLE INFINIE : un flux qui « hoquette » sans arrêt
  //    (rebuffer en rafale) ne doit pas tourner indéfiniment. On garde les
  //    horodatages des rebuffers RÉELS sur une fenêtre glissante ; au-delà de
  //    [_kMaxRebuffers] dans [_kRebufferWindow], on bascule proprement en
  //    erreur « Réessayer » au lieu de spinner sans fin. La fenêtre glissante
  //    fait que quelques rebuffers espacés ne déclenchent JAMAIS (seul un flux
  //    vraiment instable atteint le seuil). Remis à zéro à chaque _open/zap.
  final List<DateTime> _rebufferTimes = <DateTime>[];
  static const int _kMaxRebuffers = 10;
  static const Duration _kRebufferWindow = Duration(minutes: 4);

  // ----- ABR MAISON (« la qualité s'adapte, la connexion reste ») -----
  // L'ABR classique (Netflix) n'existe pas sur un flux TS mono-débit. Notre
  // équivalent : le moniteur de stabilité (machine à états PURE et testée,
  // cf. stream_stability_monitor.dart) écoute les gels + le débit
  // d'ingestion du relais ; quand la connexion ne suit plus, on bascule
  // AUTOMATIQUEMENT sur la déclinaison de qualité inférieure de la MÊME
  // chaîne trouvée dans la liste (« TF1 FHD » → « TF1 HD », cf.
  // quality_ladder.dart), et on remonte tout seul quand c'est stable.
  final StreamStabilityMonitor _stability = StreamStabilityMonitor();
  // Index de la chaîne D'ORIGINE quand on joue une déclinaison dégradée
  // (null = on est à la qualité choisie par l'utilisateur).
  int? _qualityOriginIndex;
  // Compteur de pertes upstream du relais déjà comptabilisées (delta →
  // incidents du moniteur).
  int _seenUpstreamReconnects = 0;
  // Dernier état "buffering" observé (détection des transitions).
  bool _wasBuffering = true;

  // Chaîne « échec → sonde → cascade de formats » : LE MÊME contrôleur que
  // sur téléphone (StreamBlockedFallback), branché sur les échecs définitifs
  // du relais. Terrain 2026-07-09 : ce panel sert l'URL NUE
  // `host/USER/PASS/ID.ts` en 404 — il faut la variante `/live/…m3u8` (ce
  // que fait IBO). La TV n'avait qu'une sonde de signature, jamais la
  // cascade de formats → écran noir. Ce contrôleur apporte les deux.
  late final StreamBlockedFallback _fallback;
  // Variante de format adoptée par la cascade (`.ts` → `/live/…m3u8`…),
  // réutilisée à chaque (ré)ouverture. Remise à null au zap.
  String? _adoptedAltUrl;

  Channel get _current => widget.channels[_index];

  /// URL effective à (ré)ouvrir : variante adoptée par la cascade sinon
  /// l'URL live de la chaîne.
  String get _effectiveUrl => _adoptedAltUrl ?? _current.streamUrl;

  static const List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static const List<LogicalKeyboardKey> _numpad = <LogicalKeyboardKey>[
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
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
    // Cascade « échec → sonde → formats » (parité téléphone) : branchée sur
    // les échecs définitifs du relais. Elle possède l'anti-boucle par chaîne.
    _fallback = StreamBlockedFallback(
      getChannel: () => _current,
      getOverrideUrl: () => null, // TV live (le replay a son propre écran)
      getEffectiveUrl: () => _effectiveUrl,
      isAlive: () => mounted,
      hasDecodedFrames: () => _everShownFrame,
      getAdoptedAltUrl: () => _adoptedAltUrl,
      setAdoptedAltUrl: (String? url) => _adoptedAltUrl = url,
      resetWatchdogBudget: () => _freeze.openChannel(DateTime.now()),
      reopen: (String _) => unawaited(_loadCurrentUrl()),
      showBlocked: (String _) {
        // Échec DÉFINITIF (toute la cascade signatures + formats a échoué) →
        // gravé dans le journal de la Boîte noire des Réglages. La cascade
        // possède le contexte fin ; ici on capture les codes ExoPlayer réels.
        _recordPlaybackFailure();
        if (!mounted) return;
        setState(() {
          _fatal = true;
          _buffering = false;
        });
      },
    )..attach();
    // Favoris en direct (le se met à jour tout seul).
    FavoritesRepository.instance.initialize();
    _favSub =
        FavoritesRepository.instance.favoritesStream.listen((Set<String> ids) {
      if (mounted) setState(() => _favIds = ids);
    });
    _open(reuse: true); // historique / présence pour la 1re chaîne
    // Chien de garde : aucune progression depuis 15 s → reconnexion
    // (décision déléguée à _freeze, cf. FreezeRecoveryPolicy.onTick).
    // Le MÊME tick (toutes les 4 s) sert AUSSI de sauvegarde périodique de la
    // position VOD (reprise « Reprendre à 42:15 ») : pas de timer de plus →
    // zéro réveil supplémentaire, zéro coût quand on est en DIRECT (no-op).
    _stability.openChannel(DateTime.now());
    _watchdog = Timer.periodic(_watchEvery, (_) {
      _onFreezeAction(_freeze.onTick(DateTime.now()));
      _savePlaybackPosition();
      _stabilityTick();
    });
    // Garde l'app « en ligne » + chaîne à jour pendant le visionnage.
    _presenceTimer = Timer.periodic(const Duration(minutes: 3),
        (_) => SubscriptionState.instance.syncWithBackend());
    // « Tu regardes encore ? » : vérification 1×/min, déclenchée seulement
    // après _kStillAfter d'inactivité totale (et jamais en enregistrement).
    _stillTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_askStillWatching || _isRecording) return;
      if (DateTime.now().difference(_lastUserAction) >= _kStillAfter) {
        _controller.pause();
        if (mounted) setState(() => _askStillWatching = true);
      }
    });
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
        // L'OS peut TUER l'app une fois en arrière-plan (Home, multitâche) :
        // on fige la position VOD MAINTENANT pour ne pas perdre la reprise.
        _savePlaybackPosition();
        _controller.pause();
      case AppLifecycleState.resumed:
        _controller.play();
      case AppLifecycleState.inactive:
        break; // transitions brèves (dialogue…) → on ne coupe pas
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Le lecteur se ferme → le réseau est libre : la file de téléchargements
    // Cinéma peut repartir (elle patientait pendant toute lecture réseau).
    VodDownloadService.instance.setPlaybackHold(false);
    // Hue : sortie du film → chaque lampe revient exactement comme avant.
    unawaited(HueService.instance.cinemaEnd());
    _hideTimer?.cancel();
    _presenceTimer?.cancel();
    _numTimer?.cancel();
    _stillTimer?.cancel();
    _watchdog?.cancel();
    _toastTimer?.cancel();
    _zapSettle?.cancel();
    _upNextTimer?.cancel();
    _tracksAutoClose?.cancel();
    _seekPreviewTimer?.cancel();
    // Lecteur quitté avant la 1re image → la mesure TTFF ne veut rien dire.
    CinePerf.cancel(CinePerf.playToFirstFrame);
    _favSub?.cancel();
    _fallback.detach();
    // Si on quitte le lecteur en plein enregistrement : on finalise proprement
    // (arrêt du relais + clôture en base), sans toucher au controller détruit.
    if (_activeRecording != null) {
      final Recording rec = _activeRecording!;
      LocalStreamRelay.instance
          .stopRecording(rec.streamUrl ?? _current.streamUrl);
      RecordingRepository.instance.finishRecording(rec);
    }
    // Position VOD au moment de QUITTER le lecteur (Back) : c'est LA
    // sauvegarde qui compte le plus — celle que « Continuer à regarder »
    // affichera. À faire AVANT _controller.dispose() (après, la position
    // n'est plus lisible). Fire-and-forget : l'écriture prefs survit au pop.
    _savePlaybackPosition();
    _controller.removeListener(_onPlayer);
    NowPlaying.instance.clear();
    // « On ne regarde plus rien » : DIFFÉRÉ de 1,5 s — lancer une requête
    // HTTP pile pendant la transition de pop réveillait réseau/CPU au
    // moment où l'écran suivant doit devenir interactif. Effet global
    // (singleton) : il survit à ce State sans fuite.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 1500),
        () => SubscriptionState.instance.syncWithBackend()));
    _startupWatchdog?.cancel();
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
      _freeze.onProgress(DateTime.now());
      if (_fatal && mounted)
        setState(() => _fatal = false);
      // FILM : quand la barre est visible, on la fait AVANCER (tick 500 ms du
      // natif). Uniquement en VOD + overlay → aucun rebuild inutile en direct.
      else if (_isVod && _overlay && mounted) {
        setState(() {});
      }
    }
    // Une vraie image a été dessinée → la source envoie bien de la vidéo.
    if (_controller.firstFrame) {
      // BUDGET « Regarder → première frame » (VOD, cible < 2,5 s) : le chrono
      // part de l'appui (fiche/accueil) ou de l'_open (reprise directe), et
      // s'arrête ICI, à la toute première image de CETTE ouverture.
      if (!_everShownFrame &&
          _isVod &&
          CinePerf.isRunning(CinePerf.playToFirstFrame)) {
        CinePerf.end(CinePerf.playToFirstFrame, detail: _current.name);
      }
      _everShownFrame = true;
      _startupWatchdog?.cancel(); // 1re image → garde-fou démarrage inutile
    }
    // Reprise VOD : dès que la DURÉE est connue (média préparé + seekable),
    // on peut appliquer le « Reprendre à 42:15 ». No-op en direct / déjà fait.
    if (_isVod) _maybeApplyResume();
    // ----- Pastille « Épisode suivant » sur les 30 DERNIÈRES SECONDES -----
    // « Regarder le générique ou passer » : sur la fin d'un ÉPISODE avec un
    // suivant, une pastille discrète apparaît (OK = enchaîner). Revenir en
    // arrière (> 30 s de la fin) la fait disparaître. Films/live : jamais.
    if (_isVod) {
      final Duration total = _controller.duration;
      final bool nearEnd = total > Duration.zero &&
          total - _controller.position <= const Duration(seconds: 30);
      final bool pill = nearEnd &&
          _everShownFrame &&
          !_upNextVisible &&
          !_controller.isEnded &&
          _autoplay.canPropose(
              isLive: _current.isLive,
              currentId: _current.id,
              nextId: _nextUpChannel?.id);
      if (pill != _endPillVisible && mounted) {
        setState(() => _endPillVisible = pill);
      }
    }
    // Logo tant qu'on bufferise OU que la 1re trame n'est pas encore dessinée
    // (au zap, firstFrame est remis à false → logo jusqu'à l'image suivante).
    final bool buffering = _controller.isBuffering || !_controller.firstFrame;
    // Capteur ABR : un REBUFFER réel (l'image tournait, elle s'interrompt)
    // = incident pour le moniteur de stabilité. Le buffering INITIAL d'une
    // ouverture/zap n'en est pas un (gardé par _everShownFrame).
    if (buffering && !_wasBuffering && _everShownFrame && !_isVod) {
      final DateTime now = DateTime.now();
      _stability.onIncident(now);
      _noteRebufferBudget(now); // garde-fou anti-boucle infinie
    }
    _wasBuffering = buffering;
    if (mounted && buffering != _buffering) {
      setState(() => _buffering = buffering);
    }
    // FILM terminé (générique atteint) → on OUBLIE sa position : il ne doit
    // plus apparaître dans « Continuer à regarder » (règle des 95 % du repo,
    // appliquée ici aussi car un flux terminé n'émet plus de position).
    if (_isVod && _controller.isEnded) {
      unawaited(PlaybackPositionRepository.instance.markFinished(_current.id));
      // TÉLÉCHARGEMENTS INTELLIGENTS (Netflix) : l'épisode terminé était
      // téléchargé → son fichier est supprimé (il est vu, la place se
      // libère) ; et le SUIVANT part en file — il se téléchargera dès que
      // le réseau sera libre. Un FILM n'est jamais concerné : le service
      // ne supprime que des épisodes, et on ne fournit `next` que si la
      // liste du lecteur en a un (donc une saison, jamais un film seul).
      final Channel? nextEp = _nextUpChannel;
      unawaited(VodDownloadService.instance.onEpisodeWatched(
        watchedId: _current.id,
        next: nextEp == null || nextEp.isLive
            ? null
            : VodNextEpisode(
                id: nextEp.id,
                name: nextEp.cleanName,
                streamUrl: nextEp.streamUrl,
                posterUrl: nextEp.logoUrl,
                groupName: nextEp.category,
              ),
      ));
      // ÉPISODE de série avec un suivant → l'overlay « À suivre » prend la
      // main sur cette fin : on N'ENTRE PAS dans la reconnexion anti-gel
      // ci-dessous (elle rouvrirait l'épisode terminé pendant le compte à
      // rebours). Films, fin de saison et live → chemin existant inchangé.
      if (_handleVodEnded()) return;
    }
    // Erreur / fin de flux live → reconnexion.
    if (_controller.hasError || _controller.isEnded) {
      // Diagnostic terrain (P1-6) : errorCodeName est une constante Media3
      // STABLE (ex. "ERROR_CODE_IO_BAD_HTTP_STATUS") — bien plus exploitable
      // à distance que le message brut, souvent vague ("Source error").
      if (_controller.hasError) {
        StructuredLogger.instance.warn(
          domain: 'native',
          event: 'tv_player.error',
          ctx: <String, Object?>{
            'channelId': _current.id,
            'everShownFrame': _everShownFrame,
            'errorCodeName': _controller.lastErrorCodeName,
            'errorCode': _controller.lastErrorCode,
            'message': _controller.lastErrorMessage,
          },
        );
        // BOÎTE NOIRE : l'erreur ExoPlayer, UNE fois par ouverture. Sans
        // ça la lecture HLS directe (qui contourne le relais) échouait en
        // SILENCE — journal vide alors que l'écran est noir (terrain
        // 2026-07-09). Rend visible le vrai code Media3.
        if (!_errorLoggedThisOpen) {
          _errorLoggedThisOpen = true;
          StreamDiagnostics.instance.recordEvent(
            'exoplayer',
            'ExoPlayer : ${_controller.lastErrorCodeName ?? 'erreur'}'
                '${_controller.lastErrorCode == null ? '' : ' (${_controller.lastErrorCode})'}'
                ' — ${_controller.lastErrorMessage ?? 'lecture impossible'}',
            level: 'error',
          );
        }
      }
      _onFreezeAction(_freeze.onPlayerError(DateTime.now()));
    }
  }

  /// Arme (ou réarme) le garde-fou de DÉMARRAGE : si aucune image n'est
  /// dessinée dans [_kStartupTimeout], on déclenche le diagnostic/cascade au
  /// lieu de laisser le spinner tourner ~75 s. Désarmé dès la 1re image.
  void _armStartupWatchdog() {
    _startupWatchdog?.cancel();
    _startupWatchdog = Timer(_kStartupTimeout, () {
      if (!mounted || _everShownFrame || _fatal) return;
      StructuredLogger.instance.warn(
        domain: 'native',
        event: 'tv_player.startup_timeout',
        ctx: <String, Object?>{'channelId': _current.id},
      );
      // Toujours rien après ~20 s → source morte/bloquée : cascade de secours
      // (UA/variantes) → flux OK, ou écran « Réessayer ». Jamais un spinner
      // éternel. `_declareChannelBlocked` est borné (1 diagnostic par chaîne).
      _declareChannelBlocked();
    });
  }

  /// Garde-fou ANTI-BOUCLE INFINIE : enregistre un rebuffer réel, purge la
  /// fenêtre glissante, et si le flux hoquette trop ([_kMaxRebuffers] en
  /// [_kRebufferWindow]) → écran « Réessayer » au lieu d'un spinner sans fin.
  void _noteRebufferBudget(DateTime now) {
    _rebufferTimes.add(now);
    _rebufferTimes
        .removeWhere((DateTime t) => now.difference(t) > _kRebufferWindow);
    if (_rebufferTimes.length >= _kMaxRebuffers && !_fatal) {
      StructuredLogger.instance.warn(
        domain: 'native',
        event: 'tv_player.rebuffer_budget_exceeded',
        ctx: <String, Object?>{
          'channelId': _current.id,
          'count': _rebufferTimes.length,
        },
      );
      _rebufferTimes.clear();
      _recordPlaybackFailure();
      // Ça « tourne » trop : cause = connexion trop faible / serveur lent. On
      // le trace dans la boîte noire et on écrit clairement au client que
      // c'est son réseau (pas l'app).
      StreamDiagnostics.instance.recordEvent(
        'native',
        'Connexion trop faible / serveur lent — trop de coupures de '
            'chargement (${_kMaxRebuffers} en ${_kRebufferWindow.inMinutes} '
            'min) → message client affiché (problème réseau côté client ou '
            'fournisseur, pas l\'app).',
        level: 'warn',
      );
      if (mounted) {
        setState(() {
          _fatal = true;
          _weakConnectionFatal = true;
          _buffering = false;
        });
      }
    }
  }

  void _open({bool reuse = false}) {
    _freeze.openChannel(DateTime.now());
    _lastPos = Duration.zero;
    _everShownFrame = false; // nouvelle ouverture → pas encore d'image
    _rebufferTimes.clear(); // nouvelle chaîne → budget rebuffer neuf
    _armStartupWatchdog(); // coupure rapide si aucune image en ~20 s
    _fatalNetworkHint = false;
    _weakConnectionFatal = false;
    _errorLoggedThisOpen = false; // nouvelle ouverture → on re-journalise
    _adoptedAltUrl =
        null; // la variante adoptée était propre à l'ancienne chaîne
    // Nouveau contenu → la carte « À suivre » de l'ancien n'a plus de sens.
    _upNextTimer?.cancel();
    _upNextVisible = false;
    _endPillVisible = false; // pastille fin d'épisode : propre à l'ancien
    // Reprise VOD : état neuf pour CE contenu, puis lecture (asynchrone,
    // quelques ms) de la position sauvegardée. Le seek lui-même n'aura lieu
    // que quand le flux sera prêt (durée connue, cf. _maybeApplyResume).
    _resumeApplied = false;
    _pendingResume = null;
    if (_isVod) {
      // BUDGET « Regarder → première frame » : si l'écran amont (fiche,
      // rangée Reprendre) a déjà lancé le chrono à l'appui, on le garde
      // (mesure complète) ; sinon (zap épisode suivant, reprise directe)
      // il part d'ici. Arrêté à la 1re image (cf. _onPlayer).
      if (!CinePerf.isRunning(CinePerf.playToFirstFrame)) {
        CinePerf.start(CinePerf.playToFirstFrame);
      }
      unawaited(_loadResumePoint());
    }
    if (mounted)
      setState(() {
        _buffering = true;
        _fatal = false;
      });
    // Charge la chaîne courante VIA LE RELAIS (parité téléphone) : le
    // relais ouvre l'unique connexion, gère la reconnexion, et surtout
    // résout les domaines bloqués par le DNS opérateur en DoH
    // (installDohResolution) — le lecteur natif ExoPlayer, lui, fait sa
    // propre résolution et échouerait sur ces domaines. `reuse` n'a plus
    // d'effet sur l'URL : même à la 1re ouverture on bascule sur le
    // relais (le lecteur a été créé sur l'URL directe le temps d'un
    // battement).
    unawaited(_loadCurrentUrl());
    // Historique (reprise « Continuer à regarder », favoris, reco).
    RecentlyWatchedRepository.instance.record(_current.id);
    NowPlaying.instance.set(_current.cleanName);
    SubscriptionState.instance.syncWithBackend();
    _showOverlayTemporarily();
  }

  /// Pointe le lecteur sur la chaîne courante EN PASSANT PAR LE RELAIS
  /// pour le live TS (1 connexion + reconnexion + résolution DoH des
  /// domaines bloqués par le FAI). Le HLS (.m3u8) reste en DIRECT : le
  /// relais est un tuyau TS, et ExoPlayer gère le HLS nativement (seule
  /// limite : le DoH ne couvre pas ce cas natif sur TV). Best-effort :
  /// si le relais ne démarre pas, on retombe sur l'URL directe.
  Future<void> _loadCurrentUrl({String? userAgent}) async {
    final Channel channel = _current;
    String realUrl = _effectiveUrl; // variante adoptée > URL chaîne
    // HORS-LIGNE D'ABORD (téléchargements Cinéma) : si CE contenu VOD a été
    // téléchargé, on joue le FICHIER LOCAL — démarrage instantané, zéro
    // réseau, zéro connexion consommée chez le fournisseur. On saute toute
    // la mécanique distante (formats mémorisés, relais, cascade : aucun
    // sens sur un fichier). On signale aussi « réseau libre » à la file de
    // téléchargements : c'est ce qui permet de REGARDER l'épisode local
    // pendant que le SUIVANT se télécharge (boucle Netflix).
    if (_isVod) {
      // Hue « salle de cinéma » IMMERSIVE : le film démarre → la pièce prend
      // la TEINTE DOMINANTE de l'affiche (bleu pour un sci-fi, ambre pour un
      // drame chaud). Calcul depuis l'image (jamais depuis la vidéo → zéro
      // risque box/1-connexion). Idempotent, best-effort — ne retarde jamais
      // la lecture (tout est unawaited).
      unawaited(_startHueImmersive(channel.logoUrl));
      // « TÉLÉCHARGER PENDANT QUE JE REGARDE » (façon YouTube) : si l'option
      // est active ET que le film n'est pas déjà local, on l'enregistre en
      // parallèle → hors-ligne à la fin. No-op si OFF (défaut) ou local.
      final String? already = VodDownloadService.instance.localFile(channel.id);
      if (already == null) {
        unawaited(VodDownloadService.instance.watchAlong(
          id: channel.id,
          name: channel.cleanName,
          streamUrl: channel.streamUrl,
          posterUrl: channel.logoUrl,
          category: channel.category,
        ));
      }
      final String? local = VodDownloadService.instance.localFile(channel.id);
      if (local != null && await File(local).exists()) {
        if (!mounted || channel.id != _current.id) return;
        _relayPlayUrl = null;
        VodDownloadService.instance.setPlaybackHold(false);
        _controller.setUrl(Uri.file(local).toString());
        return;
      }
    }
    // Lecture RÉSEAU (live ou VOD distante) → la file de téléchargements
    // patiente pour ne pas voler le créneau 1-connexion du panel.
    VodDownloadService.instance.setPlaybackHold(true);
    // FORMAT MÉMORISÉ (parité téléphone — corrige la tempête de connexions
    // terrain du 2026-07-09 02:20 : la TV re-cascadait à CHAQUE chaîne
    // depuis l'URL nue .ts → 8 sondes + cascade × zap → compte 1-connexion
    // saturé « 3/1 » → 404 partout). Si la cascade a déjà trouvé le format
    // gagnant pour cette source (ex. « live:m3u8 »), on l'applique DIRECT :
    // la chaîne ouvre sur /live/…m3u8 sans re-sonder. Seule la 1re chaîne
    // d'une source neuve cascade encore.
    if (_adoptedAltUrl == null) {
      final pl.Playlist? src = StreamBlockedFallback.xtreamPlaylistFor(channel);
      if (src?.id != null) {
        final XtreamContentType type =
            StreamBlockedFallback.contentTypeOf(channel);
        final String? code =
            await XtreamUrlFormatStore.instance.winningFormat(src!.id!, type);
        if (!mounted || channel.id != _current.id) return;
        // AUTO-CORRECTIF : on IGNORE un format HLS mémorisé pour du LIVE
        // (« live:m3u8 » / « none:m3u8 ») — il ouvre plusieurs connexions
        // et sature les comptes « max 1 connexion » → écran noir (terrain
        // 2026-07-09). La cascade re-valide (préférence .ts = 1 connexion)
        // et re-mémorise le bon format.
        final bool hlsLiveMemorized = type == XtreamContentType.live &&
            code != null &&
            code.contains('m3u8');
        if (code != null && !hlsLiveMemorized) {
          final String? remembered =
              XtreamUrlVariants.applyFormat(realUrl, code);
          if (remembered != null && remembered != realUrl) {
            _adoptedAltUrl = remembered;
            realUrl = remembered;
          }
        }
        final String? sourceUa =
            await XtreamUrlFormatStore.instance.sourceUserAgent(src.id!);
        if (!mounted || channel.id != _current.id) return;
        if (sourceUa != null && sourceUa != PlayerSettings.instance.userAgent) {
          await PlayerSettings.instance.setUserAgent(sourceUa);
          userAgent ??= sourceUa;
        }
      }
    }
    final String lower = realUrl.toLowerCase();
    final bool isHls = lower.contains('.m3u8') || lower.contains('.m3u');
    // VOD (film/épisode = FICHIER fini, seekable) : JAMAIS par le relais.
    // Le relais est un tuyau TS live SANS requêtes Range (contrat documenté
    // dans local_stream_relay.dart) : un mp4/mkv qui y passait perdait
    // l'avance/recul propre et la reprise exacte (ExoPlayer seek = Range).
    // En direct, ExoPlayer gère nativement Range + reconnexion progressive.
    if (isHls || _isVod) {
      _relayPlayUrl = null;
      _controller.setUrl(realUrl, userAgent: userAgent);
      return;
    }
    try {
      final String localUrl =
          await LocalStreamRelay.instance.playUrlFor(realUrl);
      if (!mounted || channel.id != _current.id) return;
      _relayPlayUrl = localUrl;
      _controller.setUrl(localUrl, userAgent: userAgent);
    } catch (_) {
      if (!mounted || channel.id != _current.id) return;
      _relayPlayUrl = null;
      _controller.setUrl(realUrl, userAgent: userAgent);
    }
  }

  void _zap(int delta) {
    final int n = widget.channels.length;
    if (n <= 1) return;
    // Si on quittait un VOD (liste de films/épisodes) : position figée AVANT
    // de changer de contenu (no-op en direct → zapping strictement inchangé).
    _savePlaybackPosition();
    // On ne peut enregistrer qu'1 chaîne à la fois (1 connexion) : changer de
    // chaîne clôt et SAUVEGARDE l'enregistrement en cours.
    if (_isRecording) _finalizeRecording(resumeDirect: false);
    // En Dart, `a % n` est TOUJOURS dans [0, n) pour n > 0 → pas de wrap négatif
    // à corriger (l'ancienne ligne `if (_index < 0)` était du code mort).
    _prevIndex = _index; // mémoire « dernière chaîne » (recall)
    _resetStabilitySession(); // zap choisi → session d'adaptation neuve
    setState(() => _index = (_index + delta) % n);
    _scheduleOpen();
  }

  /// ZAPPING RAPIDE (fluide même sur box à faible RAM) : l'HABILLAGE change
  /// TOUT DE SUITE (nom, logo, numéro, écran de marque) mais l'ouverture
  /// RÉSEAU ne part qu'après un court répit sans nouvel appui. Quand le
  /// client enchaîne Ch+ Ch+ Ch+, les chaînes traversées n'ouvrent AUCUNE
  /// connexion et ne réveillent jamais le décodeur — seule celle où il
  /// s'arrête se charge. Résultat : zéro création/destruction de session
  /// par chaîne traversée (c'est ça qui saturait les petites box), et les
  /// comptes « 1 connexion » ne voient plus de tempête d'ouvertures.
  // 150 ms : assez pour absorber une RAFALE d'appuis (Ch+ Ch+ Ch+ n'ouvre
  // aucune connexion sur les chaînes traversées) mais assez court pour qu'un
  // zap DÉLIBÉRÉ, isolé, parte quasi immédiatement — moins de latence perçue.
  static const Duration _kZapSettle = Duration(milliseconds: 150);

  void _scheduleOpen() {
    _zapSettle?.cancel();
    // Quitter la chaîne = couper son son immédiatement (l'image est déjà
    // recouverte par l'écran de marque via _buffering).
    _controller.pause();
    if (mounted) {
      setState(() {
        _buffering = true;
        _fatal = false;
      });
    }
    _showOverlayTemporarily();
    _zapSettle = Timer(_kZapSettle, () {
      if (mounted) _open();
    });
  }

  /// « Dernière chaîne » (recall) : retourne à la chaîne d'AVANT le dernier
  /// changement — et mémorise l'actuelle, pour pouvoir re-basculer (A↔B).
  void _recallLast() {
    final int? p = _prevIndex;
    if (p == null || p == _index || p < 0 || p >= widget.channels.length) {
      return;
    }
    _savePlaybackPosition(); // no-op en direct (cf. _zap)
    if (_isRecording) _finalizeRecording(resumeDirect: false);
    _prevIndex = _index;
    _resetStabilitySession(); // choix utilisateur → session neuve
    setState(() => _index = p);
    _scheduleOpen();
  }

  /// Traduit un blocage en message CLAIR pour le client — écrit noir sur
  /// blanc sur l'écran d'erreur : abonnement expiré, limite de connexions
  /// (un autre écran regarde déjà), compte suspendu. Renvoie [fallback] si
  /// aucune cause « compte » n'est identifiée.
  String _tvBlockMessage(String fallback) {
    final StreamDiagnostics d = StreamDiagnostics.instance;
    switch (d.blockReason) {
      case StreamBlockReason.expired:
        final DateTime? x = d.xtreamExpDate;
        final String date = x == null
            ? '—'
            : '${x.day.toString().padLeft(2, '0')}/'
                '${x.month.toString().padLeft(2, '0')}/${x.year}';
        return context.l10n.playerBlockedExpired(date);
      case StreamBlockReason.maxConnections:
        return context.l10n.playerBlockedMaxConnections(
          '${d.xtreamActiveCons ?? '?'}',
          '${d.xtreamMaxConnections ?? '?'}',
        );
      case StreamBlockReason.banned:
        return context.l10n.playerBlockedBanned;
      case StreamBlockReason.none:
        return fallback;
    }
  }

  /// Applique la décision de [FreezeRecoveryPolicy] : rien à faire, reconnexion,
  /// ou budget épuisé → écran d'erreur borné (P1-6, « Réessayer » manuel).
  void _onFreezeAction(FreezeAction action) {
    switch (action) {
      case FreezeAction.none:
        break;
      case FreezeAction.reopen:
        // H2 — un gel vient souvent d'un upstream SILENCIEUX (ni erreur ni
        // EOF côté relais). Rouvrir sur la MÊME URL locale du relais
        // (_relayPlayUrl) NE relance PAS la connexion amont (elle reste
        // active mais muette) → on force d'abord une vraie reconnexion amont
        // du relais. Live via relais uniquement (VOD/HLS n'y passent pas :
        // _relayPlayUrl est null). No-op si aucune session (retour false).
        if (!_isVod && _relayPlayUrl != null) {
          LocalStreamRelay.instance.forceReconnect(_effectiveUrl);
        }
        // Ré-ouvre la MÊME source : l'URL locale du relais si on enregistre,
        // sinon l'URL directe. = reconnexion au direct sans casser l'enreg.
        // RÉCUPÉRATION INVISIBLE (façon Netflix) : `silent:true` NE remet PAS
        // le lecteur en état « chargement » → la DERNIÈRE IMAGE reste affichée
        // pendant la reconnexion au lieu de faire réapparaître le spinner à
        // chaque hoquet. C'est ce qui supprime le « ça tourne » en boucle sur
        // un lien instable (si aucune image n'a encore été rendue, silent est
        // sans effet : le spinner reste, comportement inchangé au 1er chargement).
        _controller.setUrl(_relayPlayUrl ?? _current.streamUrl, silent: true);
      case FreezeAction.fatal:
        // Jamais joué → source vide/bloquée (diagnostic multi-UA avant
        // d'abandonner, cf. _declareChannelBlocked) ; sinon → vraie coupure
        // réseau, message direct existant.
        if (!_everShownFrame) {
          _declareChannelBlocked();
        } else {
          // ÉCHEC DÉFINITIF après lecture OK (reconnexions épuisées) →
          // gravé dans le journal durable de la Boîte noire (Réglages).
          _recordPlaybackFailure();
          if (mounted) {
            setState(() {
              _fatal = true;
              _buffering = false;
            });
          }
        }
    }
  }

  // ----- ABR maison : tick, bascule, remontée -----

  /// Tick périodique (même Timer que le watchdog anti-gel : zéro réveil de
  /// plus). Alimente le moniteur de stabilité avec les capteurs du relais
  /// et applique sa décision. Ne concerne QUE le direct : un film se met en
  /// pause/tampon, il ne se « dégrade » pas ; et jamais pendant un
  /// enregistrement (le fichier .ts est lié à l'URL en cours).
  void _stabilityTick() {
    if (!mounted || _isVod || _isRecording || _fatal) return;
    if (!_controller.isPlaying && !_controller.isBuffering) {
      return; // pause volontaire (« tu regardes encore ? ») : pas un signal
    }
    final DateTime now = DateTime.now();
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    // Pertes de connexion upstream vues par le relais depuis le dernier
    // tick : chacune est un incident (même si ExoPlayer a été servi par le
    // tampon et n'a RIEN montré à l'écran — c'est le signal précoce).
    final int reconnects = relay.upstreamReconnects(_effectiveUrl);
    if (reconnects > _seenUpstreamReconnects) {
      for (int i = _seenUpstreamReconnects; i < reconnects; i++) {
        _stability.onIncident(now);
      }
    }
    _seenUpstreamReconnects = reconnects;
    switch (_stability.onSample(
      now,
      ingestBytesPerSecond: relay.ingestBytesPerSecond(_effectiveUrl),
    )) {
      case StabilityAction.none:
        break;
      case StabilityAction.downshift:
        _shiftQualityDown();
      case StabilityAction.restore:
        _restoreQuality();
    }
  }

  /// Descend d'UNE marche de qualité : bascule sur la déclinaison inférieure
  /// de la même chaîne (« TF1 FHD » → « TF1 HD »). Silencieusement absent si
  /// le panel ne publie pas de déclinaison (on le mémorise pour ne pas
  /// re-chercher à chaque tick).
  void _shiftQualityDown() {
    final Channel? sibling =
        QualityLadder.lowerQualitySibling(_current, widget.channels);
    final int target = sibling == null
        ? -1
        : widget.channels.indexWhere((Channel c) => c.id == sibling.id);
    if (sibling == null || target < 0) {
      _stability.noteDownshiftUnavailable();
      StreamDiagnostics.instance.recordEvent(
        'abr',
        'Connexion trop faible pour « ${_current.name} » mais aucune '
            'déclinaison de qualité inférieure dans la liste — on tient '
            'avec le tampon et les reconnexions',
        level: 'warn',
      );
      return;
    }
    final DateTime now = DateTime.now();
    _stability.noteShifted(now);
    _qualityOriginIndex ??= _index;
    StreamDiagnostics.instance.recordEvent(
      'abr',
      'Connexion faible → bascule de qualité : « ${_current.name} » → '
          '« ${sibling.name} » (retour auto quand la connexion se stabilise)',
      level: 'warn',
    );
    _switchChannelForQuality(target);
    _flash(context.l10n.tvPlayerQualityDown(sibling.quality.badge));
  }

  /// Remonte à la chaîne d'origine (la connexion est stable depuis assez
  /// longtemps, cf. StreamStabilityMonitor.stableForRestore).
  void _restoreQuality() {
    final DateTime now = DateTime.now();
    final int? origin = _qualityOriginIndex;
    _qualityOriginIndex = null;
    _stability.noteRestored(now);
    if (origin == null ||
        origin == _index ||
        origin < 0 ||
        origin >= widget.channels.length) {
      return;
    }
    final Channel back = widget.channels[origin];
    StreamDiagnostics.instance.recordEvent(
      'abr',
      'Connexion stable → retour à la qualité d\'origine : '
          '« ${_current.name} » → « ${back.name} »',
    );
    _switchChannelForQuality(origin);
    _flash(context.l10n.tvPlayerQualityRestored(back.quality.badge));
  }

  /// Changement de chaîne AUTOMATIQUE (bascule de qualité) : même chemin
  /// que le zap (_open : relais, cascade, historique) mais SANS toucher la
  /// mémoire « dernière chaîne » (_prevIndex) ni la session du moniteur —
  /// c'est le moniteur lui-même qui pilote.
  void _switchChannelForQuality(int target) {
    if (!mounted) return;
    _seenUpstreamReconnects = 0; // nouvelle session relais
    setState(() => _index = target);
    _open();
  }

  /// Zap CHOISI par l'utilisateur : la session d'adaptation de qualité de
  /// l'ancienne chaîne est close (rien ne fuit d'une chaîne à l'autre).
  void _resetStabilitySession() {
    _stability.openChannel(DateTime.now());
    _qualityOriginIndex = null;
    _seenUpstreamReconnects = 0;
  }

  /// Grave un ÉCHEC DÉFINITIF de lecture dans le journal durable consulté
  /// par la Boîte noire des Réglages (playback_failure_log.dart). GREFFÉ sur
  /// les chemins d'erreur existants sans en changer la logique : appelé
  /// uniquement quand le lecteur ABANDONNE (budget de reconnexion épuisé /
  /// chaîne déclarée bloquée), jamais sur une reconnexion silencieuse.
  /// Fire-and-forget et fail-open : le journal ne bloque JAMAIS le lecteur.
  void _recordPlaybackFailure({int uaTried = 0, bool networkBlocked = false}) {
    try {
      final Channel c = _current;
      final String? codeName = _controller.lastErrorCodeName;
      final int? code = _controller.lastErrorCode;
      final String? cause =
          _controller.lastErrorCauseMessage ?? _controller.lastErrorMessage;
      // Verdict humain calculé AU MOMENT DES FAITS (le contexte — image déjà
      // affichée ? blocage réseau conclu par la sonde multi-UA ? — ne sera
      // plus reconstituable plus tard).
      final PlaybackFailureExplanation why = explainPlaybackFailure(
        errorCodeName: codeName,
        errorCode: code,
        cause: cause,
        everShownFrame: _everShownFrame,
        dnsFailed: networkBlocked,
      );
      unawaited(PlaybackFailureLog.instance.record(PlaybackFailureEntry(
        timestamp: DateTime.now(),
        channelName: c.cleanName,
        // VIE PRIVÉE : l'HÔTE seul, jamais l'URL complète (identifiants).
        streamHost: Uri.tryParse(c.streamUrl)?.host ?? '',
        errorCodeName: codeName,
        errorCode: code,
        cause: cause,
        uaTriedCount: uaTried,
        verdict: why.why,
      )));
    } on Object {
      // le journal ne fait JAMAIS planter le lecteur
    }
  }

  /// Chaîne jamais lue avec succès → probablement bloquée par le
  /// fournisseur. AVANT d'abandonner, sonde plusieurs signatures de lecteur
  /// connues (VLC, ExoPlayer/IBO, Smarters…) sur l'URL réelle : beaucoup de
  /// fournisseurs IPTV whitelistent UNE signature précise et servent une
  /// page vide aux autres — c'est souvent ÇA « la chaîne marche sur IBO
  /// mais pas chez nous », pas une vraie panne réseau. Si une AUTRE
  /// signature obtient une vraie réponse média, on l'adopte (persistée via
  /// PlayerSettings, réutilisée par le natif à chaque reconnexion) et on
  /// relance automatiquement, sans même montrer d'erreur au client. Une
  /// seule tentative de diagnostic par chaîne (`_uaFixAttemptedForChannelId`)
  /// pour ne jamais boucler si le vrai problème n'est pas la signature.
  Future<void> _declareChannelBlocked() => _fallback.run();

  /// « Réessayer » manuel depuis l'écran d'erreur : on repart d'un budget neuf.
  void _manualRetry() {
    _freeze.openChannel(
        DateTime.now()); // horloge fraîche : pas de watchdog immédiat
    _rebufferTimes.clear(); // budget rebuffer neuf pour la nouvelle tentative
    _armStartupWatchdog(); // si la reprise ne démarre pas non plus → coupure rapide
    setState(() {
      _fatal = false;
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
        _flash(context.l10n.tvRecFailed);
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
        _flash(context.l10n.tvPlayerRecStarted);
      }
    } catch (e) {
      if (mounted) _flash(context.l10n.tvPlayerRecError);
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
          ? context.l10n.tvPlayerRecSaved(_humanSize(bytes))
          : context.l10n.tvPlayerRecEmpty);
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

  String _humanSize(int bytes) {
    if (bytes < 1024) return context.l10n.tvPlayerSizeB('$bytes');
    if (bytes < 1024 * 1024) {
      return context.l10n.tvPlayerSizeKb((bytes / 1024).toStringAsFixed(0));
    }
    if (bytes < 1024 * 1024 * 1024) {
      return context.l10n
          .tvPlayerSizeMb((bytes / (1024 * 1024)).toStringAsFixed(1));
    }
    return context.l10n
        .tvPlayerSizeGb((bytes / (1024 * 1024 * 1024)).toStringAsFixed(2));
  }

  void _showOverlayTemporarily() {
    setState(() => _overlay = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted)
        setState(() {
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
    // FILM (Netflix) : OK = lecture/pause… SAUF quand la pastille « Épisode
    // suivant » est à l'écran (30 dernières secondes, barre masquée) : OK
    // l'active — exactement le comportement Netflix pendant un générique.
    // Pour mettre en pause à ce moment-là : Haut/Bas ouvre la barre (la
    // pastille se cache), puis OK = pause.
    if (_isVod) {
      if (_endPillVisible && !_overlay) {
        _autoplay.onUserInteraction();
        _playUpNext(auto: false);
        return;
      }
      _togglePlayPause();
      return;
    }
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
      _btnFocus =
          (_btnFocus < 0 ? 1 : _btnFocus + delta).clamp(0, _btnCount - 1);
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
      case 4:
        _openTracksSheet();
        break;
    }
  }

  // ----- Feuille « Pistes & format d'image » ------------------------------

  /// Lignes actionnables de la feuille, reconstruites à CHAQUE build :
  /// les listes de pistes sont vidées puis re-remplies par le natif à
  /// chaque zap (onTracksChanged) — la feuille suit toute seule via le
  /// listener du controller déjà en place.
  List<_TrackSheetEntry> _sheetEntries() {
    final List<_TrackSheetEntry> rows = <_TrackSheetEntry>[];
    final List<TrackInfo> audio = _controller.audioTracks;
    final List<TrackInfo> text = _controller.textTracks;
    for (int i = 0; i < audio.length; i++) {
      rows.add(_TrackSheetEntry(kind: _SheetKind.audio, index: i));
    }
    // Sous-titres : « Désactivés » d'abord (l'état sans piste texte
    // sélectionnée est le plus courant en IPTV), puis chaque piste.
    rows.add(const _TrackSheetEntry(kind: _SheetKind.textOff, index: -1));
    for (int i = 0; i < text.length; i++) {
      rows.add(_TrackSheetEntry(kind: _SheetKind.text, index: i));
    }
    for (final AspectRatioMode m in AspectRatioMode.values) {
      rows.add(_TrackSheetEntry(
          kind: _SheetKind.aspect, index: AspectRatioMode.values.indexOf(m)));
    }
    return rows;
  }

  /// Construit la surface vidéo selon [_aspect] :
  ///   - Contenir (Auto) → ratio RÉEL du flux (letterbox si besoin),
  ///     repli 16:9 tant que le natif n'a pas remonté videoSize ;
  ///   - 16:9 / 4:3 / 2.39:1 → ratio forcé ;
  ///   - Étirer → plein cadre sans respect du ratio ;
  ///   - Remplir → zoom qui GARDE le ratio et rogne les bords (utile
  ///     pour les flux 4:3 letterboxés sur TV 16:9).
  Widget _buildVideoSurface() {
    final Widget view = NativeVideoView(controller: _controller);
    final double streamAr = _controller.videoAspectRatio ?? (16 / 9);
    switch (_aspect) {
      case AspectRatioMode.fit:
        return Center(child: AspectRatio(aspectRatio: streamAr, child: view));
      case AspectRatioMode.ratio169:
        return Center(child: AspectRatio(aspectRatio: 16 / 9, child: view));
      case AspectRatioMode.ratio43:
        return Center(child: AspectRatio(aspectRatio: 4 / 3, child: view));
      case AspectRatioMode.ratio219:
        return Center(child: AspectRatio(aspectRatio: 2.39, child: view));
      case AspectRatioMode.stretch:
        return SizedBox.expand(child: view);
      case AspectRatioMode.fill:
        // Couvrir : la vidéo garde son ratio, déborde et se fait rogner.
        // OverflowBox (et non FittedBox) : la PlatformView reçoit une
        // VRAIE taille de layout — pas de mise à l'échelle par
        // transformation, plus sûr avec une SurfaceView.
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double w = c.maxWidth;
            final double h = c.maxHeight;
            final double vw = (w / h > streamAr) ? w : h * streamAr;
            final double vh = (w / h > streamAr) ? w / streamAr : h;
            return ClipRect(
              child: OverflowBox(
                minWidth: 0,
                minHeight: 0,
                maxWidth: vw,
                maxHeight: vh,
                child: SizedBox(width: vw, height: vh, child: view),
              ),
            );
          },
        );
    }
  }

  void _openTracksSheet() {
    setState(() {
      _tracksVisible = true;
      _tracksFocus = 0;
      _overlay = false; // la feuille remplace la barre à l'écran
    });
    _armTracksAutoClose();
  }

  /// FERMETURE AUTO (demande terrain 2026-07-17) : après un changement de
  /// langue/sous-titres — ou simple inactivité — la feuille disparaît
  /// toute seule au bout de 10 s. Chaque interaction (flèche, OK, tap)
  /// RELANCE le compte : on ne ferme jamais au nez de quelqu'un qui
  /// navigue encore dans la liste.
  void _armTracksAutoClose() {
    _tracksAutoClose?.cancel();
    _tracksAutoClose = Timer(const Duration(seconds: 10), () {
      if (mounted && _tracksVisible) _closeTracksSheet();
    });
  }

  void _closeTracksSheet() {
    _tracksAutoClose?.cancel();
    setState(() => _tracksVisible = false);
    _showOverlayTemporarily();
  }

  /// Applique la ligne surlignée. La sélection de piste passe par le
  /// MethodChannel du plugin (TrackSelectionOverride ExoPlayer : AUCUN
  /// rebuild du player, pas d'écran noir). Le ratio est 100 % Flutter
  /// (dimensionnement de la PlatformView) et persiste via PlayerSettings.
  void _activateSheetEntry(_TrackSheetEntry e) {
    // Sélection (D-pad OU tap tactile) → la fenêtre de fermeture auto
    // repart : la feuille disparaîtra 10 s après le DERNIER choix.
    _armTracksAutoClose();
    switch (e.kind) {
      case _SheetKind.audio:
        _controller.setAudioTrack(e.index);
        break;
      case _SheetKind.textOff:
        _controller.setSubtitleTrack(-1);
        break;
      case _SheetKind.text:
        _controller.setSubtitleTrack(e.index);
        break;
      case _SheetKind.aspect:
        final AspectRatioMode m = AspectRatioMode.values[e.index];
        setState(() => _aspect = m);
        unawaited(PlayerSettings.instance.setAspectMode(m));
        break;
    }
    // On laisse la feuille OUVERTE : l'utilisateur peut comparer les
    // pistes / formats sans rouvrir le panneau (convention TiviMate).
    setState(() {});
  }

  // MULTI-VUE (2 chaînes) : réservée aux box assez puissantes (2 décodeurs).
  // Sur une petite box, on n'essaie PAS (message) → on protège la stabilité.
  void _openMultiView() {
    if (!multiViewSupported()) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(context.l10n.tvMultiViewUnavailable),
          duration: const Duration(seconds: 3),
        ),
      );
      _showOverlayTemporarily();
      return;
    }
    // FUITE DE CONNEXIONS (terrain 2026-07-30) : ce lecteur reste MONTÉ sous
    // la route de la multivue et continuait de décoder son flux — pendant que
    // la multivue en ouvre 2 autres → 3 flux amont simultanés, dépassement de
    // la limite « max connexions » du fournisseur. On met le lecteur du dessous
    // en PAUSE avant de pousser (stoppe le décodage) et on REPREND au retour
    // (le lecteur est toujours là, un simple play() relance sans re-résoudre).
    // NB : `pause()` stoppe le décodage ; la connexion amont, elle, est refermée
    // par la détection de silence du relais 1-connexion. Reprise au pop.
    _controller.pause();
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => TvMultiViewScreen(
          channels: widget.channels,
          startIndex: _index,
        ),
      ),
    )
        .then((_) {
      if (mounted) _controller.play();
    });
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
      _controller.pause();
      // Hue « salle de cinéma » : pause film → la lumière remonte un peu
      // (no-op silencieux si pas de pont / option OFF / scène inactive).
      if (_isVod) unawaited(HueService.instance.cinemaPause());
    } else {
      _controller.play();
      if (_isVod) unawaited(HueService.instance.cinemaResume());
    }
    _showOverlayTemporarily();
    setState(() {});
  }

  /// Lance l'ambiance Hue TEINTÉE par l'affiche du film. Best-effort de
  /// bout en bout : sans pont/option, ou si l'image est indisponible ou
  /// terne, on lance la scène en rouge braise par défaut. Ne touche JAMAIS
  /// la vidéo (couleur calculée sur l'affiche téléchargée en petit).
  Future<void> _startHueImmersive(String? posterUrl) async {
    // Sortie rapide si Hue n'a rien à faire (option OFF / pas de pont) :
    // on évite un décodage d'image inutile.
    if (!HueService.instance.enabled || !HueService.instance.isPaired) return;
    ({int hue, int sat})? tint;
    try {
      if (posterUrl != null &&
          posterUrl.isNotEmpty &&
          !posterUrl.startsWith('file:')) {
        final HttpClient client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4);
        try {
          final HttpClientRequest req =
              await client.getUrl(Uri.parse(posterUrl));
          final HttpClientResponse resp =
              await req.close().timeout(const Duration(seconds: 5));
          final List<int> bytes = <int>[];
          await for (final List<int> chunk in resp) {
            bytes.addAll(chunk);
            if (bytes.length > 3 * 1024 * 1024) break; // garde-fou 3 Mo
          }
          // Décodage BORNÉ à 64 px de large : rapide, suffisant pour une
          // couleur moyenne, négligeable en mémoire sur box modeste.
          final ui.Codec codec = await ui.instantiateImageCodec(
              Uint8List.fromList(bytes),
              targetWidth: 64);
          final ui.FrameInfo frame = await codec.getNextFrame();
          final ByteData? data =
              await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
          frame.image.dispose();
          if (data != null) {
            tint = HueService.dominantFromRgba(data.buffer.asUint8List(),
                stride: 1);
          }
        } finally {
          client.close(force: true);
        }
      }
    } catch (_) {
      tint = null; // repli braise
    }
    if (!mounted || !_isVod) return;
    await HueService.instance.cinemaStart(hue: tint?.hue, sat: tint?.sat);
  }

  // ---- MODE FILM (VOD / catch-up) — commandes façon Netflix ----
  // Un FILM n'est pas un direct : on l'avance/recule (±10 s), on affiche une
  // barre de progression, et OK = lecture/pause. Le DIRECT n'utilise RIEN de
  // tout ça (tout est gardé par `_isVod`) → comportement live 100 % inchangé.
  bool get _isVod => !_current.isLive;

  /// Avance/recule le film (Netflix : ±10 s ; appuis RAPPROCHÉS dans le même
  /// sens = ±30 s pour traverser un générique sans marteler). Affiche la
  /// bulle de TEMPS CIBLE au-dessus de la barre. Sans effet en direct.
  void _seekRelative(Duration delta) {
    if (!_isVod) return;
    final DateTime now = DateTime.now();
    final int dir = delta.isNegative ? -1 : 1;
    // Double-appui : même direction, moins de 500 ms après le précédent →
    // le pas passe de 10 s à 30 s (chaque appui suivant reste à 30 s tant
    // que la rafale continue).
    final bool rapid = _lastSeekDir == dir &&
        _lastSeekTapAt != null &&
        now.difference(_lastSeekTapAt!) < const Duration(milliseconds: 500);
    _lastSeekTapAt = now;
    _lastSeekDir = dir;
    final Duration step = rapid ? Duration(seconds: 30 * dir) : delta;
    _controller.seekBy(step);
    // Bulle de preview : le TEMPS CIBLE (position déjà mise à jour par le
    // controller), visible 1,2 s après le dernier appui.
    _seekPreview = _controller.position;
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _seekPreview = null);
    });
    _showOverlayTemporarily();
    setState(() {}); // la barre reflète tout de suite la nouvelle position
  }

  /// TAP-SUR-LA-BARRE (YouTube) : saute à la fraction touchée (0..1).
  /// Même sortie que _seekBy : bulle de preview 1,2 s + barre rafraîchie.
  void _seekToFraction(double f) {
    final Duration total = _controller.duration;
    if (!_isVod || total <= Duration.zero) return;
    final Duration target =
        Duration(milliseconds: (total.inMilliseconds * f).round());
    _controller.seekTo(target);
    _seekPreview = target;
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _seekPreview = null);
    });
    _showOverlayTemporarily();
    setState(() {});
  }

  // ---- REPRISE DE LECTURE (« Reprendre à 42:15 », façon Netflix) ----
  // Tout est gardé par `_isVod` : le DIRECT (zapping) n'exécute RIEN d'ici.

  /// Va chercher la position sauvegardée du contenu courant (lecture prefs,
  /// quelques millisecondes — bien avant que le flux soit prêt). Appelé à
  /// chaque _open() d'un VOD. `ensureLoaded()` rend la reprise indépendante
  /// de l'ordre de démarrage (le vrai `load()` est branché dans main_tv).
  Future<void> _loadResumePoint() async {
    final Channel opened = _current;
    await PlaybackPositionRepository.instance.ensureLoaded();
    // L'utilisateur a quitté / changé de contenu pendant la lecture prefs →
    // cette reprise ne concerne plus l'écran affiché.
    if (!mounted || !identical(opened, _current) || _resumeApplied) return;
    _pendingResume = PlaybackPositionRepository.instance.positionFor(opened.id);
    _maybeApplyResume();
  }

  /// Applique la reprise UNE seule fois, quand le flux est PRÊT : la durée
  /// n'est émise par le natif qu'une fois le média préparé et SEEKABLE — un
  /// seekTo lancé plus tôt serait ignoré par ExoPlayer. Comportement Netflix :
  /// reprise DIRECTE, pas de dialogue ; un petit toast « Reprise à 42:15 »
  /// sert de repère (et rassure : non, le film n'a pas sauté tout seul).
  void _maybeApplyResume() {
    if (!_isVod || _resumeApplied) return;
    final Duration? target = _pendingResume;
    final Duration total = _controller.duration;
    if (target == null || total <= Duration.zero) return;
    _resumeApplied = true; // une seule fois par ouverture (jamais re-seek)
    _pendingResume = null;
    // Re-validation contre la durée RÉELLE (le fichier a pu changer côté
    // fournisseur) : position quasi à la fin → on repart du début, comme si
    // le film était terminé.
    if (target.inMilliseconds >
        total.inMilliseconds * PlaybackPositionRepository.finishedRatio) {
      return;
    }
    _controller.seekTo(target);
    if (mounted) _flash(context.l10n.tvResumedAt(_fmtClock(target)));
  }

  /// Sauvegarde la position VOD courante (périodique via le tick du watchdog,
  /// à la sortie via dispose, et avant un changement de contenu). NO-OP total
  /// en DIRECT et tant que la durée n'est pas connue. Les règles métier
  /// (< 60 s → rien ; > 95 % → terminé) vivent dans le repository — ici on
  /// se contente de pousser l'état brut.
  void _savePlaybackPosition() {
    if (!_isVod) return;
    final Duration total = _controller.duration;
    if (total <= Duration.zero) return;
    final Channel c = _current;
    final bool isEpisode = c.id.startsWith('ep-');
    // Pour un ÉPISODE, `name` vaut « S1 E3 · Titre » et `category` porte le
    // nom de la série : on préfixe pour que la rangée « Continuer à
    // regarder » reste lisible hors de la fiche série.
    final String displayName = (isEpisode && c.category.trim().isNotEmpty)
        ? '${c.category.trim()} — ${c.name}'
        : c.name;
    unawaited(PlaybackPositionRepository.instance.record(
      key: c.id,
      position: _controller.position,
      duration: total,
      name: displayName,
      streamUrl: c.streamUrl,
      posterUrl: c.logoUrl,
      isEpisode: isEpisode,
    ));
  }

  /// « 42:15 » ou « 1:02:03 » — pour le toast de reprise.
  static String _fmtClock(Duration d) {
    final int s = d.inSeconds < 0 ? 0 : d.inSeconds;
    final int h = s ~/ 3600;
    final int m = (s % 3600) ~/ 60;
    final int sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }

  // ---- « À SUIVRE » (autoplay épisode suivant, façon Netflix) ----
  // La fiche série passe déjà TOUTE la saison au lecteur (channels +
  // startIndex, cf. tv_series_screen._playEpisode) : « le suivant » est
  // simplement l'élément d'après dans la liste — SANS boucler (fin de
  // saison = pas de wrap vers l'épisode 1, écran de fin classique).

  /// Épisode suivant dans la liste du lecteur (null = dernier élément).
  Channel? get _nextUpChannel =>
      _index + 1 < widget.channels.length ? widget.channels[_index + 1] : null;

  /// Fin réelle d'un VOD : si c'est un ÉPISODE avec un suivant, l'overlay
  /// « À suivre » possède cette fin (carte + compte à rebours, ou attente
  /// d'un OK si le garde-fou anti-binge est atteint, ou silence si déjà
  /// annulé). Renvoie false pour film / fin de saison → l'appelant garde
  /// le comportement existant, strictement inchangé.
  bool _handleVodEnded() {
    // Une VRAIE fin arrive forcément après des images affichées. Un `ended`
    // parasite juste après une ouverture (source vide, événement en retard)
    // ne doit PAS déclencher l'autoplay → il retombe sur le chemin existant
    // (reconnexion anti-gel), comme avant.
    if (!_everShownFrame) return false;
    final Channel? next = _nextUpChannel;
    if (!_autoplay.canPropose(
        isLive: _current.isLive, currentId: _current.id, nextId: next?.id)) {
      return false;
    }
    // Le natif re-notifie `isEnded` tant qu'on reste sur l'écran de fin :
    // carte déjà affichée → rien à redécider.
    if (_upNextVisible) return true;
    final UpNextDecision decision = _autoplay.onEnded(
        isLive: _current.isLive, currentId: _current.id, nextId: next?.id);
    // Annulé pour CE contenu → écran de fin stable (la carte ne re-pop pas).
    if (decision == UpNextDecision.none) return true;
    _upNextTimer?.cancel();
    setState(() {
      _upNextVisible = true;
      _upNextBtn = 0; // « Lire maintenant » surligné d'office (autofocus)
      _upNextAuto = decision == UpNextDecision.autoCountdown;
      _upNextSeconds = _autoplay.countdownSeconds;
    });
    if (_upNextAuto) {
      // Tick d'1 s : décrémente le compte à rebours visible ; à zéro on
      // enchaîne tout seul. Pas de garde `_upNextVisible` ici : toute
      // sortie de la carte (Annuler, zap, dispose) CANCEL ce timer.
      _upNextTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _upNextSeconds--);
        if (_upNextSeconds <= 0) {
          t.cancel();
          _playUpNext(auto: true);
        }
      });
    }
    return true;
  }

  /// Enchaîne sur l'épisode suivant — par le compte à rebours ([auto]) ou
  /// par « Lire maintenant ». Réutilise le chemin de zap EXISTANT (_zap) :
  /// l'épisode suivant hérite donc de TOUT (reprise au timecode, sauvegarde
  /// de position, watchdog anti-gel, diagnostic multi-UA).
  void _playUpNext({required bool auto}) {
    _upNextTimer?.cancel();
    if (!mounted) return;
    // Seul l'enchaînement AUTOMATIQUE consomme le budget anti-binge ; un
    // appui « Lire maintenant » est déjà passé par onUserInteraction().
    if (auto) _autoplay.onAutoAdvance();
    setState(() => _upNextVisible = false);
    // 1-CONNEXION (terrain 2026-07-16 : « S01e04 — Chaîne vide ou
    // bloquée ») : l'épisode qui vient de finir tient ENCORE le slot
    // côté panel pendant ~1 s après la fermeture de sa connexion.
    // Enchaîner immédiatement (l'ancien chemin ouvrait N+1 en ~150 ms)
    // = 2e connexion → flux vide/403 → écran « bloqué ». On coupe
    // l'amont MAINTENANT, on laisse le panel libérer, puis on ouvre
    // l'épisode suivant. 1,2 s en fin d'épisode : imperceptible.
    _controller.pause();
    LocalStreamRelay.instance.closeOtherPlaybacks('');
    _upNextTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _zap(1);
    });
  }

  /// « Annuler » (ou Retour) : le compte à rebours s'arrête, on reste sur
  /// l'écran de fin — comportement d'avant l'autoplay.
  void _cancelUpNext() {
    _upNextTimer?.cancel();
    _autoplay.onCancel(_current.id);
    if (mounted) setState(() => _upNextVisible = false);
  }

  // Ajoute / retire la chaîne courante des favoris (bouton / touche F).
  void _toggleFavorite() {
    final bool wasFav = _isFavorite;
    FavoritesRepository.instance.toggle(_current.id);
    _flash(wasFav ? context.l10n.tvFavRemoved : context.l10n.tvFavAdded);
    _showOverlayTemporarily();
  }

  // ----- Saisie d'un numéro de chaîne (0-9) → zap après ~1,5 s -----
  void _onDigit(int d) {
    // Pépite câble US : « 0 » SEUL = dernière chaîne (recall). Aucun conflit :
    // la numérotation des chaînes démarre à 1, un numéro ne commence pas par 0.
    if (d == 0 && _numBuffer.isEmpty) {
      _recallLast();
      return;
    }
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
    _savePlaybackPosition(); // no-op en direct (cf. _zap)
    _prevIndex = _index; // mémoire « dernière chaîne » (recall)
    _resetStabilitySession(); // choix utilisateur → session neuve
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

    // Toute touche = activité → réarme « Tu regardes encore ? » ET remet à
    // zéro le garde-fou anti-binge de l'autoplay (quelqu'un tient la
    // télécommande → les enchaînements automatiques restent fluides).
    // Si la question est affichée, N'IMPORTE quelle touche reprend la
    // lecture (la touche est consommée : elle ne zappe pas par accident).
    _lastUserAction = DateTime.now();
    _autoplay.onUserInteraction();
    if (_askStillWatching) {
      setState(() => _askStillWatching = false);
      _controller.play();
      return KeyEventResult.handled;
    }

    // FEUILLE « PISTES & FORMAT » affichée : elle capte tout le D-pad
    // (même modèle que la carte « À suivre »). Haut/Bas déplacent le
    // surlignage, OK applique (piste audio / sous-titres / ratio),
    // Retour ferme. Tout le reste est consommé : pas de zap accidentel
    // sous le panneau.
    if (_tracksVisible) {
      // Chaque touche dans la feuille relance la fenêtre de fermeture
      // auto (10 s) — on ne ferme pas au nez de quelqu'un qui navigue.
      _armTracksAutoClose();
      final List<_TrackSheetEntry> rows = _sheetEntries();
      if (_isOk(k)) {
        if (_tracksFocus >= 0 && _tracksFocus < rows.length) {
          _activateSheetEntry(rows[_tracksFocus]);
        }
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.goBack ||
          k == LogicalKeyboardKey.escape ||
          k == LogicalKeyboardKey.browserBack ||
          k == LogicalKeyboardKey.exit) {
        _closeTracksSheet();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        setState(
            () => _tracksFocus = (_tracksFocus - 1).clamp(0, rows.length - 1));
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        setState(
            () => _tracksFocus = (_tracksFocus + 1).clamp(0, rows.length - 1));
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    // CARTE « À SUIVRE » affichée : elle capte tout le D-pad. Gauche/Droite
    // déplacent le surlignage entre « Lire maintenant » et « Annuler »,
    // OK active, Retour = Annuler (on RESTE sur l'écran de fin, on ne
    // quitte pas le lecteur par surprise). Les autres touches sont
    // consommées : pas de seek/zap accidentel sous la carte.
    if (_upNextVisible) {
      if (_isOk(k)) {
        if (_upNextBtn == 0) {
          _playUpNext(auto: false);
        } else {
          _cancelUpNext();
        }
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.goBack ||
          k == LogicalKeyboardKey.escape ||
          k == LogicalKeyboardKey.browserBack ||
          k == LogicalKeyboardKey.exit) {
        _cancelUpNext();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft) {
        setState(() => _upNextBtn = 0);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        setState(() => _upNextBtn = 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

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
    if (di >= 0) {
      _onDigit(di);
      return KeyEventResult.handled;
    }

    // FILM : flèche BAS = feuille « Pistes » (audio, sous-titres, format) —
    // le geste des plateformes (les options vivent sous le scrubber). Les
    // AUTRES variantes « suivant » (Ch-, PageDown…) gardent leur rôle
    // d'affichage de barre : on ne détourne que la flèche directionnelle.
    if (_isVod && k == LogicalKeyboardKey.arrowDown) {
      _openTracksSheet();
      return KeyEventResult.handled;
    }

    // Haut/Bas (et Ch+/Ch-) = zap direct — UNIQUEMENT en direct. Sur un FILM,
    // on ne zappe pas (Netflix) : on montre juste la barre.
    if (_isPrev(k)) {
      if (_isVod) {
        _showOverlayTemporarily();
      } else {
        _zap(-1);
      }
      return KeyEventResult.handled;
    }
    if (_isNext(k)) {
      if (_isVod) {
        _showOverlayTemporarily();
      } else {
        _zap(1);
      }
      return KeyEventResult.handled;
    }

    // Gauche/Droite :
    //   • FILM  → avance/recul de 10 s (façon Netflix) ;
    //   • DIRECT → déplace le surlignage entre les boutons de la barre.
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (_isVod) {
        _seekRelative(const Duration(seconds: -10));
      } else {
        _navBtn(-1);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (_isVod) {
        _seekRelative(const Duration(seconds: 10));
      } else {
        _navBtn(1);
      }
      return KeyEventResult.handled;
    }
    // Touches média AVANCE/RETOUR (télécommandes qui en ont) → seek sur un film.
    if (k == LogicalKeyboardKey.mediaRewind) {
      if (_isVod) _seekRelative(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      if (_isVod) _seekRelative(const Duration(seconds: 10));
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
    // Material TRANSPARENT : le lecteur est poussé depuis des dizaines
    // d'endroits (zap, fiches, téléchargements, reprise…) et n'a pas de
    // Scaffold — sans Material ancêtre, tout l'overlay partait en secours
    // Flutter (textes jaunes soulignés, monospace). Bug terrain 2026-07-17.
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
            onTap: () {
              _lastUserAction = DateTime.now();
              _autoplay.onUserInteraction(); // tactile = présence aussi
              if (_askStillWatching) {
                setState(() => _askStillWatching = false);
                _controller.play();
                return;
              }
              _toggleOverlay();
            },
            onVerticalDragEnd: (DragEndDetails d) {
              _lastUserAction = DateTime.now();
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
                  // Vidéo SurfaceView native, dimensionnée selon le FORMAT
                  // D'IMAGE choisi (feuille « Pistes & format »). La Surface
                  // ExoPlayer remplit la PlatformView : piloter sa taille
                  // côté Flutter suffit — zéro rebuild du player, pas
                  // d'écran noir au changement de mode.
                  _buildVideoSurface(),
                  // VOILE DE DISSIMULATION pendant l'ouverture / le zap / une
                  // reconnexion (spec « zéro frustration ») : JAMAIS de
                  // spinner. La dernière image reste figée sous un voile noir
                  // quasi opaque et le logo de la chaîne VISÉE « respire »
                  // lentement — l'habillage change tout de suite, le réseau
                  // suit (cf. _kZapSettle).
                  if (_buffering && !_fatal) _BufferVeil(channel: _current),
                  // « TU REGARDES ENCORE ? » : lecture en pause après une longue
                  // inactivité — n'importe quelle touche reprend. Économise la
                  // bande passante quand la TV reste allumée sans personne.
                  if (_askStillWatching)
                    ColoredBox(
                      color: const Color(0xE6000000), // scrim noir 90 %
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.nightlight_round,
                                color: TvTokens.gold, size: 52),
                            const SizedBox(height: 18),
                            Text(context.l10n.tvPlayerStillWatching,
                                style: TextStyle(
                                    fontSize: TvDimens.title + 6,
                                    fontWeight: FontWeight.w800,
                                    color: TvTokens.text)),
                            const SizedBox(height: 10),
                            Text(context.l10n.tvPlayerPressAnyKey,
                                style: TextStyle(
                                    fontSize: TvDimens.body,
                                    color: TvTokens.muted)),
                          ],
                        ),
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
                            Text(
                                _weakConnectionFatal
                                    ? context.l10n.playerWeakConnection
                                    : _tvBlockMessage(_everShownFrame
                                        ? context.l10n.tvChannelUnavailable
                                        : context.l10n.tvChannelBlockedBySource),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: TvDimens.body,
                                    color: TvTokens.mutedDim)),
                            // Indice réseau/VPN : uniquement quand le diagnostic
                            // multi-UA a conclu à un blocage réseau (DNS/timeout)
                            // plutôt qu'à un simple souci de signature de lecteur.
                            if (_fatalNetworkHint) ...<Widget>[
                              const SizedBox(height: 6),
                              Text(context.l10n.tvChannelNetworkHint,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: TvDimens.body * 0.85,
                                      color: TvTokens.mutedDim)),
                            ],
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
                              child: Text(context.l10n.tvRetryQuitHint,
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
                  // chaîne + tous les contrôles (dont REC et en bas).
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
                            onTracks: _openTracksSheet,
                            // ---- Mode FILM (Netflix) ----
                            isVod: _isVod,
                            position: _controller.position,
                            duration: _controller.duration,
                            buffered: _controller.buffered,
                            isPlaying: _controller.isPlaying,
                            onSeekBack: () =>
                                _seekRelative(const Duration(seconds: -10)),
                            onSeekFwd: () =>
                                _seekRelative(const Duration(seconds: 10)),
                            onPlayPause: _togglePlayPause,
                            seekPreview: _seekPreview,
                            onSeekToFraction: _seekToFraction,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
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
                            Text(context.l10n.playerRec,
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
                  // Carte « À SUIVRE » (bas-droite, façon Netflix) : titre du
                  // prochain épisode + compte à rebours 10 s + Lire maintenant /
                  // Annuler. Uniquement à la fin d'un ÉPISODE avec un suivant
                  // (cf. _handleVodEnded) — jamais en live ni pour un film.
                  // Feuille « Pistes & format d'image » (panneau latéral droit,
                  // focus émulé — cf. _onKey qui lui détourne tout le D-pad).
                  if (_tracksVisible)
                    Positioned(
                      top: 0,
                      right: 0,
                      bottom: 0,
                      child: _TracksSheet(
                        audio: _controller.audioTracks,
                        text: _controller.textTracks,
                        entries: _sheetEntries(),
                        focusedIndex: _tracksFocus,
                        aspect: _aspect,
                        onActivate: _activateSheetEntry,
                        onClose: _closeTracksSheet,
                      ),
                    ),
                  // Pastille « Épisode suivant » (30 dernières secondes d'un
                  // épisode, barre masquée) : OK = enchaîner tout de suite,
                  // ne rien faire = regarder le générique. Se cache quand la
                  // barre s'ouvre (OK redevient lecture/pause, sans ambiguïté).
                  if (_endPillVisible && !_overlay && _nextUpChannel != null)
                    Positioned(
                      right: TvDimens.safeH,
                      bottom: TvDimens.safeV + 24,
                      child: _NextEpisodePill(
                        onTap: () {
                          _autoplay.onUserInteraction();
                          _playUpNext(auto: false);
                        },
                      ),
                    ),
                  if (_upNextVisible && _nextUpChannel != null)
                    Positioned(
                      right: TvDimens.safeH,
                      bottom: TvDimens.safeV + 24,
                      child: _UpNextCard(
                        title: _nextUpChannel!.cleanName,
                        seconds: _upNextAuto ? _upNextSeconds : null,
                        totalSeconds: _autoplay.countdownSeconds,
                        focusedIndex: _upNextBtn,
                        // Tactile : un tap direct sur un bouton de la carte.
                        onPlay: () {
                          _autoplay.onUserInteraction();
                          _playUpNext(auto: false);
                        },
                        onCancel: _cancelUpNext,
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
}

/// Panneau de lecture moderne (façon YouTube / Netflix) : dégradé sombre en
/// bas, infos chaîne (logo + nom + DIRECT + n° de chaîne) puis une rangée de
/// commandes « verre » animées. À droite (« en bas ») : REC et favori.
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
    required this.onTracks,
    required this.isVod,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.isPlaying,
    required this.onSeekBack,
    required this.onSeekFwd,
    required this.onPlayPause,
    required this.onSeekToFraction,
    this.seekPreview,
  });

  final Channel channel;
  final int index;
  final int total;
  final bool isRecording;
  final bool isFavorite;

  /// Temps CIBLE pendant un seek (bulle au-dessus de la barre) — null = rien.
  final Duration? seekPreview;

  /// Index du bouton surligné au D-pad (-1 = aucun). 0=Guide 1=REC 2=Favori.
  final int focusedIndex;
  final VoidCallback onGuide;
  final VoidCallback onRecord;
  final VoidCallback onFavorite;
  final VoidCallback onMulti;
  final VoidCallback onTracks;

  // ---- Mode FILM (Netflix) ----
  final bool isVod;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isPlaying;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekFwd;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeekToFraction;

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
          // FILM → scrubber Netflix (barre + temps + ⏪10 / ▶⏸ / ⏩10).
          // DIRECT → commandes live habituelles (Guide, REC, Favori, Multi).
          if (isVod)
            _VodControls(
              position: position,
              duration: duration,
              buffered: buffered,
              isPlaying: isPlaying,
              onSeekBack: onSeekBack,
              onSeekFwd: onSeekFwd,
              onPlayPause: onPlayPause,
              onSeekToFraction: onSeekToFraction,
              onTracks: onTracks,
              seekPreview: seekPreview,
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CtrlButton(
                  icon: Icons.calendar_month_rounded,
                  label: context.l10n.tvNavGuide,
                  onTap: onGuide,
                  focused: focusedIndex == 0,
                ),
                const SizedBox(width: 34),
                _CtrlButton(
                  icon: isRecording
                      ? Icons.stop_rounded
                      : Icons.fiber_manual_record_rounded,
                  label: isRecording
                      ? context.l10n.tvPlayerStop
                      : context.l10n.playerRec,
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
                  label: context.l10n.tvPlayerFavorite,
                  onTap: onFavorite,
                  accent: TvTokens.gold,
                  active: isFavorite,
                  focused: focusedIndex == 2,
                ),
                const SizedBox(width: 34),
                _CtrlButton(
                  icon: Icons.grid_view_rounded,
                  label: context.l10n.tvPlayerMulti,
                  onTap: onMulti,
                  focused: focusedIndex == 3,
                ),
                const SizedBox(width: 34),
                // « Pistes » : audio, sous-titres et format d'image —
                // LE réglage qui manquait face aux lecteurs concurrents.
                _CtrlButton(
                  icon: Icons.tune_rounded,
                  label: context.l10n.tracksTitle,
                  onTap: onTracks,
                  focused: focusedIndex == 4,
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

/// Pastille « Épisode suivant » des 30 dernières secondes d'un épisode
/// (« regarder le générique ou passer », façon Netflix). OK = enchaîner
/// (géré par l'écran) ; le tap direct sert au tactile. Toujours dessinée
/// SURLIGNÉE : c'est LE bouton actif tant que la barre est masquée.
class _NextEpisodePill extends StatelessWidget {
  const _NextEpisodePill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: TvTokens.ember,
          borderRadius: BorderRadius.circular(12),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.skip_next_rounded,
                size: 24, color: TvTokens.onEmber),
            const SizedBox(width: 8),
            Text(
              context.l10n.tvNextEpisode,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.onEmber),
            ),
          ],
        ),
      ),
    );
  }
}

/// Commandes de LECTURE d'un FILM (façon Netflix) : grande barre de
/// progression dorée + temps écoulé/total, et une rangée ⏪10 · ▶/⏸ · 10⏩.
/// À la télécommande : Gauche/Droite = ±10 s, OK = lecture/pause (géré par
/// l'écran) ; ces boutons servent aussi au doigt (TV/tablette tactile).
class _VodControls extends StatelessWidget {
  const _VodControls({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.isPlaying,
    required this.onSeekBack,
    required this.onSeekToFraction,
    required this.onSeekFwd,
    required this.onPlayPause,
    required this.onTracks,
    this.seekPreview,
  });

  /// Temps CIBLE du seek en cours : bulle dorée au-dessus de la barre,
  /// positionnée à la fraction correspondante (façon Netflix). Null = rien.
  final Duration? seekPreview;

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isPlaying;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekFwd;
  final VoidCallback onPlayPause;

  /// Feuille « Pistes » (audio, sous-titres, format d'image) — LE réglage
  /// qui manquait en mode FILM (terrain 2026-07-17 : « pas moyen d'ajouter
  /// des sous-titres ou changer de langue sur les films »).
  final VoidCallback onTracks;

  /// TAP-SUR-LA-BARRE (façon YouTube, écrans tactiles) : fraction 0..1
  /// de l'endroit touché → l'écran convertit en seek absolu. Le glissé
  /// du doigt le long de la barre fait pareil en continu.
  final ValueChanged<double> onSeekToFraction;

  static String _fmt(Duration d) {
    final int s = d.inSeconds < 0 ? 0 : d.inSeconds;
    final int h = s ~/ 3600;
    final int m = (s % 3600) ~/ 60;
    final int sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  @override
  Widget build(BuildContext context) {
    final int totalMs = duration.inMilliseconds;
    final double frac =
        totalMs > 0 ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
    // AVANCE CHARGÉE (ligne grise façon YouTube) : jamais en-deçà de la lecture.
    final double bufferedFrac =
        totalMs > 0 ? (buffered.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
    final Duration remaining =
        totalMs > 0 ? duration - position : Duration.zero;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ---- Bulle de PREVIEW du temps (pendant un seek) ----
        // Posée au-dessus de la barre, alignée sur la fraction cible :
        // l'œil suit où on atterrit AVANT que l'image ne rattrape (le
        // décodage vidéo a toujours un temps de retard sur le seek).
        SizedBox(
          height: 34,
          child: (seekPreview == null || totalMs <= 0)
              ? const SizedBox.shrink()
              : LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final double f =
                        (seekPreview!.inMilliseconds / totalMs).clamp(0.0, 1.0);
                    // 74 = largeur de la colonne temps à gauche de la barre.
                    const double sideW = 74;
                    final double barW = c.maxWidth - sideW * 2;
                    const double bubbleW = 86;
                    final double left = (sideW + f * barW - bubbleW / 2)
                        .clamp(0.0, c.maxWidth - bubbleW);
                    return Stack(
                      children: <Widget>[
                        Positioned(
                          left: left,
                          top: 0,
                          child: Container(
                            width: bubbleW,
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: TvTokens.ember,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(_fmt(seekPreview!),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: TvTokens.onEmber)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        // ---- Barre de progression (dorée, façon Netflix) ----
        Row(
          children: <Widget>[
            SizedBox(
              width: 74,
              child: Text(_fmt(position),
                  style: TextStyle(
                      fontSize: TvDimens.label,
                      fontWeight: FontWeight.w700,
                      color: TvTokens.text)),
            ),
            Expanded(
              // TAP-SUR-LA-BARRE (YouTube) : toucher un point = sauter
              // exactement là ; glisser le doigt = suivre en continu. La
              // zone de toucher fait 28 px de haut (la barre visible n'en
              // fait que 6 — un doigt n'est pas un curseur), le calcul se
              // fait sur la largeur RÉELLE de la barre via LayoutBuilder.
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  void seekAt(double dx) {
                    if (c.maxWidth <= 0) return;
                    onSeekToFraction((dx / c.maxWidth).clamp(0.0, 1.0));
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (TapDownDetails d) =>
                        seekAt(d.localPosition.dx),
                    onHorizontalDragUpdate: (DragUpdateDetails d) =>
                        seekAt(d.localPosition.dx),
                    child: SizedBox(
                      height: 28,
                      child: Center(
                        // width: infinity → la barre garde TOUTE la largeur
                        // de la colonne (Center donne des contraintes
                        // lâches, sans ça le Stack s'effondrerait).
                        child: SizedBox(
                          height: 6,
                          width: double.infinity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                // Fond de la barre (partie non chargée).
                                Container(color: Colors.white24),
                                // Avance CHARGÉE en tampon (« ligne grise »
                                // YouTube) : jusqu'où le film est prêt à
                                // jouer sans coupure.
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: bufferedFrac,
                                  child:
                                      Container(color: Colors.white38),
                                ),
                                // Position lue (rouge braise, façon Netflix).
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: frac,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                        gradient: TvTokens.cineGradient),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: 74,
              child: Text(
                totalMs > 0 ? '-${_fmt(remaining)}' : '--:--',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: TvDimens.label,
                    fontWeight: FontWeight.w700,
                    color: TvTokens.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // ---- ⏪10 · ▶/⏸ · 10⏩ · Pistes ----
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _CtrlButton(
                icon: Icons.replay_10_rounded,
                label: context.l10n.tvSkip10,
                onTap: onSeekBack),
            const SizedBox(width: 34),
            _CtrlButton(
              icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              label: isPlaying ? context.l10n.tvPause : context.l10n.tvPlay,
              onTap: onPlayPause,
              primary: true,
              accent: TvTokens.ember,
            ),
            const SizedBox(width: 34),
            _CtrlButton(
                icon: Icons.forward_10_rounded,
                label: context.l10n.tvSkip10,
                onTap: onSeekFwd),
            const SizedBox(width: 34),
            // « Pistes » : audio, sous-titres, format — désormais AUSSI en
            // mode film (avant : seulement en direct, donc « pas moyen de
            // changer la langue sur un film » — terrain 2026-07-17).
            _CtrlButton(
                icon: Icons.subtitles_rounded,
                label: context.l10n.tracksTitle,
                onTap: onTracks),
          ],
        ),
        const SizedBox(height: 10),
        // Indice télécommande : la flèche BAS ouvre la même feuille (le
        // geste des plateformes — les boutons ci-dessus sont tactiles).
        Center(
          child: Text(context.l10n.tvVodTracksHint,
              style:
                  TextStyle(fontSize: TvDimens.label, color: TvTokens.mutedDim)),
        ),
      ],
    );
  }
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
    final Color accent = widget.accent ?? TvTokens.ember;
    // Surlignage D-pad = anneau OR épais + halo : visible sur N'IMPORTE quelle
    // télécommande (le repère « où je suis »).
    final Color borderColor = widget.focused
        ? TvTokens.ember
        : (widget.active ? accent : Colors.white24);
    final Color bg = widget.focused
        ? TvTokens.ember.withValues(alpha: 0.28)
        : (widget.active
            ? accent.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.42));
    final Color iconColor = widget.focused
        ? TvTokens.ember
        : (widget.active ? accent : TvTokens.text);
    final Color labelColor = widget.focused
        ? TvTokens.ember
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
                border: Border.all(
                    color: borderColor, width: widget.focused ? 2 : 1),
                boxShadow: widget.focused
                    ? <BoxShadow>[
                        BoxShadow(
                            color: TvTokens.ember.withValues(alpha: 0.45),
                            blurRadius: 24,
                            spreadRadius: -2),
                      ]
                    : null,
              ),
              child: Icon(widget.icon,
                  color: iconColor, size: widget.primary ? 42 : 30),
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

/// Carte « À SUIVRE » (bas-droite) : prochain épisode + compte à rebours +
/// « Lire maintenant » / « Annuler ». Le focus D-pad est ÉMULÉ comme partout
/// dans ce lecteur (cf. _btnFocus de la barre) : l'écran intercepte toutes
/// les touches, donc la carte reçoit juste `focusedIndex` et dessine le
/// surlignage or — n'importe quelle télécommande atteint les 2 boutons.
/// [seconds] null = garde-fou anti-binge atteint (3 enchaînements auto sans
/// interaction) : pas de compte à rebours, on attend un OK explicite.
/// Aucune animation continue ici (le rebours avance par pas d'1 s, l'anneau
/// est un indicateur DÉTERMINÉ qui saute de valeur en valeur) → le réglage
/// « réduire les animations » (MediaQuery.disableAnimations) est respecté
/// par construction, comme les skeletons/marquee du reste de l'app.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.title,
    required this.seconds,
    required this.totalSeconds,
    required this.focusedIndex,
    required this.onPlay,
    required this.onCancel,
  });

  final String title;
  final int? seconds; // null = attend un OK (pas d'auto-lancement)
  final int totalSeconds;
  final int focusedIndex; // 0 = Lire maintenant, 1 = Annuler
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: Colors.white24),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
              spreadRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(context.l10n.tvUpNext.toUpperCase(),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: TvTokens.ember)),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: TvDimens.title,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.text)),
          const SizedBox(height: 10),
          if (seconds != null)
            Row(
              children: <Widget>[
                // Anneau de compte à rebours : déterminé, se vide seconde
                // par seconde (pas d'animation continue).
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: totalSeconds > 0
                        ? (seconds! / totalSeconds).clamp(0.0, 1.0)
                        : 0,
                    strokeWidth: 3,
                    color: TvTokens.ember,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(width: 10),
                Text(context.l10n.tvUpNextAutoIn(seconds!),
                    style: TextStyle(
                        fontSize: TvDimens.body, color: TvTokens.muted)),
              ],
            )
          else
            // Garde-fou anti-binge : la carte attend un OK explicite.
            Text(context.l10n.tvUpNextPressOk,
                style:
                    TextStyle(fontSize: TvDimens.body, color: TvTokens.muted)),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _UpNextButton(
                  icon: Icons.play_arrow_rounded,
                  label: context.l10n.tvUpNextPlayNow,
                  focused: focusedIndex == 0,
                  onTap: onPlay,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _UpNextButton(
                  icon: Icons.close_rounded,
                  label: context.l10n.playerUpNextCancel,
                  focused: focusedIndex == 1,
                  onTap: onCancel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bouton de la carte « À suivre ». Surlignage or = même langage visuel que
/// le reste du lecteur (bouton « Réessayer » de l'écran d'erreur). Répond
/// aussi au doigt (TV/tablette tactile) via GestureDetector.
class _UpNextButton extends StatelessWidget {
  const _UpNextButton({
    required this.icon,
    required this.label,
    required this.focused,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = focused ? const Color(0xFF1A1206) : TvTokens.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:
              focused ? TvTokens.ember : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border: Border.all(
              color: focused ? TvTokens.ember : Colors.white24,
              width: focused ? TvDimens.focusOutline : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  Feuille « Pistes & format d'image » du lecteur TV
// ============================================================
//  LE réglage qui manquait face à TiviMate/IBO : choisir la piste
//  audio (multi-langues), les sous-titres (ou les couper) et le
//  format d'image, à la télécommande. Panneau latéral droit en
//  FOCUS ÉMULÉ (même modèle que la carte « À suivre ») : le parent
//  (_onKey) détourne le D-pad quand il est visible — Haut/Bas
//  déplacent le surlignage, OK applique, Retour ferme. La sélection
//  de piste passe par un TrackSelectionOverride ExoPlayer (aucun
//  rebuild du player) ; le ratio est appliqué côté Flutter.

/// Nature d'une ligne actionnable de la feuille.
enum _SheetKind { audio, textOff, text, aspect }

/// Ligne actionnable : sa nature + l'index dans la liste concernée
/// (piste audio N, piste texte N, mode d'affichage N). textOff : -1.
class _TrackSheetEntry {
  const _TrackSheetEntry({required this.kind, required this.index});
  final _SheetKind kind;
  final int index;
}

class _TracksSheet extends StatefulWidget {
  const _TracksSheet({
    required this.audio,
    required this.text,
    required this.entries,
    required this.focusedIndex,
    required this.aspect,
    required this.onActivate,
    required this.onClose,
  });

  final List<TrackInfo> audio;
  final List<TrackInfo> text;
  final List<_TrackSheetEntry> entries;
  final int focusedIndex;
  final AspectRatioMode aspect;
  final void Function(_TrackSheetEntry) onActivate;
  final VoidCallback onClose;

  @override
  State<_TracksSheet> createState() => _TracksSheetState();
}

class _TracksSheetState extends State<_TracksSheet> {
  static const double _rowH = 48;
  static const double _headerH = 40;
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_TracksSheet old) {
    super.didUpdateWidget(old);
    if (old.focusedIndex != widget.focusedIndex) _ensureFocusVisible();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Fait défiler la liste pour garder la ligne surlignée à l'écran.
  /// Offsets calculés à la main (lignes à hauteur fixe) : pas besoin
  /// de GlobalKeys ni d'ensureVisible.
  void _ensureFocusVisible() {
    if (!_scroll.hasClients) return;
    double offset = 0;
    int focusable = -1;
    for (final _DisplayRow r in _displayRows()) {
      if (r.entry != null) {
        focusable++;
        if (focusable == widget.focusedIndex) break;
      }
      offset += r.entry == null ? _headerH : _rowH;
    }
    final double target =
        (offset - 3 * _rowH).clamp(0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  /// Liste d'affichage : en-têtes de section intercalés entre les
  /// lignes actionnables (dans le MÊME ordre que widget.entries).
  List<_DisplayRow> _displayRows() {
    final List<_DisplayRow> rows = <_DisplayRow>[];
    _SheetKind? lastSection;
    for (final _TrackSheetEntry e in widget.entries) {
      final _SheetKind section =
          e.kind == _SheetKind.textOff ? _SheetKind.text : e.kind;
      if (section != lastSection) {
        rows.add(_DisplayRow.header(section));
        lastSection = section;
      }
      rows.add(_DisplayRow.entry(e));
    }
    return rows;
  }

  String _headerLabel(BuildContext context, _SheetKind kind) {
    switch (kind) {
      case _SheetKind.audio:
        return context.l10n.tracksAudio;
      case _SheetKind.text:
      case _SheetKind.textOff:
        return context.l10n.tracksSubtitles;
      case _SheetKind.aspect:
        return context.l10n.tracksAspectSection;
    }
  }

  /// Libellé humain d'une piste : label du flux, complété par la
  /// langue localisée quand elle est connue (« Français · fra »).
  String _trackLabel(BuildContext context, TrackInfo t) {
    if (t.language.isEmpty) return t.label;
    final String lang = trackLanguageLabel(context, t.language);
    if (t.label.isEmpty || t.label.toUpperCase() == t.language.toUpperCase()) {
      return lang;
    }
    return '${t.label} · $lang';
  }

  (String, bool) _entryPresentation(BuildContext context, _TrackSheetEntry e) {
    switch (e.kind) {
      case _SheetKind.audio:
        final TrackInfo t = widget.audio[e.index];
        return (_trackLabel(context, t), t.selected);
      case _SheetKind.textOff:
        final bool noneSelected =
            widget.text.every((TrackInfo t) => !t.selected);
        return (context.l10n.trackDisabled, noneSelected);
      case _SheetKind.text:
        final TrackInfo t = widget.text[e.index];
        return (_trackLabel(context, t), t.selected);
      case _SheetKind.aspect:
        final AspectRatioMode m = AspectRatioMode.values[e.index];
        return (m.localizedLabel(context), m == widget.aspect);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<_DisplayRow> rows = _displayRows();
    int focusable = -1;
    return Container(
      width: 400,
      padding: const EdgeInsets.fromLTRB(
          24, TvDimens.safeV, TvDimens.safeH, TvDimens.safeV),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: <Color>[Color(0xF20A0A0C), Color(0x000A0A0C)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.l10n.tracksTitle,
              style: const TextStyle(
                  fontSize: TvDimens.headline,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.text)),
          const SizedBox(height: 4),
          // Aucune piste audio déclarée : on reste discret mais honnête.
          if (widget.audio.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(context.l10n.tracksNoAudio,
                  style:
                      const TextStyle(fontSize: 13, color: TvTokens.mutedDim)),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              controller: _scroll,
              children: rows.map((_DisplayRow r) {
                if (r.entry == null) {
                  return SizedBox(
                    height: _headerH,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _headerLabel(context, r.section!).toUpperCase(),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: TvTokens.gold),
                        ),
                      ),
                    ),
                  );
                }
                focusable++;
                final bool focused = focusable == widget.focusedIndex;
                final (String label, bool selected) =
                    _entryPresentation(context, r.entry!);
                return SizedBox(
                  height: _rowH,
                  child: GestureDetector(
                    // Tactile (tablette / TV tactile) : tap direct.
                    onTap: () => widget.onActivate(r.entry!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: focused ? TvTokens.gold : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            selected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            size: 18,
                            color: focused
                                ? const Color(0xFF1A1206)
                                : (selected
                                    ? TvTokens.gold
                                    : TvTokens.mutedDim),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: focused
                                    ? const Color(0xFF1A1206)
                                    : TvTokens.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne d'affichage de la feuille : en-tête de section OU entrée.
class _DisplayRow {
  const _DisplayRow.header(this.section) : entry = null;
  const _DisplayRow.entry(this.entry) : section = null;
  final _SheetKind? section;
  final _TrackSheetEntry? entry;
}

// ============================================================================
//  _BufferVeil — dissimulation « hypnotique » du buffering.
//
//  Règle : JAMAIS de spinner dans le lecteur. Pendant un zap ou une
//  (re)connexion, la dernière image du flux reste FIGÉE sous un voile noir
//  profond (~90-97 %, vignette radiale) et le logo de la chaîne visée
//  « respire » lentement (opacité 0.45→1 + micro-scale 0.97→1.03, cycle
//  2,4 s). L'œil comprend « ça arrive » sans jamais voir d'attente.
//
//  Le flou gaussien plein écran de la spec est REMPLACÉ par ce voile, à
//  dessein : un BackdropFilter 60 fps par-dessus la SurfaceView est hors
//  budget GPU des box d'entrée de gamme (règle « hardware-bound » de la
//  même spec) — et en composition hybride il ne capturerait même pas la
//  vidéo. Le voile donne le même effet perçu pour un coût GPU nul.
//
//  Perf : RepaintBoundary → seule cette couche se repeint pendant la
//  pulsation ; l'animation ne vit que tant que le voile est monté.
// ============================================================================
class _BufferVeil extends StatefulWidget {
  const _BufferVeil({required this.channel});

  final Channel channel;

  @override
  State<_BufferVeil> createState() => _BufferVeilState();
}

class _BufferVeilState extends State<_BufferVeil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  late final Animation<double> _ease =
      CurvedAnimation(parent: _breath, curve: Curves.easeInOut);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? logo = widget.channel.logoUrl;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 1.1,
            colors: <Color>[Color(0xE6000000), Color(0xF7000000)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.45, end: 1).animate(_ease),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1.03).animate(_ease),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 132,
                    height: 132,
                    child: (logo != null && logo.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: logo,
                            fit: BoxFit.contain,
                            memCacheWidth: 264,
                            fadeInDuration:
                                const Duration(milliseconds: 120),
                            placeholder: (_, __) =>
                                const Center(child: TvLogo(width: 120)),
                            errorWidget: (_, __, ___) =>
                                const Center(child: TvLogo(width: 120)),
                          )
                        : const Center(child: TvLogo(width: 120)),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    widget.channel.cleanName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: TvDimens.title,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: TvTokens.text,
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
}
