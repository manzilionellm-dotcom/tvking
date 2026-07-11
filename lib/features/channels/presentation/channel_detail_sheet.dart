// =========================================================
//  channel_detail_sheet.dart — Fiche détaillée d'une chaîne
// =========================================================
//  Bottom sheet semi-modal qui apparaît au LONG PRESS d'une
//  vignette. (Le tap court reste dédié à la lecture
//  instantanée, pour ne pas alourdir l'UX du zapping.)
//
//  Contenu :
//    - Grand logo
//    - Nom propre (cleanName)
//    - Genre / Pays / Qualité en chips
//    - Programme en cours (si EPG)
//    - Bouton "Lecture" géant
//    - Bouton favori
// =========================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/domain/epg_program.dart';
import '../../epg/presentation/channel_programs_screen.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../domain/channel.dart';
import 'widgets/channel_logo.dart';

Future<void> showChannelDetail(BuildContext context, Channel channel) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ChannelDetailSheet(channel: channel),
  );
}

class ChannelDetailSheet extends StatelessWidget {
  const ChannelDetailSheet({required this.channel, super.key});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.96),
            border: Border(
              top: BorderSide(color: AppColors.border),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Grabber
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ----- En-tête : logo + nom -----
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      ChannelLogo(
                        channel: channel,
                        size: ChannelLogoSize.large,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              channel.cleanName,
                              style: AppTextStyles.headlineLarge.copyWith(
                                fontSize: 22,
                                height: 1.1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            _MetaBadges(channel: channel),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // ----- Programme en cours + suivant (EPG) -----
                  FutureBuilder<List<EpgProgram?>>(
                    future: Future.wait(<Future<EpgProgram?>>[
                      EpgRepository.instance.currentProgram(channel.id),
                      EpgRepository.instance.nextProgram(channel.id),
                    ]),
                    builder: (BuildContext context,
                        AsyncSnapshot<List<EpgProgram?>> snap) {
                      final List<EpgProgram?> progs =
                          snap.data ?? <EpgProgram?>[null, null];
                      final EpgProgram? cur = progs[0];
                      final EpgProgram? next =
                          progs.length > 1 ? progs[1] : null;
                      if (cur == null && next == null) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _sectionLabel(context.l10n.detailProgram),
                          const SizedBox(height: 6),
                          if (cur != null)
                            _programTile(
                              icon: Icons.play_circle_filled_rounded,
                              title: cur.title,
                              subtitle:
                                  '${cur.timeRangeShort} · ${context.l10n.detailNowPlaying}',
                              accent: true,
                            ),
                          if (next != null) ...<Widget>[
                            const SizedBox(height: 6),
                            _programTile(
                              icon: Icons.schedule_rounded,
                              title: next.title,
                              subtitle:
                                  '${next.timeRangeShort} · ${context.l10n.detailUpNext}',
                              accent: false,
                            ),
                          ],
                          const SizedBox(height: 22),
                        ],
                      );
                    },
                  ),

                  // ----- Détails techniques -----
                  _sectionLabel(context.l10n.detailDetails),
                  const SizedBox(height: 6),
                  _detailRow(context.l10n.detailCategory, channel.prettyCategory),
                  if (channel.country != null)
                    _detailRow(
                      context.l10n.detailCountry,
                      '${channel.country!.flag} ${channel.country!.name}',
                    ),
                  _detailRow(context.l10n.detailQuality, channel.quality.badge),
                  _detailRow(
                    context.l10n.detailCatchup,
                    channel.catchupSupported
                        ? context.l10n.detailCatchupAvailable('${channel.catchupDays ?? '?'}')
                        : context.l10n.detailCatchupUnavailable,
                  ),

                  const SizedBox(height: 24),

                  // ----- Actions principales -----
                  Row(
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            playChannel(
                              context,
                              channel,
                              zapPlaylist:
                                  PlaylistRepository.instance.currentChannels,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 22),
                          label: Text(context.l10n.playerPlay),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: _FavoriteButton(channelId: channel.id),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ----- Voir tous les programmes (replay 24h) -----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ChannelProgramsScreen(channel: channel),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.border),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.event_note_rounded, size: 20),
                      label: Text(
                        context.l10n.detailProgramsAndReplay,
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

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.textSecondary,
        fontSize: 11,
      ),
    );
  }

  Widget _programTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent ? AppColors.accentSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent
              ? AppColors.accent.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            color: accent ? AppColors.accent : AppColors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaBadges extends StatelessWidget {
  const _MetaBadges({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        if (channel.isLive)
          _badge(
            text: context.l10n.badgeLive,
            color: AppColors.live,
            textColor: Colors.white,
          ),
        _badge(
          icon: channel.genre.icon,
          text: channel.genre.localizedLabel,
          color: AppColors.surface,
          textColor: AppColors.textSecondary,
        ),
        if (channel.country != null)
          _badge(
            text: '${channel.country!.flag} ${channel.country!.name}',
            color: AppColors.surface,
            textColor: AppColors.textSecondary,
          ),
        if (channel.quality != ChannelQuality.sd)
          _badge(
            text: channel.quality.badge,
            color: AppColors.surface,
            textColor: AppColors.accent,
            borderColor: AppColors.accent.withValues(alpha: 0.4),
          ),
      ],
    );
  }

  Widget _badge({
    required String text,
    required Color color,
    required Color textColor,
    IconData? icon,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: borderColor ?? AppColors.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: AppTextStyles.labelSmall.copyWith(
              color: textColor,
              fontSize: 10,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: FavoritesRepository.instance.favoritesStream,
      initialData: FavoritesRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<Set<String>> snap) {
        final bool isFav = (snap.data ?? <String>{}).contains(channelId);
        return OutlinedButton(
          onPressed: () => FavoritesRepository.instance.toggle(channelId),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                isFav ? AppColors.accent : AppColors.textPrimary,
            backgroundColor:
                isFav ? AppColors.accentSurface : Colors.transparent,
            side: BorderSide(
              color: isFav ? AppColors.accent : AppColors.border,
              width: 1.5,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Icon(
            isFav ? Icons.favorite : Icons.favorite_outline,
            size: 22,
          ),
        );
      },
    );
  }
}
