// =========================================================
//  resume_banner.dart — Bannière "Reprendre où tu t'es arrêté"
// =========================================================
//  Visible en haut de l'accueil quand la dernière session de
//  visionnage date de < 60 minutes. Inspiré de la rangée
//  Continue Watching de Netflix qui génère ~70% des plays.
//
//  Comportement :
//    - Si dernière session < 60 min ET la chaîne est encore
//      dans la playlist → bannière avec gros bouton Reprendre
//    - Sinon → invisible (SizedBox.shrink)
//
//  Tap Reprendre = relance la chaîne via playChannel (qui
//  route vers le player local OU le cast si une TV est connectée).
//
//  Tap "Plus tard" = masque la bannière pour la session UI en
//  cours uniquement (ne supprime pas la session du DB).
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../../player/presentation/play_channel.dart';
import '../../../playlists/data/playlist_repository.dart';
import '../../data/watch_history_repository.dart';
import '../../domain/channel.dart';
import 'channel_logo.dart';

class ResumeBanner extends StatefulWidget {
  const ResumeBanner({super.key});

  /// Seuil au-delà duquel on n'affiche plus la bannière. Élargi à 72 h :
  /// « reprends là où tu t'es arrêté » doit survivre à une nuit (voire un
  /// week-end) — c'est le hook de retour n°1 (Continue Watching ≈ 70 % des
  /// plays Netflix). Une fenêtre de 60 min tuait le rappel dès le lendemain.
  static const Duration maxStaleness = Duration(hours: 72);

  @override
  State<ResumeBanner> createState() => _ResumeBannerState();
}

class _ResumeBannerState extends State<ResumeBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: WatchHistoryRepository.instance,
      builder: (BuildContext context, _) {
        final WatchSession? session =
            WatchHistoryRepository.instance.lastSession;
        if (session == null) return const SizedBox.shrink();

        final Duration sinceEnd = session.timeSinceEnd(DateTime.now());
        if (sinceEnd > ResumeBanner.maxStaleness) {
          return const SizedBox.shrink();
        }

        // Cherche la chaîne dans la playlist courante. Si elle a
        // disparu (playlist supprimée, refresh sans cette chaîne),
        // on ne montre pas la bannière.
        final List<Channel> all =
            PlaylistRepository.instance.currentChannels;
        final Channel? channel = all
            .where((Channel c) => c.id == session.channelId)
            .cast<Channel?>()
            .firstWhere((Channel? _) => true, orElse: () => null);
        if (channel == null) return const SizedBox.shrink();

        return _Banner(
          channel: channel,
          minutesAgo: sinceEnd.inMinutes,
          onResume: () => playChannel(
            context,
            channel,
            zapPlaylist: all,
          ),
          onDismiss: () => setState(() => _dismissed = true),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.channel,
    required this.minutesAgo,
    required this.onResume,
    required this.onDismiss,
  });

  final Channel channel;
  final int minutesAgo;
  final VoidCallback onResume;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final String agoText = minutesAgo <= 1
        ? context.l10n.resumeAgoNow
        : context.l10n.resumeAgoMinutes(minutesAgo);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      // Hero CTA "Reprendre" — c'est LE bouton qui génère ~70% des
      // plays sur Netflix d'après les benchmarks d'industrie. Sur TV
      // il mérite l'autofocus à l'apparition (géré par l'écran parent
      // si présent). On garde showGlow: true par défaut → le halo
      // ember 0.32 vient s'ajouter au halo emberGlowShadow déjà présent
      // sur le banner = signal très clair "appuie sur OK ici".
      child: TvFocusable(
        onTap: onResume,
        borderRadius: BorderRadius.circular(16),
        semanticsLabel: context.l10n.resumeBannerTitle(channel.cleanName),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.45),
              width: 1.3,
            ),
            boxShadow: AppColors.emberGlowShadow,
          ),
            child: Row(
              children: <Widget>[
                // Logo de la chaîne
                SizedBox(
                  width: 64,
                  height: 64,
                  child: ChannelLogo(
                    channel: channel,
                    size: ChannelLogoSize.medium,
                  ),
                ),
                const SizedBox(width: 14),
                // Infos
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        context.l10n.resumeEyebrow,
                        style: AppTextStyles.eyebrow,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        channel.cleanName,
                        style: AppTextStyles.headlineMedium.copyWith(
                          fontSize: 17,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.resumeWatchingAgo(agoText),
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                // Bouton Resume (CTA primaire ember)
                FilledButton.icon(
                  onPressed: onResume,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text(context.l10n.buttonResume),
                ),
                // Dismiss discret
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: AppColors.textMuted, size: 20),
                  tooltip: context.l10n.resumeBannerDismiss,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      );
  }
}
