// =========================================================
//  media_grid_view.dart — Grille FILMS / SÉRIES / PPV
// =========================================================
//  Affiche un ENSEMBLE de contenus d'un seul type (films, séries OU
//  événements PPV) sous forme de grille de cartes. Jamais de mélange :
//  l'appelant filtre déjà la liste par type (séparation stricte des
//  écosystèmes). Tri par popularité, chaînes mortes au fond (santé).
//  Virtualisé (GridView.builder) → fluide même avec des milliers de
//  contenus. Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../channels/domain/channel.dart';
import '../../../country_home/data/channel_curation.dart';
import '../../../country_home/data/channel_health_repository.dart';
import '../../../country_home/data/popularity_repository.dart';
import '../../../country_home/presentation/widgets/channel_logo.dart';
import '../../../player/presentation/play_channel.dart';

class MediaGridView extends StatelessWidget {
  const MediaGridView({
    super.key,
    required this.channels,
    required this.emptyLabel,
  });

  /// Contenus déjà filtrés à UN seul type (films, séries ou PPV).
  final List<Channel> channels;

  /// Message affiché si la liste est vide.
  final String emptyLabel;

  void _play(BuildContext context, Channel c, List<Channel> list) {
    PopularityRepository.instance.recordOpen(c.id);
    playChannel(context, c, zapPlaylist: list);
  }

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: AppTextStyles.maisonProgram.copyWith(
                fontSize: 15, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: ChannelHealthRepository.instance,
      builder: (BuildContext context, _) {
        final List<Channel> sorted =
            ChannelHealthRepository.instance.sortByHealth(
          PopularityRepository.instance
              .getPopularChannels(channels, top: channels.length),
        );
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
            childAspectRatio: 0.74,
          ),
          itemCount: sorted.length,
          itemBuilder: (BuildContext context, int i) {
            final Channel c = sorted[i];
            return _MediaCard(
              channel: c,
              onTap: () => _play(context, c, sorted),
            );
          },
        );
      },
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.channel, required this.onTap});
  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            // Taille concrète (jamais infinie → pas de crash cacheWidth).
            final double w = c.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ChannelLogo(channel: channel, size: w, radius: 14),
                const SizedBox(height: 6),
                Text(
                  cleanName(channel.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.maisonChannelName.copyWith(fontSize: 13),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
