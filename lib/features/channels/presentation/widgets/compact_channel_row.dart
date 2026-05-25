// =========================================================
//  compact_channel_row.dart — Ligne dense pour 20 000 chaînes
// =========================================================
//  Conçu pour scroller une catégorie entière (style TiviMate
//  list view). Hauteur fixe (64px) → ListView.builder avec
//  itemExtent ultra rapide même sur très grosse playlist.
//
//  Layout (de gauche à droite) :
//    [logo 48x48] | [nom + métadonnées] | [badge qualité] | [♥]
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../epg/data/epg_repository.dart';
import '../../../epg/domain/epg_program.dart';
import '../../../playlists/data/favorites_repository.dart';
import '../../domain/channel.dart';
import 'channel_logo.dart';

class CompactChannelRow extends StatefulWidget {
  const CompactChannelRow({
    required this.channel,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Hauteur exposée pour `itemExtent` du ListView.builder.
  static const double height = 72;

  @override
  State<CompactChannelRow> createState() => _CompactChannelRowState();
}

class _CompactChannelRowState extends State<CompactChannelRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final Channel ch = widget.channel;
    return Focus(
      onFocusChange: (bool f) => setState(() => _focused = f),
      child: MouseRegion(
        onEnter: (_) => setState(() => _focused = true),
        onExit: (_) => setState(() => _focused = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: CompactChannelRow.height,
              decoration: BoxDecoration(
                color: _focused
                    ? AppColors.accentSurface
                    : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color: _focused ? AppColors.accent : Colors.transparent,
                    width: 3,
                  ),
                  bottom: BorderSide(
                    color: AppColors.border,
                    width: 0.5,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              child: Row(
                children: <Widget>[
                  // ----- Logo (avec fallback) -----
                  ChannelLogo(
                    channel: ch,
                    size: ChannelLogoSize.compact,
                  ),
                  const SizedBox(width: 12),

                  // ----- Texte -----
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            if (ch.isLive) ...<Widget>[
                              const _MiniLiveDot(),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                ch.cleanName,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        FutureBuilder<EpgProgram?>(
                          future:
                              EpgRepository.instance.currentProgram(ch.id),
                          builder: (BuildContext context,
                              AsyncSnapshot<EpgProgram?> snap) {
                            // Si on a un programme EPG → on l'affiche
                            // avec icône calendrier ; sinon catégorie M3U.
                            final EpgProgram? p = snap.data;
                            if (p != null) {
                              return Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.play_circle_outline_rounded,
                                    size: 11,
                                    color: AppColors.accent,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      p.title,
                                      style: AppTextStyles.bodyMedium
                                          .copyWith(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: <Widget>[
                                Icon(
                                  ch.genre.icon,
                                  size: 11,
                                  color: AppColors.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    ch.prettyCategory,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (ch.country != null) ...<Widget>[
                                  const SizedBox(width: 6),
                                  Text(
                                    ch.country!.flag,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // ----- Badge qualité -----
                  if (ch.quality != ChannelQuality.sd)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChannelQualityBadge(quality: ch.quality),
                    ),

                  // ----- Favori -----
                  _MiniFavorite(channelId: ch.id),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Petit point rouge pulsant pour signaler "LIVE" en mode compact.
class _MiniLiveDot extends StatefulWidget {
  const _MiniLiveDot();

  @override
  State<_MiniLiveDot> createState() => _MiniLiveDotState();
}

class _MiniLiveDotState extends State<_MiniLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.live.withValues(
              alpha: 0.55 + (_ctrl.value * 0.45),
            ),
          ),
        );
      },
    );
  }
}

class _MiniFavorite extends StatelessWidget {
  const _MiniFavorite({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: FavoritesRepository.instance.favoritesStream,
      initialData: FavoritesRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<Set<String>> snap) {
        final bool isFav = (snap.data ?? <String>{}).contains(channelId);
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_outline,
            color: isFav ? AppColors.accent : AppColors.textMuted,
            size: 18,
          ),
          onPressed: () => FavoritesRepository.instance.toggle(channelId),
        );
      },
    );
  }
}
