// =========================================================
//  favorites_screen.dart — Liste des chaînes favorites
// =========================================================
//  Combine 2 streams (chaînes + IDs favoris) avec StreamBuilder
//  imbriqué et affiche une grille des chaînes mises en favori.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/presentation/cast_button.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../domain/channel.dart';
import 'widgets/channel_card.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Favoris'),
        actions: const <Widget>[
          CastButton(),
          SizedBox(width: 6),
        ],
      ),
      body: StreamBuilder<Set<String>>(
        stream: FavoritesRepository.instance.favoritesStream,
        initialData: FavoritesRepository.instance.current,
        builder: (BuildContext context, AsyncSnapshot<Set<String>> favSnap) {
          final Set<String> favIds = favSnap.data ?? <String>{};
          return StreamBuilder<List<Channel>>(
            stream: PlaylistRepository.instance.channelsStream,
            initialData: PlaylistRepository.instance.currentChannels,
            builder:
                (BuildContext context, AsyncSnapshot<List<Channel>> chanSnap) {
              final List<Channel> all = chanSnap.data ?? <Channel>[];
              final List<Channel> favs =
                  all.where((Channel c) => favIds.contains(c.id)).toList();

              if (favs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.favorite_outline,
                        size: 56,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Aucun favori pour l\'instant',
                        style: AppTextStyles.bodyLarge,
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Appuie sur ♥ dans le menu d\'une chaîne pour la garder ici.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return LayoutBuilder(
                builder: (BuildContext context, BoxConstraints cons) {
                  final double w = cons.maxWidth;
                  final int cols = w >= 1000 ? 4 : w >= 700 ? 3 : 2;
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 16 / 11,
                    ),
                    itemCount: favs.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Channel ch = favs[index];
                      return ChannelCard(
                        channel: ch,
                        onTap: () => _onTap(context, ch, favs),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _onTap(BuildContext context, Channel channel, List<Channel> favs) {
    playChannel(context, channel, zapPlaylist: favs);
  }
}
