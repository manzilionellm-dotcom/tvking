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

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/branding/brand_config.dart';
import '../../../core/branding/brand_logo.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/legal_disclaimer.dart';
import '../../channels/domain/channel.dart';
import '../../channels/presentation/favorites_screen.dart';
import '../../channels/presentation/search_screen.dart';
import '../../channels/presentation/widgets/mac_activation_view.dart';
import '../../channels/presentation/widgets/resume_banner.dart';
import '../../feedback/presentation/feedback_sheet.dart';
import '../../channels/presentation/widgets/source_choice_sheet.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../subscription/data/subscription_state.dart';
import 'widgets/announcement_banner.dart';
import 'widgets/category_browser_view.dart';

class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({super.key});

  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen> {
  /// Sondage SILENCIEUX de la source assignée par le revendeur. Tant que
  /// l'app n'a pas de chaînes (écran d'activation affiché), on interroge
  /// le backend toutes les 6 s. Dès que le revendeur a poussé la MAC dans
  /// le panel, l'app charge la source TOUTE SEULE — le client n'a rien à
  /// taper. Le timer s'arrête net dès que des chaînes sont chargées.
  Timer? _activationPoll;

  /// Évite deux sondages simultanés (réseau lent).
  bool _polling = false;

  /// Affiche brièvement un écran « Activation réussie — redémarrage… »
  /// quand la source vient d'arriver automatiquement, pour que le client
  /// perçoive un redémarrage propre plutôt qu'un changement brusque.
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    FavoritesRepository.instance.initialize();
    RecentlyWatchedRepository.instance.initialize();
    // Invitation à laisser un avis (pilotée par le panel) : affichée en
    // douceur quelques secondes après l'arrivée sur l'accueil, une seule
    // fois par message. Sans effet si désactivée ou déjà répondue.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 8), () {
        if (mounted) maybeShowFeedbackSheet(context);
      });
    });
    // Démarre le sondage auto SEULEMENT si on est sur l'écran vide. Si des
    // chaînes sont déjà là (client qui revient), inutile de sonder.
    if (PlaylistRepository.instance.currentChannels.isEmpty) {
      // 1er essai rapide (2 s) puis toutes les 6 s.
      Future<void>.delayed(const Duration(seconds: 2), _pollActivation);
      _activationPoll = Timer.periodic(
        const Duration(seconds: 6),
        (_) => _pollActivation(),
      );
    }
  }

  @override
  void dispose() {
    _activationPoll?.cancel();
    super.dispose();
  }

  /// Un tick du sondage : resynchronise l'abonnement + la source poussée.
  /// Si une source vient d'être chargée (chaînes passées de 0 à >0), on
  /// déclenche la transition « redémarrage » et on coupe le timer.
  Future<void> _pollActivation() async {
    if (_polling || !mounted) return;
    // Déjà des chaînes ? on arrête le sondage (cas course / retour écran).
    if (PlaylistRepository.instance.currentChannels.isNotEmpty) {
      _activationPoll?.cancel();
      return;
    }
    _polling = true;
    try {
      await SubscriptionState.instance.syncWithBackend();
      await RemoteSourceRepository.sync();
    } catch (_) {
      // Réseau capricieux : on réessaiera au prochain tick.
    } finally {
      _polling = false;
    }
    if (!mounted) return;
    // La source a-t-elle chargé des chaînes ?
    if (PlaylistRepository.instance.currentChannels.isNotEmpty) {
      _activationPoll?.cancel();
      _enterRestart();
    }
  }

  /// Joue la transition « redémarrage » ~1,8 s puis révèle les catégories.
  /// Le StreamBuilder a déjà les chaînes en main : on ne fait que retarder
  /// l'affichage pour un effet de redémarrage propre et rassurant.
  void _enterRestart() {
    setState(() => _restarting = true);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _restarting = false);
    });
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

              // Transition « redémarrage » : la source vient d'arriver
              // automatiquement, on l'annonce en douceur avant de révéler
              // les catégories (le client a juste l'impression que l'app
              // redémarre, sans rien avoir tapé).
              if (_restarting) return _buildRestartSplash(context);

              // Pas de playlist → écran d'activation par code MAC.
              if (channels.isEmpty) return _buildActivationEntry(context);

              // Playlist chargée → catégories → chaînes.
              return Column(
                children: <Widget>[
                  _buildHeader(),
                  // Bandeau « message à tous » (annonce admin). Auto-géré :
                  // ne prend aucune place s'il n'y a rien à montrer.
                  const AnnouncementBanner(),
                  // « Reprendre » : bannière façon Continue Watching de
                  // Netflix (génère ~70% des plays). Apparaît seulement si
                  // une session récente (< 60 min) existe ; sinon invisible.
                  // En Privé, aucun historique n'est tracké (incognito) →
                  // elle reste donc masquée, ce qui respecte la promesse.
                  const ResumeBanner(),
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
              BrandConfig.instance.appName,
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

  // ----- Transition « redémarrage » (source poussée reçue) -----
  //  Plein écran, centré : logo + spinner + texte rassurant. Affiché
  //  ~1,8 s par _enterRestart() quand le sondage auto a chargé la source.
  Widget _buildRestartSplash(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const BrandLogo.medium(),
          const SizedBox(height: 28),
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            context.l10n.activationRestartTitle,
            style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.activationRestartSubtitle,
            style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
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
              BrandConfig.instance.appName,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Sélecteur de SOURCE — visible seulement si le client a un
          // TRIO (≥ 2 sources poussées par le revendeur sur sa MAC). Tape
          // → feuille pour basculer d'un abonnement à l'autre.
          if (PlaylistRepository.instance.currentPlaylists.length >= 2)
            IconButton(
              tooltip: context.l10n.simpleSwitchSource,
              icon: const Icon(Icons.layers_rounded),
              onPressed: () => _showSourceSwitcher(context),
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

  /// Feuille de bascule entre les sources du TRIO. Liste les playlists
  /// chargées ; tape l'une d'elles → elle devient active (ses catégories
  /// s'affichent aussitôt). Pas de saisie : tout vient du revendeur.
  void _showSourceSwitcher(BuildContext context) {
    final List<dynamic> playlists =
        PlaylistRepository.instance.currentPlaylists;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  context.l10n.simpleSwitchSource,
                  style: AppTextStyles.headlineMedium.copyWith(fontSize: 16),
                ),
              ),
              for (final dynamic p in playlists)
                ListTile(
                  leading: Icon(
                    p.isActive == true
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: p.isActive == true
                        ? AppColors.accent
                        : AppColors.textTertiary,
                  ),
                  title: Text(
                    (p.name as String?)?.isNotEmpty == true
                        ? p.name as String
                        : context.l10n.homeSourceFallback,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 14),
                  ),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    final int? id = p.id as int?;
                    if (id != null && p.isActive != true) {
                      await PlaylistRepository.instance.setActivePlaylist(id);
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
