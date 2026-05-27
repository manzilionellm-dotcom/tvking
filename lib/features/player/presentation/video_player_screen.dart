// =========================================================
//  video_player_screen.dart — Lecteur vidéo HAUT NIVEAU
// =========================================================
//  Phase 1.3 — version améliorée :
//
//    - Décodage hardware (hwdec=auto-safe) pour 4K/8K
//    - Buffer configurable (5-60s, défaut 20s)
//    - Pistes audio multiples sélectionnables
//    - Sous-titres sélectionnables
//    - Vitesse de lecture (0.5x → 2x)
//    - Ratio d'affichage (16:9, 4:3, fit, fill, stretch, 2.39:1)
//    - Overlay statistiques (résolution, codec, FPS)
//    - Plein écran immersif + wakelock
//    - Recharge en cas d'erreur
//    - Réglages persistés entre sessions
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/live_badge.dart';
import '../../cast/data/cast_manager.dart';
import '../../cast/presentation/cast_picker_sheet.dart';
import '../../cast/presentation/qr_cast_sheet.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/data/watch_history_repository.dart';
import '../../channels/domain/channel.dart';
import '../../onboarding/data/device_class_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../recordings/data/http_recording_downloader.dart';
import '../../recordings/data/recording_repository.dart';
import '../../recordings/data/recording_service.dart';
import '../../recordings/domain/recording.dart';
import '../data/pip_service.dart';
import '../data/player_settings.dart';
import 'widgets/player_settings_sheet.dart';
import 'widgets/player_stats_overlay.dart';
import 'widgets/player_tracks_sheet.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    required this.channel,
    this.zapPlaylist,
    this.overrideUrl,
    this.overrideTitle,
    super.key,
  });

  final Channel channel;

  /// Si fourni, le player active les boutons ⏮ / ⏭ pour zapper
  /// dans cette liste. Sinon ces boutons sont masqués.
  final List<Channel>? zapPlaylist;

  /// Si fourni, on lit cette URL au lieu de `channel.streamUrl`.
  /// Sert pour le catch-up / replay.
  final String? overrideUrl;

  /// Titre à afficher en surimpression (ex : nom du programme).
  final String? overrideTitle;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  bool _overlayVisible = true;
  Timer? _hideOverlayTimer;

  bool _hasError = false;
  String? _errorMessage;
  bool _isBuffering = true;
  bool _isPlaying = false;

  // Pour le zapping : la chaîne courante (peut changer dans la session
  // sans recréer l'écran) et l'index dans la zapPlaylist.
  late Channel _currentChannel;

  // Enregistrement en cours (null si pas d'enregistrement actif).
  Recording? _activeRecording;
  bool get _isRecording => _activeRecording != null;

  // Picture-in-Picture : implémenté en NATIF Android via
  // MainActivity.kt + MethodChannel `tvking/pip`. Pas de plugin
  // tiers — voir `lib/features/player/data/pip_service.dart` et
  // l'override `onUserLeaveHint` côté Kotlin. Mode YouTube
  // Premium : la vidéo continue en mini-fenêtre quand l'user
  // appuie HOME pendant la lecture.

  /// ID de la session de visionnage en cours (table `watch_sessions`).
  /// Démarrée dans `initState`, fermée dans `dispose`. Sert au Hook
  /// Model : Continue Watching + affinity scoring.
  int _watchSessionId = 0;

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  /// PageController du swipe TikTok-style. Initialisé en LAZY dans le
  /// build car `_zapIndex` dépend de la position dans la playlist et
  /// du `_currentChannel` qui peut changer. Reste `null` sur TV ou
  /// quand `_canZap == false` (pas de playlist).
  PageController? _zapPageController;

  /// Quand on appelle `_zapTo` depuis un BOUTON (⏮/⏭, télécommande),
  /// on déclenche `animateToPage` sur le PageController, qui à son
  /// tour tire `onPageChanged`. Pour éviter de re-traiter le swipe
  /// déjà appliqué (double `_player.open`), on flag pendant l'animation.
  bool _zapAnimating = false;

  @override
  void initState() {
    super.initState();

    _currentChannel = widget.channel;

    // Écoute les changements d'état PiP côté natif. Quand l'OS bascule
    // en mini-fenêtre, on cache d'autorité l'overlay des contrôles —
    // ses boutons seraient illisibles à 300×170 et masqueraient la vidéo.
    PipService.instance.addListener(_onPipChanged);
    // Aspect ratio par défaut — la plupart des flux IPTV sont 16:9.
    PipService.instance.setAspectRatio(numerator: 16, denominator: 9);

    // Ouvre une session de visionnage pour le Hook Model.
    // Fire-and-forget — on n'attend pas l'I/O DB.
    WatchHistoryRepository.instance
        .startSession(
          channelId: widget.channel.id,
          channelName: widget.channel.cleanName,
        )
        .then((int id) => _watchSessionId = id);

    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // ROTATION AUTO QUI SUIT LE TÉLÉPHONE (style YouTube / Netflix).
    //
    // L'utilisateur veut que la vidéo tourne en fonction de COMMENT
    // il tient son téléphone : portrait → vidéo en portrait avec
    // bandeaux noirs en haut/bas, paysage → vidéo plein cadre 16:9.
    // Pas de forçage : c'est le capteur d'orientation qui décide.
    //
    // En spécifiant les 3 orientations utiles au système Android via
    // `setPreferredOrientations`, on outrepasse le réglage 'rotation
    // automatique' du système : MÊME SI l'utilisateur a désactivé
    // l'auto-rotate dans son panneau rapide, la vidéo tournera
    // quand même quand il bascule son téléphone — c'est exactement
    // le comportement YouTube / Netflix.
    //
    // On exclut `portraitDown` (téléphone tête en bas) — personne ne
    // regarde de vidéo retournée à 180°, et certains téléphones n'ont
    // de toute façon pas de capteur pour cette orientation-là.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // (PiP temporairement désactivé — voir note plus haut)

    // Charge d'abord les réglages persistés
    PlayerSettings.instance.load();

    // Configure le Player avec un buffer généreux (pour 4K/8K)
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: PlayerSettings.instance.bufferBytes,
        // Logs visibles seulement en debug, pas en release
        logLevel: MPVLogLevel.warn,
      ),
    );
    _videoController = VideoController(_player);

    // Applique les options libmpv pour hardware decoding + cache
    _applyMpvOptions();

    // Abonne aux événements
    _subs.add(_player.stream.buffering.listen((bool b) {
      if (mounted) setState(() => _isBuffering = b);
    }));
    _subs.add(_player.stream.playing.listen((bool p) {
      if (mounted) {
        setState(() {
          _isPlaying = p;
          // Si le stream se met à jouer, on dégage l'overlay d'erreur
          // (libmpv envoie souvent des warnings "force-seekable" qui ne
          // sont pas fatals — la vidéo joue quand même).
          if (p && _hasError) {
            _hasError = false;
            _errorMessage = null;
          }
        });
      }
      // Signal au natif Android pour le PiP auto : "lecture en
      // cours". Si l'utilisateur appuie HOME pendant que `p == true`,
      // MainActivity.onUserLeaveHint() entrera en mini-fenêtre
      // (style YouTube Premium). Aucun appel quand `p == false`
      // = home → app cachée normalement (pas de PiP).
      PipService.instance.setPlaybackActive(p);
    }));
    _subs.add(_player.stream.error.listen((String e) {
      if (!mounted) return;
      // Filtre les messages non-fatals de libmpv. Liste basée
      // sur les messages courants qui ne bloquent PAS la lecture :
      //   - "force-seekable" : seek impossible (normal pour le live)
      //   - "demuxer warning" : avertissement de démultiplexeur
      //   - "first-frame-late" : décodage légèrement en retard
      //   - "Audio device underrun" : artefact son temporaire
      final String lower = e.toLowerCase();
      const List<String> nonFatal = <String>[
        'force-seekable',
        'demuxer',
        'first-frame',
        'underrun',
        'discontinuity',
        'frame drop',
      ];
      final bool isWarning =
          nonFatal.any((String pattern) => lower.contains(pattern));
      if (isWarning) {
        // On log mais on n'affiche pas l'overlay d'erreur
        debugPrint('[Player] WARNING (ignoré) : $e');
        return;
      }
      // Si la lecture est déjà active, c'est probablement aussi
      // un warning tardif — on ne casse pas l'expérience.
      if (_isPlaying) {
        debugPrint('[Player] Erreur reçue pendant la lecture, ignorée : $e');
        return;
      }
      setState(() {
        _hasError = true;
        _errorMessage = e;
      });
    }));

    // Listener pour les changements de réglages → réapplication immédiate
    PlayerSettings.instance.addListener(_onSettingsChanged);

    // URL effective : overrideUrl (catch-up) sinon stream live
    final String url = widget.overrideUrl ?? _currentChannel.streamUrl;
    _player.open(Media(url));

    // Restaure la dernière vitesse
    if (PlayerSettings.instance.lastSpeed != 1.0) {
      _player.setRate(PlayerSettings.instance.lastSpeed);
    }

    _scheduleHideOverlay();
  }

  // ----- Zapping -----

  bool get _canZap =>
      widget.zapPlaylist != null && widget.zapPlaylist!.length > 1;

  /// `true` quand l'écran tourne sur une TV / Android TV / Fire TV
  /// (10-foot UI, télécommande). Le layout du player s'adapte —
  /// boutons focusables au D-pad, ⏮/⏭ visibles, pas de swipe.
  /// Appelé dans build() donc le context est dispo.
  bool get _isTvUi => DeviceClassRepository.instance.isTvFor(context);

  int get _zapIndex {
    if (widget.zapPlaylist == null) return -1;
    return widget.zapPlaylist!
        .indexWhere((Channel c) => c.id == _currentChannel.id);
  }

  /// Zap à un index donné. Appelé depuis :
  ///   - les boutons ⏮/⏭ (avec wrap modulo pour la liste circulaire)
  ///   - la télécommande TV
  ///   - le PageView TikTok via `_onZapPageChanged` (index déjà borné)
  ///
  /// Si un PageController est actif (mode TikTok), on lui demande
  /// d'animer la transition, ce qui déclenchera `onPageChanged` qui
  /// appellera `_applyZap`. Sinon on appelle `_applyZap` direct.
  void _zapTo(int newIndex) {
    if (widget.zapPlaylist == null) return;
    final List<Channel> list = widget.zapPlaylist!;
    if (list.isEmpty) return;
    final int wrapped = ((newIndex % list.length) + list.length) % list.length;

    if (_zapPageController != null && _zapPageController!.hasClients) {
      // Animation fluide TikTok-style. `_zapAnimating` empêche le
      // double-firing de `onPageChanged` pendant l'animation.
      _zapAnimating = true;
      _zapPageController!
          .animateToPage(
            wrapped,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _zapAnimating = false);
    } else {
      // Mode TV ou playlist absente → bascule direct.
      _applyZap(wrapped);
    }
  }

  /// Applique réellement le changement de chaîne. Tirée par `_zapTo`
  /// directement (mode TV) ou par `onPageChanged` du PageView après
  /// le snap d'un swipe utilisateur.
  void _applyZap(int newIndex) {
    if (widget.zapPlaylist == null) return;
    final List<Channel> list = widget.zapPlaylist!;
    if (newIndex < 0 || newIndex >= list.length) return;
    final Channel next = list[newIndex];
    // Ignore si on est déjà sur cette chaîne (évite un `_player.open`
    // redondant qui re-démarrerait le buffering pour rien).
    if (next.id == _currentChannel.id) return;
    setState(() {
      _currentChannel = next;
      _hasError = false;
      _errorMessage = null;
      _isBuffering = true;
    });
    RecentlyWatchedRepository.instance.record(next.id);
    // Zap = nouvelle session côté Hook Model. On ferme l'ancienne et
    // on en ouvre une nouvelle pour que les durées soient justes.
    if (_watchSessionId > 0) {
      WatchHistoryRepository.instance.endSession(_watchSessionId);
    }
    WatchHistoryRepository.instance
        .startSession(
          channelId: next.id,
          channelName: next.cleanName,
        )
        .then((int id) => _watchSessionId = id);
    _player.open(Media(next.streamUrl));
    _scheduleHideOverlay();
  }

  /// Callback du `PageView` quand l'utilisateur a fini un swipe vertical.
  void _onZapPageChanged(int newIndex) => _applyZap(newIndex);

  void _zapNext() => _zapTo(_zapIndex + 1);
  void _zapPrev() => _zapTo(_zapIndex - 1);

  // ----- Enregistrement -----

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
    _scheduleHideOverlay();
  }

  Future<void> _startRecording() async {
    try {
      final String path =
          await RecordingRepository.instance.createFilePath(
        channelName: _currentChannel.cleanName,
        programTitle: widget.overrideTitle,
      );

      // NOUVEAU PIPELINE : on n'utilise PLUS `stream-record` de libmpv
      // qui s'avère silencieusement inopérant sur les flux IPTV
      // testés par l'utilisateur (BFM TV 3 min → 0 octets).
      //
      // À la place, un downloader HTTP en Dart pur (cf.
      // http_recording_downloader.dart) ouvre une 2e connexion vers
      // le même streamUrl et écrit les bytes dans le fichier .ts au
      // fur et à mesure. Plus aucune dépendance à libmpv pour
      // l'enregistrement — on contrôle TOUT côté Dart.
      //
      // Note : 2 connexions HTTP au serveur Xtream (1 pour le player,
      // 1 pour le downloader). Certains fournisseurs limitent à 1
      // connexion/credentials — on verra à l'usage.
      // ORDRE CRITIQUE POUR L'ENREGISTREMENT EN ARRIÈRE-PLAN :
      //
      //   1. Démarrer le ForegroundService EN PREMIER pour qu'il
      //      acquière le PartialWakeLock + WifiLock AVANT que la
      //      requête HTTP du downloader ne s'ouvre. Sinon, dès que
      //      l'user appuie HOME, Android met le CPU en sommeil et
      //      coupe le WiFi → la socket HTTP est tuée → enregistrement
      //      s'arrête sans qu'on s'en rende compte.
      //
      //   2. PUIS lancer le download HTTP qui hérite du contexte
      //      'awake' garanti par les locks du service.
      //
      // C'était le bug du screenshot 'ADULT: ALBA XXX' du user :
      // 27 Mo en foreground, 0 octet de plus dès qu'il quittait l'app.
      await RecordingService.instance.start(
        title: widget.overrideTitle != null && widget.overrideTitle!.isNotEmpty
            ? '${_currentChannel.cleanName} – ${widget.overrideTitle}'
            : _currentChannel.cleanName,
      );

      final bool ok = await HttpRecordingDownloader.instance.start(
        streamUrl: _currentChannel.streamUrl,
        filePath: path,
      );
      if (!ok) {
        // Si le download n'a pas pu démarrer, on annule aussi le
        // service pour ne pas garder une notification fantôme.
        await RecordingService.instance.stop();
        _toast(
          'Enregistrement impossible : le serveur a refusé la requête. '
          'Vérifie ton URL ou demande à ton fournisseur d\'autoriser '
          '2 connexions sur ton compte.',
        );
        return;
      }

      final Recording rec =
          await RecordingRepository.instance.startRecording(
        channelId: _currentChannel.id,
        channelName: _currentChannel.cleanName,
        programTitle: widget.overrideTitle,
        filePath: path,
        channelLogoUrl: _currentChannel.logoUrl,
      );

      if (mounted) {
        setState(() => _activeRecording = rec);
        _toast(
          'Enregistrement démarré — continue même hors application',
        );
      }
    } catch (e) {
      _toast('Impossible de démarrer : $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final Recording? rec = _activeRecording;

      // Arrête UNIQUEMENT le job de CE recording (par filePath).
      // Critique pour les recordings parallèles : sinon on tuerait
      // aussi les autres chaînes que l'user enregistre en même temps
      // depuis d'autres sessions player.
      final int bytes = rec != null
          ? await HttpRecordingDownloader.instance.stop(filePath: rec.filePath)
          : await HttpRecordingDownloader.instance.stop();

      if (rec != null) {
        await RecordingRepository.instance.finishRecording(rec);
      }

      // Le ForegroundService natif ne s'arrête QUE si plus AUCUN
      // recording n'est actif. Sinon on garde le service vivant
      // pour protéger les autres enregistrements parallèles.
      if (HttpRecordingDownloader.instance.activeCount == 0) {
        await RecordingService.instance.stop();
      }

      if (mounted) {
        setState(() => _activeRecording = null);
        // Formatage taille : Bytes / KB / MB / GB selon ordre de grandeur.
        final String sizeLabel = _humanSize(bytes);
        if (bytes == 0) {
          _toast(
            'Enregistrement vide. Ton fournisseur IPTV n\'autorise '
            'qu\'une seule connexion à la fois — demande à augmenter '
            'la limite pour pouvoir enregistrer.',
          );
        } else {
          _toast(
            'Enregistrement sauvegardé ($sizeLabel) — '
            'exporte depuis Mes enregistrements',
          );
        }
      }
    } catch (e) {
      _toast('Erreur arrêt enregistrement : $e');
    }
  }

  /// Convertit un nombre d'octets en chaîne lisible (KB / MB / GB).
  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<bool> _setMpvProperty(String name, String value) async {
    try {
      // ignore: invalid_use_of_protected_member
      final dynamic native = (_player.platform as dynamic);
      await native?.setProperty(name, value);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceHigh,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        content: Text(message, style: AppTextStyles.bodyLarge),
      ),
    );
  }

  Future<void> _applyMpvOptions() async {
    final PlayerSettings s = PlayerSettings.instance;

    // Décodage hardware si activé.
    // "auto-safe" = tente HW, retombe sur SW si pas dispo (sans bug visuel).
    final String hwdec = s.hardwareDecode ? 'auto-safe' : 'no';

    // Les properties libmpv ne sont accessibles que via la
    // surface native du player (pas l'API Dart de haut niveau).
    // On essaie/catch parce que certaines plateformes ne
    // l'exposent pas (web par ex.).
    try {
      // ignore: invalid_use_of_protected_member
      final dynamic native = (_player.platform as dynamic);
      await native?.setProperty('hwdec', hwdec);
      await native?.setProperty('cache', 'yes');
      // Maximum 4 secondes de retour en arrière à mettre en cache
      await native?.setProperty('cache-secs', s.bufferSeconds.toString());

      // === STABILITÉ LONGUE DURÉE (fix bug "lit 2 min et recommence") ===
      //
      // L'user constatait que le player s'arrêtait après ~2 min sur
      // certaines chaînes puis redémarrait depuis le début. Cause
      // typique : le serveur IPTV ferme la connexion HTTP (session
      // timeout ou idle keepalive), libmpv détecte EOS et reset.
      //
      // Options ajoutées pour rendre le player "le plus puissant
      // de sa catégorie" sur lecture continue 24/7 :

      // 1. Reconnexion automatique côté libavformat (FFmpeg).
      //    Si le serveur coupe ou que le réseau lag, libmpv
      //    rejoint la connexion sans tuer le pipeline.
      //    - reconnect=1            : reconnecte sur erreur HTTP
      //    - reconnect_streamed=1   : OK aussi sur les flux non-seekable
      //    - reconnect_delay_max=30 : jusqu'à 30s de backoff
      //    - reconnect_at_eof=1     : redémarre aussi à l'EOF prématuré
      //    - reconnect_on_http_error=4xx,5xx : reconnect sur erreurs HTTP
      await native?.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=30,'
            'reconnect_at_eof=1,reconnect_on_http_error=4xx,5xx,'
            'reconnect_on_network_error=1',
      );

      // 2. Cache demuxer généreux — absorbe les hoquets réseau
      //    sans interrompre la lecture. Valeurs élevées car les
      //    téléphones modernes ont >4 GB RAM.
      //    - demuxer-max-bytes      : 512 MiB de buffer avant
      //    - demuxer-max-back-bytes : 128 MiB de back-buffer
      //    - demuxer-readahead-secs : 20s d'avance bufferisée
      await native?.setProperty('demuxer-max-bytes', '536870912');
      await native?.setProperty('demuxer-max-back-bytes', '134217728');
      await native?.setProperty('demuxer-readahead-secs', '20');

      // 3. Ne pas pause sur cache underrun — préfère un micro
      //    rebuffer transparent qu'un freeze de la lecture.
      await native?.setProperty('cache-pause', 'no');
      await native?.setProperty('cache-pause-wait', '1');

      // 4. Timeout réseau confortable (60s vs 10s par défaut).
      //    Sur 4G/5G en mobilité, les RTT peuvent piquer >10s.
      await native?.setProperty('network-timeout', '60');

      // 5. keep-open=yes : NE PAS quitter le player sur EOF.
      //    Sans ça, certains flux malformés font sortir libmpv
      //    de la lecture et l'écran reste figé sur la dernière
      //    frame avant de redémarrer (= le bug "2min recommence").
      await native?.setProperty('keep-open', 'yes');
      await native?.setProperty('keep-open-pause', 'no');

      // 6. User-Agent mimant VLC — certains Xtream bloquent
      //    les UA "libmpv" ou "Dart" et coupent la connexion
      //    après le timeout par défaut côté serveur (~120s).
      await native?.setProperty(
        'user-agent',
        'VLC/3.0.18 LibVLC/3.0.18',
      );

      // 7. force-seekable=yes : même sur des flux live qui
      //    déclarent ne pas être seekable, libmpv peut zapper
      //    dans le cache → permet le rebobinage des 20s.
      await native?.setProperty('force-seekable', 'yes');
    } catch (_) {
      // Pas grave, on continue avec les défauts.
    }
  }

  void _onSettingsChanged() {
    // Quand l'utilisateur change un réglage en cours de lecture
    // → applique en live ce qui peut l'être à chaud.
    _applyMpvOptions();
    if (mounted) setState(() {}); // pour le ratio
  }

  @override
  void dispose() {
    _hideOverlayTimer?.cancel();
    for (final StreamSubscription<dynamic> s in _subs) {
      s.cancel();
    }
    // Ferme proprement la session de visionnage. Si l'app est killée
    // sans dispose, _cleanupAbandoned() au prochain boot rattrape.
    if (_watchSessionId > 0) {
      WatchHistoryRepository.instance.endSession(_watchSessionId);
    }
    PlayerSettings.instance.removeListener(_onSettingsChanged);
    _zapPageController?.dispose();
    _player.dispose();
    WakelockPlus.disable();
    // À la sortie du lecteur, on dit au natif "plus de playback"
    // pour qu'un futur appui HOME ne déclenche pas le PiP par erreur
    // (ex. si l'user revient sur la home pour zapper rapidement).
    PipService.instance.setPlaybackActive(false);
    PipService.instance.removeListener(_onPipChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Restaure portrait-only en quittant le player (l'accueil et les
    // autres écrans sont conçus en portrait).
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  // ----- Helpers UX -----

  void _scheduleHideOverlay() {
    _hideOverlayTimer?.cancel();
    _hideOverlayTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  void _toggleOverlay() {
    // En mini-fenêtre PiP, l'overlay des contrôles serait illisible
    // et masquerait la vidéo. On bloque le toggle. L'utilisateur
    // pilote la mini-fenêtre via les contrôles natifs Android.
    if (PipService.instance.isInPipMode) return;
    setState(() => _overlayVisible = !_overlayVisible);
    if (_overlayVisible) _scheduleHideOverlay();
  }

  /// Appelé chaque fois que l'état PiP change côté natif. On force
  /// l'overlay à se cacher dès qu'on entre en mini-fenêtre.
  void _onPipChanged() {
    if (!mounted) return;
    if (PipService.instance.isInPipMode && _overlayVisible) {
      setState(() => _overlayVisible = false);
    }
  }

  void _togglePlayPause() {
    if (_player.state.playing) {
      _player.pause();
    } else {
      _player.play();
    }
    _scheduleHideOverlay();
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _isBuffering = true;
    });
    final String url = widget.overrideUrl ?? _currentChannel.streamUrl;
    _player.open(Media(url));
  }

  Future<void> _openTracks() async {
    _hideOverlayTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PlayerTracksSheet(player: _player),
    );
    _scheduleHideOverlay();
  }

  Future<void> _openCastPicker() async {
    final String url = widget.overrideUrl ?? _currentChannel.streamUrl;
    final String title = widget.overrideTitle ?? _currentChannel.cleanName;
    _hideOverlayTimer?.cancel();
    await showCastPicker(context, streamUrl: url, title: title);
    _scheduleHideOverlay();
  }

  Future<void> _openQrCast() async {
    final String url = widget.overrideUrl ?? _currentChannel.streamUrl;
    final String title = widget.overrideTitle ?? _currentChannel.cleanName;
    _hideOverlayTimer?.cancel();
    await showQrCastSheet(context, streamUrl: url, channelName: title);
    _scheduleHideOverlay();
  }

  /// Bouton manuel "Mini-fenêtre" dans la rangée de contrôles du
  /// player. Permet de tester / utiliser le PiP sans devoir
  /// appuyer HOME. Utile aussi sur les devices où onUserLeaveHint
  /// n'est pas appelé (MIUI / certaines surcouches).
  Future<void> _enterPipManually() async {
    final bool ok = await PipService.instance.enterPip();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Mini-fenêtre indisponible sur cet appareil (requiert Android 8+). '
            'Active aussi la permission Picture-in-picture dans : '
            'Paramètres → Apps → 7 MOTION → Permissions.',
            style: AppTextStyles.bodyMedium,
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _openSettings() async {
    _hideOverlayTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PlayerSettingsSheet(
        currentSpeed: _player.state.rate,
        onSpeedChange: (double s) => _player.setRate(s),
      ),
    );
    _scheduleHideOverlay();
  }

  // ============================================================
  //  Télécommande Android TV / Fire TV — touches média + D-pad
  // ============================================================
  //  La télécommande envoie des `LogicalKeyboardKey` Flutter
  //  standard, mais SANS handler explicite l'app ne fait rien
  //  quand on appuie Play / Pause / Channel±. On câble ici la
  //  logique pour offrir l'expérience "vraie TV" :
  //
  //    Play / Pause / PlayPause / Space        → toggle play
  //    Stop / Back-long-press                  → sort du lecteur
  //    MediaTrackNext / Channel+               → chaîne suivante
  //    MediaTrackPrevious / Channel-           → chaîne précédente
  //    FastForward / Flèche droite (no overlay)→ +10 secondes
  //    Rewind      / Flèche gauche (no overlay)→ -10 secondes
  //    Flèche haut/bas (no overlay)            → zap suivant/précédent
  //    OK / Enter / Select (no overlay)        → afficher l'overlay
  //
  //  Quand l'overlay des contrôles est visible, on laisse les
  //  flèches naviguer entre les boutons (focus traversal Flutter
  //  natif) au lieu de zapper — sinon on ne pourrait pas changer
  //  les réglages à la télécommande. Les touches MEDIA_* en
  //  revanche sont TOUJOURS interceptées, peu importe l'overlay.
  // ============================================================

  /// Saute de `delta` secondes (positif = avance, négatif = recul).
  /// Borne à zéro pour éviter de seek négatif. Affiche un mini-toast
  /// pour confirmer visuellement le saut (utile en TV sans haptique).
  void _seekBy(Duration delta) {
    final Duration current = _player.state.position;
    Duration target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    _player.seek(target);
    final int secs = delta.inSeconds;
    _toast(secs >= 0 ? '⟳ +${secs}s' : '⟲ ${secs}s');
  }

  /// Handler clavier / télécommande. Branché sur le `Focus` parent
  /// du Scaffold. Retourne `KeyEventResult.handled` quand l'événement
  /// est consommé (pour stopper la propagation) ou `ignored` quand on
  /// veut laisser les Focus enfants gérer (ex. nav dans l'overlay).
  KeyEventResult _handlePlayerKeyEvent(FocusNode node, KeyEvent event) {
    // KeyDownEvent uniquement — éviter de tirer 2× sur Up + Down.
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;

    // -------- Touches média : TOUJOURS interceptées --------
    if (k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaStop) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackNext ||
        k == LogicalKeyboardKey.channelDown) {
      if (_canZap) _zapNext();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackPrevious ||
        k == LogicalKeyboardKey.channelUp) {
      if (_canZap) _zapPrev();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }

    // -------- Flèches : seulement si overlay caché --------
    // Sinon on bloquerait la nav D-pad dans les boutons de l'overlay.
    if (!_overlayVisible) {
      if (k == LogicalKeyboardKey.arrowUp) {
        if (_canZap) _zapPrev();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        if (_canZap) _zapNext();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft) {
        _seekBy(const Duration(seconds: -10));
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        _seekBy(const Duration(seconds: 10));
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.space ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter ||
          k == LogicalKeyboardKey.select) {
        _toggleOverlay();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // ----- Mapping AspectRatioMode → BoxFit + ratio -----

  BoxFit _fitFromMode(AspectRatioMode m) {
    switch (m) {
      case AspectRatioMode.fit:
        return BoxFit.contain;
      case AspectRatioMode.fill:
        return BoxFit.cover;
      case AspectRatioMode.stretch:
        return BoxFit.fill;
      case AspectRatioMode.ratio169:
      case AspectRatioMode.ratio43:
      case AspectRatioMode.ratio219:
        return BoxFit.contain;
    }
  }

  double? _forcedAspect(AspectRatioMode m) {
    switch (m) {
      case AspectRatioMode.ratio169:
        return 16 / 9;
      case AspectRatioMode.ratio43:
        return 4 / 3;
      case AspectRatioMode.ratio219:
        return 2.39;
      default:
        return null;
    }
  }

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    final bool useTikTokSwipe = _canZap && !_isTvUi;
    // Initialise le PageController au PREMIER build où on en a besoin.
    // Lazy car `_zapIndex` dépend de `_currentChannel` qui peut changer
    // entre initState et le premier build (race condition rare mais
    // évitable comme ça).
    if (useTikTokSwipe && _zapPageController == null) {
      final int initial = _zapIndex.clamp(0, widget.zapPlaylist!.length - 1);
      _zapPageController = PageController(initialPage: initial);
    }

    // Le `Focus` parent reçoit les touches télécommande qui n'ont
    // PAS été consommées par les widgets enfants (boutons de
    // l'overlay quand il est visible, p. ex.). `autofocus: true`
    // garantit qu'au cold start le player capte les touches même
    // si rien d'autre n'a le focus.
    //
    // `PopScope(canPop: false, ...)` intercepte le back gesture /
    // bouton retour pour entrer en PiP au lieu de fermer le
    // player — comportement YouTube Premium canonique : "tu n'as
    // pas DIT que tu voulais arrêter la vidéo, tu as juste appuyé
    // back, donc je continue de jouer en mini-fenêtre."
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Focus(
        autofocus: true,
        onKeyEvent: _handlePlayerKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: useTikTokSwipe
              ? _buildTikTokPageView()
              : _buildPlayerSurface(),
        ),
      ),
    );
  }

  /// Intercepteur du BACK. Si la vidéo joue ET que le PiP est
  /// supporté ET qu'on n'est pas déjà en PiP, on entre en mini-
  /// fenêtre plutôt que de fermer le player. Sinon, pop normal.
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return; // déjà sorti, rien à faire
    if (!mounted) return;

    final bool alreadyInPip = PipService.instance.isInPipMode;
    final bool pipSupported = await PipService.instance.isSupported();

    if (!alreadyInPip && pipSupported && _isPlaying) {
      final bool ok = await PipService.instance.enterPip();
      // Si le natif refuse (permission désactivée, etc.), on quitte
      // quand même — sinon le bouton back ferait rien.
      if (!ok && mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    // Pas de PiP possible → pop normal du player.
    if (mounted) Navigator.of(context).pop();
  }

  /// PageView vertical "TikTok-style" — swipe haut/bas pour zapper.
  /// Chaque page est la zone player ; la page active rend la vidéo
  /// en cours de lecture, les voisines un poster de la chaîne (logo
  /// + nom) pour la transition fluide pendant le swipe.
  Widget _buildTikTokPageView() {
    final List<Channel> list = widget.zapPlaylist!;
    return PageView.builder(
      scrollDirection: Axis.vertical,
      controller: _zapPageController,
      // Physics élastique — donne le rebond doux qu'on attend d'un
      // feed TikTok / Reels au lieu du clamp brutal par défaut.
      physics: const BouncingScrollPhysics(),
      onPageChanged: _onZapPageChanged,
      itemCount: list.length,
      itemBuilder: (BuildContext context, int i) {
        final bool isCurrent = list[i].id == _currentChannel.id;
        return GestureDetector(
          onTap: _toggleOverlay,
          child: isCurrent
              ? _buildPlayerSurface()
              : _ZapPreviewPage(channel: list[i]),
        );
      },
    );
  }

  /// Surface de lecture : la vidéo + spinner + stats + overlays.
  /// Extraite pour pouvoir être ré-utilisée à l'identique dans le
  /// PageView et dans le mode mono-page (TV / playlist absente).
  Widget _buildPlayerSurface() {
    return GestureDetector(
      onTap: _toggleOverlay,
      child: ListenableBuilder(
        listenable: PlayerSettings.instance,
        builder: (BuildContext context, _) {
          final AspectRatioMode mode = PlayerSettings.instance.aspectMode;
          return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // ----- 1. La vidéo (avec aspect ratio forcé si demandé) -----
                Center(
                  child: _forcedAspect(mode) == null
                      ? Video(
                          controller: _videoController,
                          controls: (VideoState _) => const SizedBox.shrink(),
                          fit: _fitFromMode(mode),
                        )
                      : AspectRatio(
                          aspectRatio: _forcedAspect(mode)!,
                          child: Video(
                            controller: _videoController,
                            controls: (VideoState _) => const SizedBox.shrink(),
                            fit: _fitFromMode(mode),
                          ),
                        ),
                ),

                // ----- 2. Spinner pendant le buffering -----
                if (_isBuffering && !_hasError)
                  const Center(
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),

                // ----- 3. Stats overlay (toggle dans les réglages) -----
                if (PlayerSettings.instance.showStats && !_hasError)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    left: 12,
                    child: PlayerStatsOverlay(player: _player),
                  ),

                // ----- 3bis. Logo flottant de la chaîne (style France 2) -----
                //  En bas-droite, semi-transparent, masqué quand l'overlay
                //  contrôles est visible (pour ne pas cacher les boutons).
                //  Charge depuis le `logoUrl` du Channel ; fallback : pas
                //  de logo si l'URL est nulle ou casse au load.
                if (!_hasError &&
                    !_overlayVisible &&
                    _currentChannel.logoUrl != null &&
                    _currentChannel.logoUrl!.isNotEmpty)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.75,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Image.network(
                            _currentChannel.logoUrl!,
                            height: 36,
                            width: 60,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                            loadingBuilder: (BuildContext c, Widget child,
                                ImageChunkEvent? p) =>
                                p == null ? child : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),

                // ----- 4. Overlay erreur -----
                if (_hasError) _buildErrorOverlay(),

                // ----- 5. Overlay contrôles -----
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _overlayVisible ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_overlayVisible,
                    child: _buildOverlay(),
                  ),
                ),
              ],
            );
          },
        ),
      );
  }

  // ----- Composants -----

  Widget _buildOverlay() {
    final Channel ch = _currentChannel;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.75),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.9),
          ],
          stops: const <double>[0, 0.22, 0.55, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            // ----- Haut : retour + titre + favori -----
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          ch.cleanName,
                          style: AppTextStyles.headlineMedium
                              .copyWith(fontSize: 18),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        // FittedBox(scaleDown) protège la Row
                        // badge + catégorie contre les écrans étroits.
                        // Si le contenu dépasse la largeur dispo, tout
                        // est réduit en bloc au lieu de déborder à droite
                        // (le 'RIGHT OVERFLOWED BY 36 PIXELS' qu'on
                        // voyait en debug build). Aligné à gauche pour
                        // garder le visuel naturel.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (ch.isLive) ...<Widget>[
                                const LiveBadge(),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                ch.category,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.accentCyan,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _FavoriteToggle(channelId: ch.id),
                  // Bouton "Mini-fenêtre" (PiP) — déclenche manuellement
                  // le passage en mini-fenêtre flottante style YouTube
                  // Premium. Sur Android 8+, c'est le même mécanisme
                  // qu'un appui HOME pendant la lecture, mais l'user a
                  // un contrôle explicite sans devoir quitter l'app.
                  // Sur les devices qui ne supportent pas PiP, l'appel
                  // retourne false → on affiche un toast d'erreur.
                  IconButton(
                    icon: const Icon(
                      Icons.picture_in_picture_alt_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Mini-fenêtre',
                    onPressed: _enterPipManually,
                  ),
                  // NB : le bouton "Cast par QR Code" a été retiré du
                  // header à la demande de l'user — il prenait de la
                  // place et le cast officiel via clé Google Cast sera
                  // privilégié à l'avenir (achat de clé prévu). La
                  // méthode _openQrCast et le sheet sont conservés
                  // dans le code pour réactivation rapide si besoin.
                  ListenableBuilder(
                    listenable: CastManager.instance,
                    builder: (BuildContext context, _) {
                      final bool casting =
                          CastManager.instance.isCasting;
                      return IconButton(
                        icon: Icon(
                          casting
                              ? Icons.cast_connected_rounded
                              : Icons.cast_rounded,
                          color: casting
                              ? AppColors.accent
                              : Colors.white,
                        ),
                        tooltip: casting
                            ? 'Casting en cours — tap pour gérer'
                            : 'Envoyer vers une TV',
                        onPressed: _openCastPicker,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Recharger le flux',
                    onPressed: _retry,
                  ),
                ],
              ),
            ),

            // ----- Centre : Play/Pause minimaliste -----
            //
            //  Sur PHONE : juste le play/pause discret au milieu, sans
            //  fond ni bordure (immersif). Zap channel = swipe vertical
            //  sur la vidéo (voir GestureDetector.onVerticalDragEnd).
            //
            //  Sur TV : on remet les boutons ⏮ / ⏭ autour du play/pause
            //  car il n'y a pas de geste swipe avec une télécommande.
            //  Les 3 boutons sont focusables au D-pad et le user navigue
            //  gauche/droite, OK pour zapper ou play/pause.
            Expanded(
              child: Center(
                child: _isTvUi
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (_canZap)
                            _TvDpadButton(
                              icon: Icons.skip_previous_rounded,
                              onTap: _zapPrev,
                              autofocus: false,
                            ),
                          if (_canZap) const SizedBox(width: 32),
                          _TvDpadButton(
                            icon: _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onTap: _togglePlayPause,
                            autofocus: true,
                            large: true,
                          ),
                          if (_canZap) const SizedBox(width: 32),
                          if (_canZap)
                            _TvDpadButton(
                              icon: Icons.skip_next_rounded,
                              onTap: _zapNext,
                              autofocus: false,
                            ),
                        ],
                      )
                    : _PlayPauseButton(
                        isPlaying: _isPlaying,
                        onTap: _togglePlayPause,
                      ),
              ),
            ),

            // ----- Bas : barre de contrôles -----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _ControlButton(
                    icon: Icons.subtitles_outlined,
                    label: 'Pistes',
                    onTap: _openTracks,
                  ),
                  _ControlButton(
                    icon: Icons.speed_rounded,
                    label: '${_player.state.rate.toStringAsFixed(_player.state.rate == _player.state.rate.toInt() ? 0 : 2)}x',
                    onTap: _openSettings,
                  ),
                  _ControlButton(
                    icon: _aspectIcon(PlayerSettings.instance.aspectMode),
                    label: PlayerSettings.instance.aspectMode.label,
                    onTap: _openSettings,
                  ),
                  _ControlButton(
                    icon: _isRecording
                        ? Icons.stop_circle_rounded
                        : Icons.fiber_manual_record_rounded,
                    label: _isRecording ? 'STOP' : 'REC',
                    iconColor: _isRecording ? AppColors.live : null,
                    onTap: _toggleRecording,
                  ),
                  // Bouton PiP désactivé temporairement (incompat JVM
                  // target du plugin `floating: ^4` sur le SDK Android
                  // CI). À rétablir quand on a un plugin compatible.
                  _ControlButton(
                    icon: Icons.tune_rounded,
                    label: 'Réglages',
                    onTap: _openSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _aspectIcon(AspectRatioMode mode) {
    switch (mode) {
      case AspectRatioMode.fit:
        return Icons.fit_screen_outlined;
      case AspectRatioMode.fill:
        return Icons.aspect_ratio_rounded;
      case AspectRatioMode.stretch:
        return Icons.open_in_full_rounded;
      case AspectRatioMode.ratio169:
      case AspectRatioMode.ratio43:
      case AspectRatioMode.ratio219:
        return Icons.crop_landscape_rounded;
    }
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.78),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              color: AppColors.live,
              size: 56,
            ),
            const SizedBox(height: 14),
            Text(
              'Impossible de lire ce flux',
              style: AppTextStyles.headlineMedium,
            ),
            const SizedBox(height: 8),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  maxLines: 4,
                ),
              ),
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Retour'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _retry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentPink,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Pas de cercle, pas de bordure — juste l'icône blanche.
    // Apple TV / Netflix mobile : l'OSD reste discret, l'icône
    // a une légère ombre pour rester lisible sur les scènes claires.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 72,
            shadows: const <Shadow>[
              Shadow(color: Colors.black54, blurRadius: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: iconColor ?? Colors.white, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 10,
                color: iconColor ?? Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteToggle extends StatelessWidget {
  const _FavoriteToggle({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: FavoritesRepository.instance.favoritesStream,
      initialData: FavoritesRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<Set<String>> snap) {
        final bool isFav = (snap.data ?? <String>{}).contains(channelId);
        return IconButton(
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_outline,
            color: isFav ? AppColors.accentPink : Colors.white,
          ),
          tooltip: isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
          onPressed: () => FavoritesRepository.instance.toggle(channelId),
        );
      },
    );
  }
}

/// Bouton du player en mode TV (10-foot UI). Focusable au D-pad,
/// scale 1.08 + bordure ember au focus, autofocus optionnel sur le
/// play/pause central. La version `large: true` est utilisée pour
/// le play/pause au milieu, les autres pour ⏮ / ⏭.
class _TvDpadButton extends StatefulWidget {
  const _TvDpadButton({
    required this.icon,
    required this.onTap,
    this.autofocus = false,
    this.large = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;
  final bool large;

  @override
  State<_TvDpadButton> createState() => _TvDpadButtonState();
}

class _TvDpadButtonState extends State<_TvDpadButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final double size = widget.large ? 96 : 72;
    final double iconSize = widget.large ? 56 : 40;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (bool f) => setState(() => _focused = f),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _focused
                  ? AppColors.accent.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: _focused
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.25),
                width: _focused ? 2.5 : 1.5,
              ),
              boxShadow: _focused
                  ? <BoxShadow>[
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.45),
                        blurRadius: 24,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  _ZapPreviewPage — Page placeholder pendant le swipe TikTok
// ============================================================
//  Affichée pour chaque chaîne du PageView qui n'est PAS en cours
//  de lecture. Pendant le swipe, l'utilisateur voit ce poster
//  glisser depuis le haut/bas vers le centre. Au snap, le poster
//  est remplacé par le widget Video qui démarre la lecture.
//
//  Design : ultra-sobre, noir, avec le logo de la chaîne grand
//  centré et son nom — style "Reels coming up" / TikTok preview.
// ============================================================

class _ZapPreviewPage extends StatelessWidget {
  const _ZapPreviewPage({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final String? logoUrl = channel.logoUrl;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Halo subtil rouge ember pour signaler "à venir"
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: <Color>[
                    AppColors.accent.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Logo de la chaîne ou initiales
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: logoUrl != null && logoUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(22.5),
                          child: Image.network(
                            logoUrl,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              _initials(channel.cleanName),
                              style: AppTextStyles.displayLarge,
                            ),
                          ),
                        )
                      : Text(
                          _initials(channel.cleanName),
                          style: AppTextStyles.displayLarge,
                        ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    channel.cleanName,
                    style: AppTextStyles.headlineMedium,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final List<String> words = name.split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }
}
