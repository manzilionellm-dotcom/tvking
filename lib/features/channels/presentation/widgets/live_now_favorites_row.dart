// =========================================================
//  live_now_favorites_row.dart — "Live maintenant sur tes favoris"
// =========================================================
//  Hook Model — combine deux mécanismes :
//
//    1. Favoris (Investment) : l'utilisateur a déjà investi
//       dans ces chaînes en les ajoutant.
//    2. Live EPG (Variable Reward + Anticipation) : chaque
//       seconde quelque chose de différent passe en direct,
//       donc à chaque ouverture l'utilisateur ne sait pas ce
//       qu'il va trouver.
//
//  Pour chaque chaîne favorite, on demande à EpgRepository le
//  programme en cours et on l'affiche en card avec :
//    - Logo chaîne
//    - Nom programme actuel ("Real Madrid - PSG", "JT 20H"...)
//    - Barre de progression % du programme déjà écoulé
//    - Tap → playChannel
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../epg/data/epg_repository.dart';
import '../../../epg/domain/epg_program.dart';
import '../../../player/presentation/play_channel.dart';
import '../../../playlists/data/favorites_repository.dart';
import '../../../playlists/data/playlist_repository.dart';
import '../../domain/channel.dart';
import 'channel_logo.dart';

class LiveNowFavoritesRow extends StatefulWidget {
  const LiveNowFavoritesRow({super.key});

  @override
  State<LiveNowFavoritesRow> createState() => _LiveNowFavoritesRowState();
}

class _LiveNowFavoritesRowState extends State<LiveNowFavoritesRow> {
  /// Liste des (chaîne, programme en cours). Recalculée quand les
  /// favoris changent, et toutes les 60 sec pour suivre les
  /// changements de programmes.
  List<_LiveSlot> _slots = <_LiveSlot>[];
  bool _loading = true;

  late final Stream<Set<String>> _favStream;

  @override
  void initState() {
    super.initState();
    _favStream = FavoritesRepository.instance.favoritesStream;
    _favStream.listen((Set<String> _) => _recompute());
    _recompute();
  }

  Future<void> _recompute() async {
    final Set<String> favIds = FavoritesRepository.instance.current;
    if (favIds.isEmpty) {
      if (mounted) {
        setState(() {
          _slots = <_LiveSlot>[];
          _loading = false;
        });
      }
      return;
    }

    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    final Map<String, Channel> byId = <String, Channel>{
      for (final Channel c in all) c.id: c,
    };
    final List<Channel> favorites = <Channel>[];
    for (final String id in favIds) {
      final Channel? c = byId[id];
      if (c != null) favorites.add(c);
    }
    // On limite à 12 favoris pour la rangée — au-delà c'est trop
    // de requêtes EPG simultanées et la rangée scrolle de toute façon.
    final List<Channel> picked = favorites.take(12).toList();

    final List<_LiveSlot> slots = <_LiveSlot>[];
    for (final Channel c in picked) {
      final EpgProgram? p =
          await EpgRepository.instance.currentProgram(c.id);
      slots.add(_LiveSlot(channel: c, program: p));
    }
    if (mounted) {
      setState(() {
        _slots = slots;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si pas de favoris, on ne montre rien — l'accueil reste propre.
    if (_loading) return const SizedBox.shrink();
    if (_slots.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.live,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.live.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'EN DIRECT SUR TES FAVORIS',
                  style: AppTextStyles.eyebrow.copyWith(
                    color: AppColors.live,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _slots.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int i) {
                final _LiveSlot slot = _slots[i];
                return _LiveCard(
                  slot: slot,
                  onTap: () => playChannel(
                    context,
                    slot.channel,
                    zapPlaylist:
                        PlaylistRepository.instance.currentChannels,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveSlot {
  const _LiveSlot({required this.channel, this.program});
  final Channel channel;
  final EpgProgram? program;

  /// Pourcentage du programme écoulé [0..1]. null si pas de programme.
  double? get progress {
    if (program == null) return null;
    final DateTime now = DateTime.now();
    final int total = program!.end
        .difference(program!.start)
        .inSeconds;
    if (total <= 0) return null;
    final int elapsed = now.difference(program!.start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.slot, required this.onTap});

  final _LiveSlot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: ChannelLogo(
                      channel: slot.channel,
                      size: ChannelLogoSize.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      slot.channel.cleanName,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  slot.program?.title ?? 'En direct',
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              if (slot.progress != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: slot.progress,
                    minHeight: 3,
                    backgroundColor:
                        AppColors.accent.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.live,
                    ),
                  ),
                )
              else
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
