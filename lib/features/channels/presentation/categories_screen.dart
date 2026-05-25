// =========================================================
//  categories_screen.dart — Liste de toutes les catégories
// =========================================================
//  Sur l'accueil on n'affiche qu'UNE catégorie phare (la
//  plus représentée). Cet écran liste TOUTES les catégories
//  trouvées dans la playlist, avec le nombre de chaînes par
//  catégorie, et un tap → ChannelsGridScreen filtré.
//
//  Tri : par nombre de chaînes décroissant (le + populaire
//  en premier — comportement Spotify/Netflix typique).
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../playlists/data/playlist_repository.dart';
import '../domain/channel.dart';
import 'channels_grid_screen.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Catégories'),
      ),
      body: StreamBuilder<List<Channel>>(
        stream: PlaylistRepository.instance.channelsStream,
        initialData: const <Channel>[],
        builder: (BuildContext context, AsyncSnapshot<List<Channel>> snap) {
          final List<Channel> channels = snap.data ?? <Channel>[];
          if (channels.isEmpty) {
            return Center(
              child: Text(
                'Aucune chaîne — ajoute d\'abord une playlist.',
                style: AppTextStyles.bodyMedium,
              ),
            );
          }

          // Regroupe par catégorie
          final Map<String, List<Channel>> byCat =
              <String, List<Channel>>{};
          for (final Channel c in channels) {
            byCat.putIfAbsent(c.category, () => <Channel>[]).add(c);
          }
          final List<MapEntry<String, List<Channel>>> entries = byCat.entries
              .toList()
            // Tri descendant par nombre de chaînes
            ..sort((MapEntry<String, List<Channel>> a,
                    MapEntry<String, List<Channel>> b) =>
                b.value.length.compareTo(a.value.length));

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            physics: const BouncingScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (BuildContext _, int __) =>
                const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final MapEntry<String, List<Channel>> entry = entries[index];
              return _CategoryTile(
                name: entry.key,
                count: entry.value.length,
                channels: entry.value,
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.name,
    required this.count,
    required this.channels,
  });

  final String name;
  final int count;
  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    // Petit dégradé déterministe basé sur le nom — chaque catégorie
    // a "sa" couleur stable.
    final int seed = name.hashCode.abs();
    final List<List<Color>> palette = const <List<Color>>[
      <Color>[Color(0xFFFF3366), Color(0xFF7B1FA2)],
      <Color>[Color(0xFF00D9FF), Color(0xFF0288D1)],
      <Color>[Color(0xFFFFD700), Color(0xFFFF6F00)],
      <Color>[Color(0xFF00E676), Color(0xFF00BFA5)],
      <Color>[Color(0xFFE040FB), Color(0xFF7C4DFF)],
      <Color>[Color(0xFFD32F2F), Color(0xFF212121)],
    ];
    final List<Color> gradient = palette[seed % palette.length];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ChannelsGridScreen(
                title: name,
                channels: channels,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.surface.withValues(alpha: 0.7),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: <Widget>[
              // Petit carré coloré dégradé
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count chaîne${count > 1 ? 's' : ''}',
                      style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
