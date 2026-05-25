// =========================================================
//  home_screen.dart — Accueil "TV King" v1.4 (premium)
// =========================================================
//  Refonte Phase 1.4 — direction Apple TV / Netflix / Plex.
//
//  Architecture d'information :
//    1. Hero "VEDETTE" (1 chaîne mise en avant)
//    2. Continue Watching (chaînes récemment visionnées)
//    3. Favorites
//    4. Sports Live
//    5. Live Now (genre-mix populaire)
//    6. Films
//    7. Séries
//    8. Jeunesse
//    9. Info
//   10. Découvertes
//
//  Toutes les sections sont des `PremiumRow` (rangées
//  horizontales scrollables, ~150px de haut). Chaque "Voir
//  tout" ouvre `CategorySectionScreen` filtré.
//
//  Bottom nav : Accueil / Live TV / Recherche / Favoris / Profil.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/presentation/cast_mini_bar.dart';
import '../../epg/presentation/tv_guide_screen.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/presentation/add_playlist_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../data/recently_watched_repository.dart';
import '../domain/channel.dart';
import '../domain/channel_genre.dart';
import 'category_section_screen.dart';
import 'channel_detail_sheet.dart';
import 'favorites_screen.dart';
import 'search_screen.dart';
import 'widgets/empty_state.dart';
import 'widgets/floating_bottom_nav.dart';
import 'widgets/hero_section.dart';
import 'widgets/premium_row.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentNavIndex = 0;
  final FavoritesRepoSnapshot _favSnap = FavoritesRepoSnapshot();

  /// La playlist "complète" à passer au player pour activer le zapping
  /// ⏮ / ⏭. On utilise les chaînes du repo (cache mémoire instantané).
  List<Channel> _zapList() => PlaylistRepository.instance.currentChannels;

  void _onChannelTap(Channel ch) =>
      playChannel(context, ch, zapPlaylist: _zapList());
  void _onChannelLongPress(Channel ch) => showChannelDetail(context, ch);

  Future<void> _openAddPlaylist() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const AddPlaylistScreen(),
          fullscreenDialog: true,
        ),
      );

  Future<void> _openSearch() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
      );

  Future<void> _openSettings() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
      );

  Future<void> _openFavorites() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()),
      );

  Future<void> _openLiveTV() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const CategorySectionScreen(title: 'Live TV'),
        ),
      );

  Future<void> _openSection(String title, ChannelGenre genre) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            CategorySectionScreen(title: title, genreFilter: genre),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      backgroundColor: AppColors.background,
      appBar: _appBar(),
      body: Stack(
        children: <Widget>[
          const _BackgroundLayer(),
          SafeArea(
            bottom: false,
            child: StreamBuilder<List<Channel>>(
              stream: PlaylistRepository.instance.channelsStream,
              initialData: PlaylistRepository.instance.currentChannels,
              builder: (BuildContext context,
                  AsyncSnapshot<List<Channel>> snap) {
                final List<Channel> channels = snap.data ?? <Channel>[];
                if (channels.isEmpty) {
                  return EmptyStateView(onAddPlaylist: _openAddPlaylist);
                }
                return _buildContent(channels);
              },
            ),
          ),
          // Mini-bar de cast (visible seulement quand un cast est actif)
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: 0,
            right: 0,
            child: const CastMiniBar(),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FloatingBottomNav(
              currentIndex: _currentNavIndex,
              onTap: _onNavTap,
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.live_tv_rounded,
              color: Colors.black,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'TV KING',
            style: AppTextStyles.headlineLarge.copyWith(
              fontSize: 18,
              letterSpacing: 3,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Guide TV',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const TvGuideScreen(),
            ),
          ),
          icon: const Icon(Icons.event_note_rounded),
        ),
        IconButton(
          tooltip: 'Ajouter une playlist',
          onPressed: _openAddPlaylist,
          icon: const Icon(Icons.add_rounded),
        ),
        IconButton(
          tooltip: 'Recherche',
          onPressed: _openSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: 'Réglages',
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  // ============================================================
  //  Contenu principal — liste verticale de sections
  // ============================================================

  Widget _buildContent(List<Channel> all) {
    // Pré-calculs (rapides même à 20k channels — itère 1× la liste)
    final Map<String, Channel> byId = <String, Channel>{};
    final List<Channel> sports = <Channel>[];
    final List<Channel> movies = <Channel>[];
    final List<Channel> series = <Channel>[];
    final List<Channel> kids = <Channel>[];
    final List<Channel> news = <Channel>[];
    final List<Channel> music = <Channel>[];
    final List<Channel> docs = <Channel>[];
    final List<Channel> live = <Channel>[];

    for (final Channel c in all) {
      byId[c.id] = c;
      if (c.isLive) live.add(c);
      switch (c.genre) {
        case ChannelGenre.sports:
          sports.add(c);
        case ChannelGenre.movies:
          movies.add(c);
        case ChannelGenre.series:
          series.add(c);
        case ChannelGenre.kids:
          kids.add(c);
        case ChannelGenre.news:
          news.add(c);
        case ChannelGenre.music:
          music.add(c);
        case ChannelGenre.documentary:
          docs.add(c);
        case ChannelGenre.entertainment:
        case ChannelGenre.international:
        case ChannelGenre.adult:
        case ChannelGenre.other:
          break;
      }
    }

    // Hero : prend la 1ʳᵉ chaîne avec un logo (plus joli) sinon la 1ʳᵉ
    final Channel hero =
        all.firstWhere((Channel c) => c.hasLogo, orElse: () => all.first);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        const SliverPadding(padding: EdgeInsets.only(top: 64)),

        // ----- Hero -----
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          sliver: SliverToBoxAdapter(
            child: HeroSection(
              channel: hero,
              onWatch: () => _onChannelTap(hero),
              onInfo: () => _onChannelLongPress(hero),
            ),
          ),
        ),

        // ----- Continue Watching -----
        StreamBuilder<List<String>>(
          stream: RecentlyWatchedRepository.instance.stream,
          initialData: RecentlyWatchedRepository.instance.current,
          builder: (BuildContext context, AsyncSnapshot<List<String>> snap) {
            final List<Channel> recent = <Channel>[];
            for (final String id in snap.data ?? <String>[]) {
              final Channel? c = byId[id];
              if (c != null) recent.add(c);
            }
            if (recent.isEmpty) return const SliverToBoxAdapter();
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: PremiumRow(
                  title: 'Reprendre',
                  channels: recent,
                  onChannelTap: _onChannelTap,
                  onChannelLongPress: _onChannelLongPress,
                ),
              ),
            );
          },
        ),

        // ----- Favoris -----
        SliverToBoxAdapter(child: _favoritesRow(byId)),

        // ----- Sports Live -----
        if (sports.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumRow(
                title: 'Sports en direct',
                subtitle: '${sports.length} chaînes',
                channels: sports.take(20).toList(),
                onChannelTap: _onChannelTap,
                onChannelLongPress: _onChannelLongPress,
                onSeeAll: () => _openSection('Sports', ChannelGenre.sports),
              ),
            ),
          ),

        // ----- Live Now -----
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: PremiumRow(
              title: 'En direct maintenant',
              subtitle: '${live.length} chaînes',
              channels: live.take(20).toList(),
              onChannelTap: _onChannelTap,
              onChannelLongPress: _onChannelLongPress,
              onSeeAll: _openLiveTV,
            ),
          ),
        ),

        // ----- Films -----
        if (movies.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumRow(
                title: 'Films',
                subtitle: '${movies.length} chaînes',
                channels: movies.take(20).toList(),
                onChannelTap: _onChannelTap,
                onChannelLongPress: _onChannelLongPress,
                onSeeAll: () => _openSection('Films', ChannelGenre.movies),
              ),
            ),
          ),

        // ----- Séries -----
        if (series.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumRow(
                title: 'Séries',
                subtitle: '${series.length} chaînes',
                channels: series.take(20).toList(),
                onChannelTap: _onChannelTap,
                onChannelLongPress: _onChannelLongPress,
                onSeeAll: () => _openSection('Séries', ChannelGenre.series),
              ),
            ),
          ),

        // ----- Kids -----
        if (kids.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumRow(
                title: 'Jeunesse',
                subtitle: '${kids.length} chaînes',
                channels: kids.take(20).toList(),
                onChannelTap: _onChannelTap,
                onChannelLongPress: _onChannelLongPress,
                onSeeAll: () => _openSection('Jeunesse', ChannelGenre.kids),
              ),
            ),
          ),

        // ----- News -----
        if (news.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumRow(
                title: 'Info & Actualités',
                subtitle: '${news.length} chaînes',
                channels: news.take(20).toList(),
                onChannelTap: _onChannelTap,
                onChannelLongPress: _onChannelLongPress,
                onSeeAll: () => _openSection('Info', ChannelGenre.news),
              ),
            ),
          ),

        // ----- Music -----
        if (music.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumRow(
                title: 'Musique',
                subtitle: '${music.length} chaînes',
                channels: music.take(20).toList(),
                onChannelTap: _onChannelTap,
                onChannelLongPress: _onChannelLongPress,
                onSeeAll: () => _openSection('Musique', ChannelGenre.music),
              ),
            ),
          ),

        // ----- Documentaires -----
        if (docs.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumRow(
                title: 'Documentaires',
                subtitle: '${docs.length} chaînes',
                channels: docs.take(20).toList(),
                onChannelTap: _onChannelTap,
                onChannelLongPress: _onChannelLongPress,
                onSeeAll: () => _openSection(
                  'Documentaires',
                  ChannelGenre.documentary,
                ),
              ),
            ),
          ),

        // ----- Découvertes (catalogue complet, ordre inversé) -----
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: PremiumRow(
              title: 'À découvrir',
              channels: all.reversed.take(20).toList(),
              onChannelTap: _onChannelTap,
              onChannelLongPress: _onChannelLongPress,
              onSeeAll: _openLiveTV,
            ),
          ),
        ),

        // Espace pour la bottom nav flottante
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Widget _favoritesRow(Map<String, Channel> byId) {
    return _favSnap.buildFavorites(
      builder: (List<String> favIds) {
        final List<Channel> favs = <Channel>[];
        for (final String id in favIds) {
          final Channel? c = byId[id];
          if (c != null) favs.add(c);
        }
        if (favs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: PremiumRow(
            title: 'Favoris',
            subtitle: '${favs.length} chaînes',
            channels: favs.take(20).toList(),
            onChannelTap: _onChannelTap,
            onChannelLongPress: _onChannelLongPress,
            onSeeAll: _openFavorites,
          ),
        );
      },
    );
  }

  // ----- Bottom Nav -----

  void _onNavTap(int index) {
    setState(() => _currentNavIndex = index);
    switch (index) {
      case 0:
        break; // déjà sur Accueil
      case 1:
        _openLiveTV().then((_) => _resetNav());
      case 2:
        _openSearch().then((_) => _resetNav());
      case 3:
        _openFavorites().then((_) => _resetNav());
      case 4:
        _openSettings().then((_) => _resetNav());
    }
  }

  void _resetNav() {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _currentNavIndex = 0);
    });
  }
}

// ----- Helper pour lire les favoris en stream -----
class FavoritesRepoSnapshot {
  Widget buildFavorites({required Widget Function(List<String>) builder}) {
    return StreamBuilder<Set<String>>(
      stream: FavoritesRepository.instance.favoritesStream,
      initialData: FavoritesRepository.instance.current,
      builder:
          (BuildContext context, AsyncSnapshot<Set<String>> snap) {
        return builder((snap.data ?? <String>{}).toList());
      },
    );
  }
}

// ----- Fond global avec dégradé subtil -----
class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient,
      ),
      child: SizedBox.expand(),
    );
  }
}
