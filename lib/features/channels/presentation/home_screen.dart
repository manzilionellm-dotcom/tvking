// =========================================================
//  home_screen.dart — Écran d'accueil "TV King" v0.2
// =========================================================
//  Refonte UI Phase 1.0bis — layout style Apple TV / Netflix.
//
//  Composition (de haut en bas) :
//    1. AppBar minimaliste (logo + recherche/profil)
//    2. Hero vedette (un grand panneau pour LA chaîne mise
//       en avant, avec play button + boutons d'action)
//    3. Quick Chips (Catégories / Favoris / Recherche / Réglages)
//    4. Rangée horizontale "Pour vous" (chaînes recommandées)
//    5. Rangée horizontale "En direct maintenant" (lives actuels)
//    6. Rangée horizontale "Découvertes" (chaînes peu vues)
//    7. Floating bottom nav (Accueil / TV Guide / Films / etc.)
//
//  Phase 1 — pas encore de logique de recommandation ; on
//  utilise les 10 chaînes fictives en les répartissant dans
//  les sections de façon visuellement plaisante.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/fake_channels.dart';
import '../domain/channel.dart';
import 'widgets/channel_row.dart';
import 'widgets/floating_bottom_nav.dart';
import 'widgets/hero_section.dart';
import 'widgets/quick_chips_row.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Index de l'onglet actif dans la bottom nav.
  /// 0 = Accueil par défaut. Les autres onglets afficheront
  /// un placeholder "Bientôt disponible" pour l'instant.
  int _currentNavIndex = 0;

  /// Notification stub réutilisée par tous les boutons placeholder.
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

  @override
  Widget build(BuildContext context) {
    // On découpe les 10 chaînes fictives en sections variées.
    // Phase 1 — pas de vraie recommandation, juste un découpage
    // visuel pour remplir l'UI.
    final Channel hero = kFakeChannels.first;
    final List<Channel> forYou = kFakeChannels.sublist(1);
    final List<Channel> liveNow =
        kFakeChannels.where((Channel c) => c.isLive).toList();
    final List<Channel> discoveries =
        kFakeChannels.reversed.toList(); // ordre inversé pour varier

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true, // la bottom nav flotte par-dessus le contenu
      appBar: _buildAppBar(),
      body: Stack(
        children: <Widget>[
          // ===== Couche 1 : dégradé de fond principal =====
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.backgroundGradient,
            ),
            child: SizedBox.expand(),
          ),

          // ===== Couche 2 : halos d'ambiance =====
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

          // ===== Couche 3 : contenu scrollable =====
          SafeArea(
            bottom: false, // la bottom nav gère son propre safe-area
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Espace sous AppBar transparente
                  const SizedBox(height: 70),

                  // ---- HERO : grande bannière vedette ----
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: HeroSection(
                      channel: hero,
                      onWatch: () => _onChannelTap(hero),
                      onInfo: () =>
                          _showComingSoon('Fiche détaillée de la chaîne'),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ---- Quick Chips ----
                  QuickChipsRow(
                    onCategories: () => _showComingSoon('Catégories'),
                    onFavorites: () => _showComingSoon('Favoris'),
                    onSearch: () => _showComingSoon('Recherche'),
                    onSettings: () => _showComingSoon('Réglages'),
                  ),

                  const SizedBox(height: 24),

                  // ---- Rangée "Pour vous" ----
                  ChannelRow(
                    title: 'Pour vous',
                    channels: forYou,
                    onChannelTap: _onChannelTap,
                    onSeeAll: () => _showComingSoon('Voir tout — Pour vous'),
                  ),

                  const SizedBox(height: 24),

                  // ---- Rangée "En direct maintenant" ----
                  ChannelRow(
                    title: 'En direct maintenant',
                    channels: liveNow,
                    onChannelTap: _onChannelTap,
                    onSeeAll: () => _showComingSoon('Voir tout — En direct'),
                  ),

                  const SizedBox(height: 24),

                  // ---- Rangée "Découvertes" ----
                  ChannelRow(
                    title: 'Découvertes',
                    channels: discoveries,
                    onChannelTap: _onChannelTap,
                    onSeeAll: () => _showComingSoon('Voir tout — Découvertes'),
                  ),
                ],
              ),
            ),
          ),

          // ===== Couche 4 : bottom nav flottante =====
          Align(
            alignment: Alignment.bottomCenter,
            child: FloatingBottomNav(
              currentIndex: _currentNavIndex,
              onTap: (int i) {
                setState(() => _currentNavIndex = i);
                if (i != 0) {
                  _showComingSoon(_navLabel(i));
                  // On revient sur Accueil après l'annonce — phase 1.
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
          onPressed: () => _showComingSoon('Recherche'),
          icon: const Icon(Icons.search, color: Colors.white),
        ),
        IconButton(
          onPressed: () => _showComingSoon('Profil'),
          icon: const Icon(Icons.account_circle_outlined, color: Colors.white),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// Halo lumineux circulaire pour l'ambiance VIP.
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
