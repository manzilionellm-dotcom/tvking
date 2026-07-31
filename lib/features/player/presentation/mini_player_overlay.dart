// =========================================================
//  mini_player_overlay.dart — Fenêtre de lecture réduite
// =========================================================
//  Porté de TV King : petite fenêtre flottante en bas à droite,
//  au-dessus de TOUTES les routes (montée dans MaterialApp.builder,
//  cf. main.dart). Zéro coût quand rien ne joue (SizedBox.shrink).
//
//  Contrôles — tous DANS la fenêtre, comme l'original :
//    coin haut-droit :  Agrandir · Fermer
//    rangée basse    :  Écouteurs (audio seul) · Lecture/Pause ·
//                       Chaîne suivante (si playlist de zap)
//  Sous la vidéo : titre + barre de progression (VOD uniquement —
//  masquée en live, durée nulle).
// =========================================================

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/app/root_navigator.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/domain/channel.dart';
import '../data/mini_player_service.dart';
import 'play_channel.dart';

class MiniPlayerOverlay extends StatelessWidget {
  const MiniPlayerOverlay({super.key});

  /// « Agrandir » : ferme le mini puis rouvre le plein écran par le
  /// chemin normal (playChannel → cast/vérification/lecteur), via le
  /// Navigator racine (l'overlay vit au-dessus du Navigator).
  Future<void> _expand() async {
    final MiniPlayerService svc = MiniPlayerService.instance;
    final Channel? channel = svc.channel;
    if (channel == null) return;
    final List<Channel>? zap = svc.zapPlaylist;
    final String? overrideUrl = svc.overrideUrl;
    final String? overrideTitle = svc.overrideTitle;
    await svc.close();
    final BuildContext? ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await playChannel(
      ctx,
      channel,
      zapPlaylist: zap,
      overrideUrl: overrideUrl,
      overrideTitle: overrideTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MiniPlayerService.instance,
      builder: (BuildContext context, _) {
        final MiniPlayerService svc = MiniPlayerService.instance;
        final Player? player = svc.player;
        final VideoController? controller = svc.controller;
        if (player == null || controller == null) {
          return const SizedBox.shrink();
        }

        // Material : l'overlay vit hors de tout Scaffold.
        return Align(
          alignment: Alignment.bottomRight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 224,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // ----- Surface vidéo (ou panneau audio seul) -----
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            if (svc.audioOnly)
                              _AudioOnlyPanel()
                            else
                              Video(
                                controller: controller,
                                controls: (VideoState _) =>
                                    const SizedBox.shrink(),
                              ),
                            // Coin haut-droit : Agrandir · Fermer.
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Row(
                                children: <Widget>[
                                  _MiniButton(
                                    icon: Icons.open_in_full_rounded,
                                    tooltip: context.l10n.miniExpand,
                                    onTap: _expand,
                                  ),
                                  const SizedBox(width: 4),
                                  _MiniButton(
                                    icon: Icons.close_rounded,
                                    tooltip: context.l10n.miniClose,
                                    onTap: svc.close,
                                  ),
                                ],
                              ),
                            ),
                            // Rangée basse : Écouteurs · Lecture/Pause ·
                            // Suivant (si playlist de zap).
                            Positioned(
                              bottom: 4,
                              left: 4,
                              right: 4,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  _MiniButton(
                                    icon: svc.audioOnly
                                        ? Icons.ondemand_video_rounded
                                        : Icons.headphones_rounded,
                                    tooltip: svc.audioOnly
                                        ? context.l10n.playerVideo
                                        : context.l10n.playerAudioOnly,
                                    active: svc.audioOnly,
                                    onTap: svc.toggleAudioOnly,
                                  ),
                                  StreamBuilder<bool>(
                                    stream: player.stream.playing,
                                    initialData: player.state.playing,
                                    builder: (BuildContext context,
                                        AsyncSnapshot<bool> snap) {
                                      final bool playing =
                                          snap.data ?? false;
                                      return _MiniButton(
                                        icon: playing
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        tooltip: playing
                                            ? context.l10n.playerPause
                                            : context.l10n.playerPlay,
                                        onTap: svc.togglePlayPause,
                                      );
                                    },
                                  ),
                                  if (svc.nextChannel != null)
                                    _MiniButton(
                                      icon: Icons.skip_next_rounded,
                                      tooltip: context.l10n.miniNext,
                                      onTap: svc.playNext,
                                    )
                                  else
                                    const SizedBox(width: 30),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ----- Titre + progression (VOD) -----
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              svc.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            StreamBuilder<Duration>(
                              stream: player.stream.position,
                              initialData: player.state.position,
                              builder: (BuildContext context,
                                  AsyncSnapshot<Duration> snap) {
                                final Duration dur = player.state.duration;
                                // Live : durée nulle → pas de barre.
                                if (dur <= Duration.zero) {
                                  return const SizedBox.shrink();
                                }
                                final double ratio =
                                    ((snap.data ?? Duration.zero)
                                                .inMilliseconds /
                                            dur.inMilliseconds)
                                        .clamp(0.0, 1.0);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: 3,
                                      backgroundColor: Colors.white
                                          .withValues(alpha: 0.15),
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        AppColors.accent,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
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
    );
  }
}

/// Panneau « Audio seulement » — le son continue, l'image est rangée.
class _AudioOnlyPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceHigh,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.headphones_rounded, color: AppColors.accent, size: 28),
          const SizedBox(height: 6),
          Text(
            context.l10n.miniAudioOnlyCaption.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 10,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Petit bouton rond translucide — même langage visuel que l'original
/// (cercle noir 45 %, icône blanche), taille pouce-compatible.
class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? AppColors.accent
                : Colors.black.withValues(alpha: 0.45),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? AppColors.background : Colors.white,
          ),
        ),
      ),
    );
  }
}
