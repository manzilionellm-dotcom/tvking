// =========================================================
//  home_screen.dart — Écran d'accueil "TV King"
// =========================================================
//  Phase 1.1+1.2 — branche le `PlaylistRepository` (chaînes
//  réelles parsées en M3U/Xtream) et tous les écrans
//  satellites : Catégories, Recherche, Favoris, Réglages,
//  Voir tout.
//
//  Logique d'affichage :
//    - Liste vide → EmptyStateView (CTA ajouter playlist)
//    - Liste pleine → Hero + Chips + plusieurs ChannelRow
//
//  Bottom nav 5 onglets (Accueil / TV Guide / Films /
//  Recherche / Profil). Pour l'instant 3 sont fonctionnels
//  (Accueil + Recherche + Profil), les 2 autres affichent un
//  message "Phase à venir".
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/presentation/add_playlist_screen.dart';
import '../../playlists/presentation/playlists_screen.dart';
import '../domain/channel.dart';
import 'categories_screen.dart';
import 'channels_grid_screen.dart';
import 'favorites_screen.dart';
import 'search_screen.dart';
import 'widgets/channel_row.dart';
import 'widgets/empty_state.dart';
import 'widgets/floating_bottom_nav.dart';
import 'widgets/hero_section.dart';
import 'widgets/quick_chips_row.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentNavIndex = 0;

  // ----- Navigation helpers -----

  void _onChannelTap(Channel channel) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 90),
        backgroundColor: AppColors.surfaceHigh,
        duration: const Duration(seconds: 2),
        content: Text(
          'Lecture de "${channel.name}" — lecteur à brancher (Phase 1.3)',
          style: AppTextStyles.bodyLarge,
        ),
      ),
    );
  }

  Future<void> _openAddPlaylist() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const AddPlaylistScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openCategories() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CategoriesScreen()),
    );
  }

  Future<void> _openFavorites() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()),
    );
  }

  Future<void> _openSearch() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
    );
  }

  Future<void> _openSettings() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const PlaylistsScreen()),
    );
  }

  Future<void> _openSeeAll(String title, List<Channel> channels) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChannelsGridScreen(
          title: title,
          channels: channels,
        ),
      ),
    );
  }

  void _showComingSoon(String featureName) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 90),
        backgroundColor: AppColors.surfaceHigh,
        duration: const Duration(seconds: 2),
        content: Text(
          '$featureName — bientôt disponible',
          style: AppTextStyles.bodyLarge,
        ),
      ),
    );
  }

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: <Widget>[
          const _BackgroundLayer(),
          SafeArea(
            bottom: false,
            child: StreamBuilder<List<Channel>>(
              stream: PlaylistRepository.instance.channelsStream,
              initialData: const <Channel>[],
              builder: (BuildContext context,
                  AsyncSnapshot<List<Channel>> snapshot) {
                final List<Channel> channels = snapshot.data ?? <Channel>[];
                if (channels.isEmpty) {
                  return EmptyStateView(onAddPlaylist: _openAddPlaylist);
                }
                return _buildContent(channels);
              },
            ),
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

  void _onNavTap(int index) {
    setState(() => _currentNavIndex = index);
    switch (index) {
      case 0:
        // Déjà sur Accueil, rien à faire
        break;
      case 1:
        // TV Guide → Phase 2
        _showComingSoon('TV Guide (Phase 2)');
        _resetNavToHome();
        break;
      case 2:
        // Films → Phase Xtream VOD
        _showComingSoon('Films (Phase Xtream VOD)');
        _resetNavToHome();
        break;
      case 3:
        _openSearch().then((_) => _resetNavToHome());
        break;
      case 4:
        _openSettings().then((_) => _resetNavToHome());
        break;
    }
  }

  void _resetNavToHome() {
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _currentNavIndex = 0);
    });
  }

  /// Contenu principal quand on a au moins une chaîne.
  Widget _buildContent(List<Channel> channels) {
    // Sélection du Hero — première chaîne live
    final Channel hero = channels.firstWhere(
      (Channel c) => c.isLive,
      orElse: () => channels.first,
    );

    // Sections — pour vous = 15 premières (hors hero)
    final List<Channel> forYou =
        channels.where((Channel c) => c.id != hero.id).take(20).toList();
    final List<Channel> liveNow =
        channels.where((Channel c) => c.isLive).take(30).toList();
    final List<Channel> discoveries = channels.reversed.take(30).toList();

    // Catégorie phare (la + représentée)
    final String topCategory = _findTopCategory(channels);
    final List<Channel> topCategoryChannels = channels
        .where((Channel c) => c.category == topCategory)
        .take(30)
        .toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 70),

          // ---- HERO ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: HeroSection(
              channel: hero,
              onWatch: () => _onChannelTap(hero),
              onInfo: () => _showComingSoon('Fiche détaillée'),
            ),
          ),
          const SizedBox(height: 20),

          // ---- Quick chips → vrais écrans ----
          QuickChipsRow(
            onCategories: _openCategories,
            onFavorites: _openFavorites,
            onSearch: _openSearch,
            onSettings: _openSettings,
          ),
          const SizedBox(height: 24),

          // ---- Pour vous ----
          ChannelRow(
            title: 'Pour vous',
            channels: forYou,
            onChannelTap: _onChannelTap,
            onSeeAll: () => _openSeeAll('Pour vous', channels),
          ),
          const SizedBox(height: 24),

          // ---- En direct ----
          ChannelRow(
            title: 'En direct maintenant',
            channels: liveNow,
            onChannelTap: _onChannelTap,
            onSeeAll: () => _openSeeAll(
              'En direct maintenant',
              channels.where((Channel c) => c.isLive).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // ---- Catégorie phare ----
          if (topCategoryChannels.isNotEmpty)
            ChannelRow(
              title: topCategory,
              channels: topCategoryChannels,
              onChannelTap: _onChannelTap,
              onSeeAll: () => _openSeeAll(
                topCategory,
                channels
                    .where((Channel c) => c.category == topCategory)
                    .toList(),
              ),
            ),
          if (topCategoryChannels.isNotEmpty) const SizedBox(height: 24),

          // ---- Découvertes ----
          ChannelRow(
            title: 'Découvertes',
            channels: discoveries,
            onChannelTap: _onChannelTap,
            onSeeAll: () =>
                _openSeeAll('Découvertes', channels.reversed.toList()),
          ),
        ],
      ),
    );
  }

  String _findTopCategory(List<Channel> channels) {
    final Map<String, int> counts = <String, int>{};
    for (final Channel c in channels) {
      counts[c.category] = (counts[c.category] ?? 0) + 1;
    }
    String best = 'Autres';
    int bestCount = -1;
    counts.forEach((String name, int count) {
      if (count > bestCount) {
        best = name;
        bestCount = count;
      }
    });
    return best;
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        'TV KING',
        style: AppTextStyles.headlineLarge.copyWith(
          color: AppColors.gold,
          letterSpacing: 4,
          fontSize: 20,
        ),
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Ajouter une playlist',
          onPressed: _openAddPlaylist,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
        ),
        IconButton(
          tooltip: 'Recherche',
          onPressed: _openSearch,
          icon: const Icon(Icons.search, color: Colors.white),
        ),
        IconButton(
          tooltip: 'Mes playlists',
          onPressed: _openSettings,
          icon: const Icon(
            Icons.account_circle_outlined,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.backgroundGradient,
          ),
          child: SizedBox.expand(),
        ),
        Positioned(
          top: -120,
          left: -80,
          child: _GlowOrb(
            color: AppColors.accentPink.withValues(alpha: 0.22),
            size: 320,
          ),
        ),
        Positioned(
          bottom: -160,
          right: -100,
          child: _GlowOrb(
            color: AppColors.accentCyan.withValues(alpha: 0.18),
            size: 380,
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
