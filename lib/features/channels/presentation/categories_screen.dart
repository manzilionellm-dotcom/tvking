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

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../playlists/data/playlist_repository.dart';
import '../data/category_order_store.dart';
import '../domain/channel.dart';
import 'category_order_screen.dart';
import 'channels_grid_screen.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  Future<void> _openReorder(
      BuildContext context, List<String> currentOrder) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CategoryOrderScreen(categories: currentOrder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Charge l'ordre personnalisé (idempotent) ; le ListenableBuilder
    // ci-dessous redessine dès qu'il est prêt ou modifié.
    // ignore: discarded_futures
    CategoryOrderStore.instance.ensureLoaded();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.categoriesTitle),
      ),
      body: ListenableBuilder(
        listenable: CategoryOrderStore.instance,
        builder: (BuildContext context, Widget? _) {
          return StreamBuilder<List<Channel>>(
            stream: PlaylistRepository.instance.channelsStream,
            initialData: PlaylistRepository.instance.currentChannels,
            builder:
                (BuildContext context, AsyncSnapshot<List<Channel>> snap) {
              final List<Channel> channels = snap.data ?? <Channel>[];
              if (channels.isEmpty) {
                return Center(
                  child: Text(
                    context.l10n.categoriesEmpty,
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
              List<MapEntry<String, List<Channel>>> entries = byCat.entries
                  .toList()
                // Tri PAR DÉFAUT : nombre de chaînes décroissant.
                ..sort((MapEntry<String, List<Channel>> a,
                        MapEntry<String, List<Channel>> b) =>
                    b.value.length.compareTo(a.value.length));
              // ORDRE PERSONNALISÉ de l'utilisateur (glisser-déposer) appliqué
              // PAR-DESSUS : catégories classées d'abord, le reste ensuite.
              entries = CategoryOrderStore.instance.applyOrder(
                  entries, (MapEntry<String, List<Channel>> e) => e.key);

              return Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: TextButton.icon(
                        onPressed: () => _openReorder(
                          context,
                          entries
                              .map((MapEntry<String, List<Channel>> e) => e.key)
                              .toList(),
                        ),
                        icon: const Icon(Icons.swap_vert_rounded, size: 20),
                        label: Text(context.l10n.categoryOrderEdit),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      physics: const BouncingScrollPhysics(),
                      itemCount: entries.length,
                      separatorBuilder: (BuildContext _, int __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final MapEntry<String, List<Channel>> entry =
                            entries[index];
                        return _CategoryTile(
                          name: entry.key,
                          count: entry.value.length,
                          channels: entry.value,
                        );
                      },
                    ),
                  ),
                ],
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
    // Dégradé déterministe basé sur le nom — chaque catégorie a "sa"
    // dérivée Maison Noir stable. On reste dans la famille accentEmber /
    // surfaces sombres : pas de néons, pas d'arc-en-ciel.
    final int seed = name.hashCode.abs();
    final List<List<Color>> palette = const <List<Color>>[
      // accentEmber deep → canvas
      <Color>[Color(0xFF9C8359), Color(0xFF0E0B14)],
      // brass glow → elevated
      <Color>[Color(0xFFB8965E), Color(0xFF16121C)],
      // accentEmber → overcast
      <Color>[Color(0xFFD4B483), Color(0xFF221D2D)],
      // info ash → glass
      <Color>[Color(0xFF8FA8C4), Color(0xFF1C1826)],
      // status warning → canvas
      <Color>[Color(0xFFD4A574), Color(0xFF0E0B14)],
      // status success → elevated
      <Color>[Color(0xFF7FB890), Color(0xFF16121C)],
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
                      context.l10n.channelCount(count),
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
