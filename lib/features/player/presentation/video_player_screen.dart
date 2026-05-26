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
import '../../playlists/data/favorites_repository.dart';
import '../../recordings/data/recording_repository.dart';
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

  /// ID de la session de visionnage en cours (table `watch_sessions`).
  /// Démarrée dans `initState`, fermée dans `dispose`. Sert au Hook
  /// Model : Continue Watching + affinity scoring.
  int _watchSessionId = 0;

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

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

  int get _zapIndex {
    if (widget.zapPlaylist == null) return -1;
    return widget.zapPlaylist!
        .indexWhere((Channel c) => c.id == _currentChannel.id);
  }

  void _zapTo(int newIndex) {
    if (widget.zapPlaylist == null) return;
    final List<Channel> list = widget.zapPlaylist!;
    if (list.isEmpty) return;
    final int wrapped = ((newIndex % list.length) + list.length) % list.length;
    final Channel next = list[wrapped];
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
      if (mounted) {
        setState(() => _activeRecording = rec);
        _toast('Enregistrement démarré');
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
      if (mounted) {
        setState(() => _activeRecording = null);
        _toast('Enregistrement sauvegardé');
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
    _player.dispose();
    WakelockPlus.disable();
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleOverlay,
        // Geste swipe vertical pour zapper — remplace les ⏮ / ⏭ qui
        // encombraient le centre de l'image. Geste premium type Netflix.
        // Vitesse > 300 px/s pour éviter les déclenchements accidentels
        // pendant un scroll de l'overlay.
        onVerticalDragEnd: _canZap
            ? (DragEndDetails d) {
                final double v = d.primaryVelocity ?? 0;
                if (v < -300) {
                  _zapNext();
                } else if (v > 300) {
                  _zapPrev();
                }
              }
            : null,
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

            // ----- Centre : Play/Pause minimaliste, pas de cercles -----
            //
            //  Avant : 3 cercles flottants (⏮ ⏯ ⏭) qui cassaient
            //  l'immersion + le ⏮/⏭ n'avait pas de sens sur LIVE.
            //  Maintenant : un seul play/pause discret, sans fond ni
            //  bordure. Le zap channel passe par le swipe vertical
            //  sur la vidéo (voir GestureDetector.onVerticalDragEnd).
            Expanded(
              child: Center(
                child: _PlayPauseButton(
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
