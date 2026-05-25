// =========================================================
//  video_player_screen.dart — Lecteur vidéo plein écran
// =========================================================
//  Phase 1.3 — branche le moteur `media_kit` (libmpv) pour
//  lire les flux IPTV : HLS, MPEG-TS, MP4, audio multi-piste.
//
//  UX :
//    - Plein écran, statut bar masquée
//    - Tap → bascule l'overlay (titre + bouton retour + Play/Pause + Stop)
//    - L'overlay s'auto-masque après 4s d'inactivité
//    - Écran maintenu allumé via wakelock_plus
//    - Buffering visible (cercle pulsant)
//    - Erreur réseau affichée clairement
//
//  Orientation : forcée à `portrait & landscape` (l'utilisateur
//  décide). Sur Android TV / Fire TV → paysage par défaut.
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
import '../../channels/domain/channel.dart';
import '../../playlists/data/favorites_repository.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({required this.channel, super.key});

  final Channel channel;

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

  late final StreamSubscription<bool> _bufferingSub;
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<String> _errorSub;

  @override
  void initState() {
    super.initState();

    // Garde l'écran allumé pendant la lecture
    WakelockPlus.enable();

    // Statut bar : full immersive sticky (revient au touch)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _player = Player();
    _videoController = VideoController(_player);

    // Abonne aux flux d'événements du player
    _bufferingSub = _player.stream.buffering.listen((bool b) {
      if (mounted) setState(() => _isBuffering = b);
    });
    _playingSub = _player.stream.playing.listen((bool p) {
      if (mounted) setState(() => _isPlaying = p);
    });
    _errorSub = _player.stream.error.listen((String e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e;
        });
      }
    });

    // Lance la lecture
    _player.open(Media(widget.channel.streamUrl));

    // Programme le masquage de l'overlay après quelques secondes
    _scheduleHideOverlay();
  }

  @override
  void dispose() {
    _hideOverlayTimer?.cancel();
    _bufferingSub.cancel();
    _playingSub.cancel();
    _errorSub.cancel();
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
    _player.open(Media(widget.channel.streamUrl));
  }

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleOverlay,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // ----- 1. La vidéo -----
            Center(
              child: Video(
                controller: _videoController,
                controls: NoVideoControls, // on dessine notre propre overlay
                fit: BoxFit.contain,
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
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ),

            // ----- 3. Overlay erreur -----
            if (_hasError) _buildErrorOverlay(),

            // ----- 4. Overlay des contrôles -----
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _overlayVisible ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_overlayVisible,
                child: _buildOverlay(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----- Composants -----

  Widget _buildOverlay() {
    final Channel ch = widget.channel;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.75),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
          ],
          stops: const <double>[0, 0.25, 0.6, 1],
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
                          ch.name,
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

            // ----- Centre : bouton Play/Pause géant -----
            Expanded(
              child: Center(
                child: _PlayPauseButton(
                  isPlaying: _isPlaying,
                  onTap: _togglePlayPause,
                ),
              ),
            ),

            // ----- Bas : éventuelles infos / boutons supplémentaires -----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.accentCyan,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap = afficher/masquer les contrôles · '
                        'Play/Pause au centre · ⟳ pour recharger',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
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
  const _PlayPauseButton({
    required this.isPlaying,
    required this.onTap,
  });

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.15),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 44,
          ),
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
