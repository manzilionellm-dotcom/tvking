// =========================================================
//  simple_home_screen.dart — Accueil mobile (façon TiviMate)
// =========================================================
//  Refonte « Black7 » demandée par le client : on RESPECTE l'organisation
//  d'origine de la playlist, sans aucune reclassification maison.
//
//    • ACCUEIL VIDE (pas de playlist) → uniquement l'activation par
//      CODE MAC : le client ne saisit RIEN (ni M3U, ni serveur, ni
//      identifiant). Il voit son code, l'envoie au revendeur qui active
//      à distance, puis « Vérifier mon abonnement » charge la source.
//      Une petite marque en haut. Rien d'autre.
//
//    • ACCUEIL REMPLI → navigation à deux niveaux :
//        1. la LISTE DES CATÉGORIES de la playlist (group-title), avec le
//           nombre de chaînes ;
//        2. on tape → la liste PROPRE des chaînes de cette catégorie.
//      (cf. CategoryBrowserView)
//
//  Plus de grille de pays, plus de HERO, plus de sections curées, plus de
//  verrou cinéma : tout ça a été retiré. Données 100 % réelles
//  (PlaylistRepository). Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/branding/brand_logo.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/legal_disclaimer.dart';
import '../../channels/domain/channel.dart';
import '../../channels/presentation/favorites_screen.dart';
import '../../channels/presentation/search_screen.dart';
import '../../channels/presentation/widgets/mac_activation_view.dart';
import '../../channels/presentation/widgets/source_choice_sheet.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../profile/presentation/profile_screen.dart';
import 'widgets/announcement_banner.dart';
import 'widgets/category_browser_view.dart';

class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({super.key});

  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen> {
  @override
  void initState() {
    super.initState();
    FavoritesRepository.instance.initialize();
    RecentlyWatchedRepository.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: StreamBuilder<List<Channel>>(
            stream: PlaylistRepository.instance.channelsStream,
            initialData: PlaylistRepository.instance.currentChannels,
            builder:
                (BuildContext context, AsyncSnapshot<List<Channel>> snap) {
              final List<Channel> channels = snap.data ?? const <Channel>[];

              // Pas de playlist → écran d'activation par code MAC.
              if (channels.isEmpty) return _buildActivationEntry(context);

              // Playlist chargée → catégories → chaînes.
              return Column(
                children: <Widget>[
                  _buildHeader(),
                  // Bandeau « message à tous » (annonce admin). Auto-géré :
                  // ne prend aucune place s'il n'y a rien à montrer.
                  const AnnouncementBanner(),
                  Expanded(child: CategoryBrowserView(channels: channels)),
                  _buildBottomBar(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ----- Accueil VIDE : activation par code MAC uniquement -----
  //  Le client ne saisit RIEN (ni M3U, ni serveur, ni identifiant). Il
  //  voit son code, l'envoie au revendeur, puis « Vérifier mon
  //  abonnement » charge la source poussée. Au succès, le StreamBuilder
  //  se reconstruit tout seul et révèle la liste des catégories.
  Widget _buildActivationEntry(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Petite marque en haut.
          const SizedBox(height: 12),
          const Center(child: BrandLogo.medium()),
          const SizedBox(height: 12),
          Center(
            child: Text(
              BrandStrings.appName,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
            ),
          ),
          const SizedBox(height: 30),
          const MacActivationView(),
          const SizedBox(height: 14),
          const LegalDisclaimer.compact(),
        ],
      ),
    );
  }

  // ----- En-tête (accueil rempli) -----
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: BrandLogo.compact(),
          ),
          Expanded(
            child: Text(
              BrandStrings.appName,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: context.l10n.simpleMyAccount,
            icon: const Icon(Icons.person_rounded),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
    );
  }

  // ----- Barre du bas -----
  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.35),
        border: const Border(top: BorderSide(color: AppColors.surface)),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _BottomNavItem(
            icon: Icons.home_rounded,
            label: context.l10n.navHome,
            active: true,
            onTap: () {},
          ),
          _BottomNavItem(
            icon: Icons.favorite_rounded,
            label: context.l10n.navFavorites,
            active: false,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()),
            ),
          ),
          // Recherche IA (langage naturel), mise en avant (ember) au centre.
          _BottomNavItem(
            icon: Icons.auto_awesome_rounded,
            label: context.l10n.navAi,
            active: false,
            accent: true,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
          // « Ajouter » = activation par code MAC (pas de M3U/Xtream).
          _BottomNavItem(
            icon: Icons.add_circle_outline_rounded,
            label: context.l10n.buttonAdd,
            active: false,
            onTap: () => showActivationSheet(context),
          ),
        ],
      ),
    );
  }
}

/// Élément de la barre de navigation du bas (mobile) — icône + libellé,
/// teinté ember quand actif, estompé sinon.
class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Onglet « vedette » (la recherche IA) : toujours teinté ember, avec
  /// l'icône posée sur une pastille accent pour ressortir au centre.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final Color color =
        (active || accent) ? AppColors.accent : AppColors.textTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (accent)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.55),
                    width: 1.2,
                  ),
                ),
                child: Icon(icon, color: color, size: 26),
              )
            else
              Icon(icon, color: color, size: 26),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontSize: 10,
                letterSpacing: 0.4,
                fontWeight: accent ? FontWeight.w800 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
