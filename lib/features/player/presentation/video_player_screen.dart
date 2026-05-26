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
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/data/watch_history_repository.dart';
import '../../channels/domain/channel.dart';
import '../../onboarding/data/device_class_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../recordings/data/gallery_exporter.dart';
import '../../recordings/data/recording_repository.dart';
import '../../recordings/data/recording_service.dart';
import '../../recordings/domain/recording.dart';
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

  // Picture-in-Picture désactivé temporairement (le plugin `floating: ^4`
  // a un mismatch JVM target avec le SDK Android du CI, casse Gradle).
  // À rétablir avec un patch gradle ou un autre plugin compatible.

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
      // Demande à libmpv de copier le flux dans `path`
      final bool ok = await _setMpvProperty('stream-record', path);
      if (!ok) {
        _toast('Enregistrement non supporté sur ce flux');
        return;
      }
      final Recording rec =
          await RecordingRepository.instance.startRecording(
        channelId: _currentChannel.id,
        channelName: _currentChannel.cleanName,
        programTitle: widget.overrideTitle,
        filePath: path,
      );

      // Démarre le ForegroundService natif qui empêche Android de
      // tuer notre process quand l'utilisateur passe en arrière-plan
      // (lire un SMS, prendre un appel, etc.) pendant l'enregistrement.
      // Best effort : si le service refuse de démarrer (permission,
      // OS exotique), l'enregistrement continue quand même mais sans
      // la garantie anti-kill.
      await RecordingService.instance.start(
        title: widget.overrideTitle != null && widget.overrideTitle!.isNotEmpty
            ? '${_currentChannel.cleanName} – ${widget.overrideTitle}'
            : _currentChannel.cleanName,
      );

      if (mounted) {
        setState(() => _activeRecording = rec);
        _toast('Enregistrement démarré – continue même hors écran');
      }
    } catch (e) {
      _toast('Impossible de démarrer : $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _setMpvProperty('stream-record', '');
      final Recording? rec = _activeRecording;
      if (rec != null) {
        await RecordingRepository.instance.finishRecording(rec);
      }

      // Arrête le ForegroundService natif et retire la notification
      // persistante de la barre de statut. À faire APRÈS la finalisation
      // libmpv pour que l'écriture du fichier soit complète au moment
      // où Android peut éventuellement recycler le process.
      await RecordingService.instance.stop();

      if (mounted) {
        setState(() => _activeRecording = null);
        _toast('Enregistrement sauvegardé');
      }

      // Export vers la galerie photo du téléphone — sans bloquer
      // l'UX. Si le `.ts` est valide (libmpv a réussi à le finaliser),
      // MediaStore le copie sous Movies/7MOTION/<name>.mp4 et la
      // Galerie l'affiche dès le prochain scan.
      //
      // Best effort : si l'export foire (espace plein, permission
      // refusée, etc.), le fichier original reste accessible via
      // l'écran Enregistrements (storage privé app).
      if (rec != null) {
        final String displayName = rec.filePath
            .split('/')
            .last
            .replaceAll('.ts', '.mp4');
        final bool exported = await GalleryExporter.exportVideo(
          srcPath: rec.filePath,
          displayName: displayName,
        );
        if (mounted) {
          _toast(exported
              ? 'Sauvegardé dans Galerie › Movies › 7MOTION'
              : 'Sauvegardé localement (export galerie indisponible)');
        }
      }
    } catch (e) {
      _toast('Erreur arrêt enregistrement : $e');
    }
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
    // (PiP désactivé — voir note plus haut)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    setState(() => _overlayVisible = !_overlayVisible);
    if (_overlayVisible) _scheduleHideOverlay();
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: useTikTokSwipe
          ? _buildTikTokPageView()
          : _buildPlayerSurface(),
    );
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
                        Row(
                          children: <Widget>[
                            if (ch.isLive) ...<Widget>[
                              const LiveBadge(),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                ch.category,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.accentCyan,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _FavoriteToggle(channelId: ch.id),
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
