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
import '../../../core/notifications/notification_service.dart';
import '../../../core/widgets/celebration_overlay.dart';
import '../../../core/widgets/legal_disclaimer.dart';
import '../../stats/data/engagement_service.dart';
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
import '../../sports/data/match_alerts_service.dart';
import '../../sports/presentation/sport_screen.dart';
import '../../../core/app/device_memory.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/domain/vod_movie.dart';
import '../../playlists/data/remote_source_repository.dart';
import '../../playlists/presentation/import_progress_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../subscription/data/subscription_state.dart';
import '../../subscription/presentation/guest_screen.dart';
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

  /// Vrai pendant que l'écran d'import VIVANT est affiché : empêche d'en
  /// ouvrir un second (tick du sondage OU signal temps réel pendant l'import).
  bool _importing = false;

  /// Garde anti-empilement de la barre du bas : un double-tap rapide sur
  /// « Favoris » / « IA » / « Ajouter » déclenchait DEUX push (ou deux
  /// feuilles) — le 2e tap partait avant que la 1re route ne couvre l'écran.
  /// Un seul écran secondaire à la fois ; le flag se libère au retour (pop).
  bool _navBusy = false;

  /// Ouvre un écran/feuille depuis la barre du bas, protégé par [_navBusy].
  /// `open` retourne le Future de la route poussée (ou de la feuille) : on
  /// l'attend pour ne relâcher la garde qu'au retour sur l'accueil.
  Future<void> _openFromBottomBar(Future<void> Function() open) async {
    if (_navBusy || !mounted) return;
    _navBusy = true;
    try {
      await open();
    } finally {
      _navBusy = false;
    }
  }

  @override
  void initState() {
    super.initState();
    FavoritesRepository.instance.initialize();
    RecentlyWatchedRepository.instance.initialize();
    // Palier de streak atteint → on célèbre à l'accueil (Hook : récompense).
    EngagementService.instance.addListener(_maybeCelebrate);
    // Invitation à laisser un avis (pilotée par le panel) : affichée en
    // douceur quelques secondes après l'arrivée sur l'accueil, une seule
    // fois par message. Sans effet si désactivée ou déjà répondue.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // RÉ-ENGAGEMENT : (re)programme les rappels de retour à chaque
      // ouverture — le fait d'être là repousse le rappel de dormance, donc
      // un habitué ne le voit jamais. Best-effort / silencieux.
      unawaited(NotificationService.instance.scheduleReEngagement());
      // ALERTES DES GRANDS MATCHS (demande propriétaire du 22/08 : « une
      // app d'IPTV ET de notifications de match ») : à chaque arrivée sur
      // l'accueil, on (re)programme le rappel « coup d'envoi dans 15 min »
      // des grandes affiches et on annonce les scores fraîchement connus.
      // Le service s'auto-limite (une passe / 30 min) et se tait si
      // l'interrupteur des Réglages est éteint.
      unawaited(MatchAlertsService.instance.refresh());
      // Un palier peut déjà être en attente (atteint pendant la session
      // précédente, juste avant de fermer l'app).
      _maybeCelebrate();
      Future<void>.delayed(const Duration(seconds: 8), () {
        if (mounted) maybeShowFeedbackSheet(context);
      });
    });
    // PRÉCHAUFFAGE DU CINÉMA (photo client du 22/08 : « le cinéma côté
    // mobile tarde à venir ») : le catalogue n'était chargé qu'à l'OUVERTURE
    // de l'écran — le client payait alors l'attente complète devant un
    // squelette. On le tire ici, en tâche de fond, pendant qu'il regarde
    // l'accueil : à l'ouverture, le Cinéma est servi depuis la mémoire.
    //
    // GARDE-FOUS : (a) seulement s'il y a déjà une source (sinon rien à
    // charger) ; (b) JAMAIS sur un téléphone à faible RAM — c'est le profil
    // qu'on a passé la journée du 21/08 à protéger de l'OOM ; (c) après un
    // délai, pour ne pas concurrencer le premier rendu de l'accueil ;
    // (d) best-effort absolu : une erreur ici ne doit rien changer.
    //
    // DÉLAI RAMENÉ DE 3 s À 1,2 s : à 3 s, le client qui file droit sur le
    // Cinéma arrivait AVANT le préchauffage et payait l'attente entière —
    // le préchauffage ne servait qu'à ceux qui traînaient sur l'accueil.
    // Ce raccourcissement n'est devenu SÛR qu'avec la fusion des appels
    // simultanés dans VodRepository : sans elle, ouvrir le Cinéma pendant
    // le préchauffage lançait un SECOND téléchargement complet.
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      // Palier PARTAGÉ (et non `lowRam` seul : beaucoup de téléphones bon
      // marché ne déclarent pas ce drapeau alors qu'ils ont ≤ 1 Go).
      if (DeviceMemory.isSmall) return;
      if (PlaylistRepository.instance.currentChannels.isEmpty) return;
      unawaited(
        VodRepository.instance.fetchMovies().catchError(
          (Object _) => const <VodMovie>[],
        ),
      );
    });
    // TEMPS RÉEL : dès que le revendeur pousse une source depuis le panel,
    // RealtimeSyncService bumpe `pushedTick` → on charge la source IMMÉDIA-
    // TEMENT (import vivant), sans attendre le prochain tick du sondage. C'est
    // ce qui rend l'activation INSTANTANÉE côté client.
    RemoteSourceRepository.pushedTick.addListener(_onSourcePushed);
    // Démarre le sondage auto SEULEMENT si on est sur l'écran vide. Si des
    // chaînes sont déjà là (client qui revient), inutile de sonder.
    if (PlaylistRepository.instance.currentChannels.isEmpty) {
      // 1er essai rapide (2 s) puis toutes les 6 s (filet si le temps réel
      // n'a pas pu joindre l'appareil : socket coupé, app en arrière-plan…).
      Future<void>.delayed(const Duration(seconds: 2), _pollActivation);
      _activationPoll = Timer.periodic(
        const Duration(seconds: 6),
        (_) => _pollActivation(),
      );
    }
  }

  /// Réaction au signal temps réel « source poussée » : si on est encore sur
  /// l'écran d'activation (pas de chaînes), on déclenche le chargement VIVANT
  /// tout de suite.
  void _onSourcePushed() {
    if (!mounted) return;
    if (PlaylistRepository.instance.currentChannels.isNotEmpty) return;
    unawaited(_pollActivation());
  }

  @override
  void dispose() {
    _activationPoll?.cancel();
    RemoteSourceRepository.pushedTick.removeListener(_onSourcePushed);
    EngagementService.instance.removeListener(_maybeCelebrate);
    super.dispose();
  }

  /// Affiche la célébration si un palier de streak est en attente. Appelé
  /// à l'arrivée sur l'accueil ET à chaque notification de l'EngagementService.
  void _maybeCelebrate() {
    final int m = EngagementService.instance.pendingMilestone;
    if (m > 0 && mounted) {
      EngagementService.instance.consumeMilestone();
      showStreakCelebration(context, m);
    }
  }

  /// Un tick du sondage (ou un signal temps réel) : cherche la source assignée
  /// par le revendeur et, si elle existe, la charge EN MONTRANT l'écran d'import
  /// VIVANT (les chaînes qui s'ajoutent en direct) — exactement comme le bouton
  /// manuel « Vérifier mon abonnement ». Avant, ce chemin automatique chargeait
  /// la source EN SILENCE : le client ne voyait rien télécharger et l'activation
  /// paraissait ne « rien faire ».
  Future<void> _pollActivation() async {
    if (_polling || _importing || !mounted) return;
    // Déjà des chaînes ? on arrête le sondage (cas course / retour écran).
    if (PlaylistRepository.instance.currentChannels.isNotEmpty) {
      _activationPoll?.cancel();
      return;
    }
    _polling = true;
    List<Map<String, dynamic>> pending = const <Map<String, dynamic>>[];
    try {
      await SubscriptionState.instance.syncWithBackend();
      // On récupère la/les source(s) SANS les charger : si quelque chose est en
      // attente, on bascule sur l'import VIVANT (avec progression) plutôt qu'un
      // chargement silencieux.
      pending = await RemoteSourceRepository.fetchAssignedSources();
    } catch (_) {
      // Réseau capricieux : on réessaiera au prochain tick.
    } finally {
      _polling = false;
    }
    if (!mounted || pending.isEmpty) return;
    // Course : une autre voie (temps réel, sync silencieux de secours) a pu
    // charger entre-temps → on ne double pas.
    if (PlaylistRepository.instance.currentChannels.isNotEmpty) {
      _activationPoll?.cancel();
      return;
    }

    // IMPORT VIVANT plein écran : « Activation de tes chaînes… » avec les
    // catégories/chaînes qui s'ajoutent en direct. Le client VOIT le
    // téléchargement, sans avoir rien tapé.
    _activationPoll?.cancel();
    _importing = true;
    try {
      await runImportWithProgress<RemoteSyncResult>(
        context,
        title: context.l10n.activationLoadingTitle,
        task: (onProgress) =>
            RemoteSourceRepository.applySources(pending, onProgress: onProgress),
      );
    } catch (_) {
      // Best-effort : un échec ne doit jamais bloquer l'accueil.
    } finally {
      _importing = false;
    }
    if (!mounted) return;
    // L'import a-t-il vraiment chargé des chaînes ? Sinon (provider KO), on
    // relance le sondage de secours pour retenter au prochain tick.
    if (PlaylistRepository.instance.currentChannels.isEmpty) {
      _activationPoll ??= Timer.periodic(
        const Duration(seconds: 6),
        (_) => _pollActivation(),
      );
    }
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

              // Pas de playlist → écran d'activation par code MAC. (Quand le
              // revendeur pousse la source, l'import VIVANT s'affiche par-dessus
              // via _pollActivation ; à la fin, `channels` n'est plus vide et
              // on révèle les catégories.)
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
                  // Barre « mode invité » — fine, toujours visible en haut de
                  // l'accueil : inviter un ami, prêter son abonnement, ou
                  // entrer un code reçu. Demande client : « toujours présent,
                  // surtout côté mobile, à l'écran d'accueil ».
                  _GuestEntryBar(onTap: () => openGuestScreen(context)),
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
          const SizedBox(height: 24),
          // « Invité ou code perso ? » — le tout premier choix d'une nouvelle
          // install : soit on a été invité par un ami (mode invité), soit on a
          // son propre identifiant à activer (les blocs ci-dessous).
          _GuestEntryCard(onTap: () => openGuestScreen(context)),
          const SizedBox(height: 22),
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
          // Streak d'engagement : compteur discret « N » (jours d'affilée).
          // Visible dès 1 jour — voir le chiffre monter donne envie de ne pas
          // casser la série (déclencheur INTERNE de retour quotidien). Se met
          // à jour en direct quand un nouveau jour est compté.
          ListenableBuilder(
            listenable: EngagementService.instance,
            builder: (BuildContext context, _) {
              final int s = EngagementService.instance.streak;
              if (s < 1) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accentSurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.local_fire_department_rounded,
                          size: 14, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        '$s',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Mode invité — toujours accessible depuis l'accueil : inviter un
          // ami, entrer un code, ou envoyer son identifiant.
          IconButton(
            tooltip: context.l10n.guestScreenTitle,
            icon: const Icon(Icons.card_giftcard_rounded),
            onPressed: () => openGuestScreen(context),
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
      // `spaceAround` répartissait l'espace RESTANT ; à 5 onglets il n'en
      // restait plus, d'où un débordement. Chaque onglet prend désormais
      // une part ÉGALE de la largeur, quelle que soit la taille de l'écran.
      child: Row(
        children: <Widget>[
          // « Accueil » : la barre n'existe QUE sur l'accueil (les autres
          // onglets sont des routes plein écran qui la recouvrent), donc
          // `active: true` reflète bien la réalité ici — et taper l'onglet
          // courant ne doit rien faire (comportement standard des bottom bars).
          Expanded(
            child: _BottomNavItem(
              icon: Icons.home_rounded,
              label: context.l10n.navHome,
              active: true,
              onTap: () {},
            ),
          ),
          Expanded(
            child: _BottomNavItem(
              icon: Icons.favorite_rounded,
              label: context.l10n.navFavorites,
              active: false,
              onTap: () => _openFromBottomBar(
                () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                      builder: (_) => const FavoritesScreen()),
                ),
              ),
            ),
          ),
          // SPORT (demande client du 23/08 : « ajoute tout un coin dédié au
          // sport »). Tous les sports, pas seulement le football — et c'est
          // de là qu'on choisit les matchs à suivre un par un.
          Expanded(
            child: _BottomNavItem(
              icon: Icons.sports_soccer_rounded,
              label: context.l10n.navSport,
              active: false,
              onTap: () => _openFromBottomBar(
                () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const SportScreen()),
                ),
              ),
            ),
          ),
          // Recherche IA (langage naturel), mise en avant (ember) au centre.
          Expanded(
            child: _BottomNavItem(
              icon: Icons.auto_awesome_rounded,
              label: context.l10n.navAi,
              active: false,
              accent: true,
              onTap: () => _openFromBottomBar(
                () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                ),
              ),
            ),
          ),
          // « Ajouter » = activation par code MAC (pas de M3U/Xtream).
          Expanded(
            child: _BottomNavItem(
              icon: Icons.add_circle_outline_rounded,
              label: context.l10n.buttonAdd,
              active: false,
              onTap: () =>
                  _openFromBottomBar(() => showActivationSheet(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte « Mode invité » — le premier choix d'une install neuve, posée en
/// haut de l'écran d'activation : « On t'a invité ? » → ouvre le mode invité
/// (tape un code, ou envoie ton identifiant à celui qui t'invite). Toujours
/// visible côté mobile, comme demandé.
class _GuestEntryCard extends StatelessWidget {
  const _GuestEntryCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.accentSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.card_giftcard_rounded,
                  color: AppColors.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.homeGuestCardTitle,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.homeGuestCardBody,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.accent, size: 24),
          ],
        ),
      ),
    );
  }
}

/// Barre FINE « mode invité » posée en haut de l'accueil rempli. Une seule
/// ligne, tappable, teintée ember — impossible à rater sans manger l'espace
/// d'une grosse carte.
class _GuestEntryBar extends StatelessWidget {
  const _GuestEntryBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accentSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.card_giftcard_rounded,
                  color: AppColors.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.homeGuestBarLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.accent, size: 22),
            ],
          ),
        ),
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
        // Padding RÉDUIT et libellé ellipsé : depuis l'ajout du 5e onglet
        // (Sport), un padding de 16 de chaque côté faisait déborder la
        // barre sur un écran de 320 dp — exactement les petits téléphones
        // qu'on s'est engagé à supporter.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
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
