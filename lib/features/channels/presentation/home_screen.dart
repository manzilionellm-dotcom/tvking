// =========================================================
//  home_screen.dart — Écran d'accueil "TV King"
// =========================================================
//  Phase 1.1+1.2 : on branche le `PlaylistRepository`.
//
//  Logique :
//    - On s'abonne au `channelsStream` du repository.
//    - Tant qu'on reçoit une liste vide → affichage `EmptyStateView`
//      avec bouton "Ajouter une playlist".
//    - Dès qu'on a des chaînes → on les répartit dans les
//      sections (Hero, Pour vous, En direct, Découvertes,
//      Par catégorie) au lieu des chaînes fictives.
//
//  Hero choisi : la PREMIÈRE chaîne live de la liste pour
//  l'instant. Plus tard (Phase 5), ce sera la dernière
//  regardée ou l'algo de recommandation.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/presentation/add_playlist_screen.dart';
import '../domain/channel.dart';
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

  // ----- Helpers UX -----

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

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: <Widget>[
          // Fond + halos communs à tous les états
          const _BackgroundLayer(),

          // Contenu réactif au repository
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

          // Bottom nav par-dessus tout
          Align(
            alignment: Alignment.bottomCenter,
            child: FloatingBottomNav(
              currentIndex: _currentNavIndex,
              onTap: (int i) {
                setState(() => _currentNavIndex = i);
                if (i != 0) {
                  _showComingSoon(_navLabel(i));
                  Future<void>.delayed(
                    const Duration(milliseconds: 1500),
                    () {
                      if (mounted) setState(() => _currentNavIndex = 0);
                    },
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  String _navLabel(int index) {
    switch (index) {
      case 1:
        return 'TV Guide (Phase 2)';
      case 2:
        return 'Films (futur Xtream VOD)';
      case 3:
        return 'Recherche (Phase 1.4)';
      case 4:
        return 'Profil (Phase 5)';
      default:
        return 'Accueil';
    }
  }

  /// Contenu standard quand on a au moins une chaîne.
  Widget _buildContent(List<Channel> channels) {
    final Channel hero = channels.firstWhere(
      (Channel c) => c.isLive,
      orElse: () => channels.first,
    );

    // Découpages simples pour les rangées (Phase 1, pas encore
    // d'algo de recommandation : on prend des slices variés).
    final List<Channel> forYou =
        channels.where((Channel c) => c.id != hero.id).take(15).toList();
    final List<Channel> liveNow = channels
        .where((Channel c) => c.isLive)
        .take(20)
        .toList();
    final List<Channel> discoveries = channels.reversed.take(20).toList();

    // Catégorie la plus représentée (pour avoir une 4ème rangée
    // dynamique et thématique)
    final String topCategory = _findTopCategory(channels);
    final List<Channel> topCategoryChannels = channels
        .where((Channel c) => c.category == topCategory)
        .take(20)
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
              onInfo: () => _showComingSoon('Fiche détaillée de la chaîne'),
            ),
          ),
          const SizedBox(height: 20),

          // ---- Quick chips ----
          QuickChipsRow(
            onCategories: () => _showComingSoon('Toutes les catégories'),
            onFavorites: () => _showComingSoon('Favoris'),
            onSearch: () => _showComingSoon('Recherche'),
            onSettings: () => _showComingSoon('Réglages'),
          ),
          const SizedBox(height: 24),

          // ---- Pour vous ----
          ChannelRow(
            title: 'Pour vous',
            channels: forYou,
            onChannelTap: _onChannelTap,
            onSeeAll: () => _showComingSoon('Voir tout — Pour vous'),
          ),
          const SizedBox(height: 24),

          // ---- En direct ----
          ChannelRow(
            title: 'En direct maintenant',
            channels: liveNow,
            onChannelTap: _onChannelTap,
            onSeeAll: () => _showComingSoon('Voir tout — En direct'),
          ),
          const SizedBox(height: 24),

          // ---- Catégorie phare ----
          if (topCategoryChannels.isNotEmpty)
            ChannelRow(
              title: topCategory,
              channels: topCategoryChannels,
              onChannelTap: _onChannelTap,
              onSeeAll: () => _showComingSoon('Voir tout — $topCategory'),
            ),
          if (topCategoryChannels.isNotEmpty) const SizedBox(height: 24),

          // ---- Découvertes ----
          ChannelRow(
            title: 'Découvertes',
            channels: discoveries,
            onChannelTap: _onChannelTap,
            onSeeAll: () => _showComingSoon('Voir tout — Découvertes'),
          ),
        ],
      ),
    );
  }

  /// Trouve la catégorie la plus présente dans la playlist.
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
        // Bouton "Ajouter playlist" toujours accessible
        IconButton(
          tooltip: 'Ajouter une playlist',
          onPressed: _openAddPlaylist,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
        ),
        IconButton(
          tooltip: 'Recherche',
          onPressed: () => _showComingSoon('Recherche'),
          icon: const Icon(Icons.search, color: Colors.white),
        ),
        IconButton(
          tooltip: 'Profil',
          onPressed: () => _showComingSoon('Profil'),
          icon: const Icon(Icons.account_circle_outlined, color: Colors.white),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Fond global de l'écran : dégradé + 2 halos d'ambiance.
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
