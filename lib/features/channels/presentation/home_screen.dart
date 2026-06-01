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

import '../../../core/branding/brand_logo.dart';
import '../../../core/flavor/flavor.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/cinematic_spacing.dart';
import '../../cast/presentation/cast_mini_bar.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/presentation/add_playlist_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../security/data/biometric_auth.dart';
import '../data/recently_watched_repository.dart';
import '../domain/channel.dart';
import '../domain/channel_genre.dart';
import 'focused_category_screen.dart';
import 'widgets/round_category_row.dart';
import 'category_section_screen.dart';
import 'channel_detail_sheet.dart';
import 'favorites_screen.dart';
import 'search_screen.dart';
import '../data/affinity_service.dart';
import '../data/time_of_day_service.dart';
import 'widgets/empty_state.dart';
import 'widgets/floating_bottom_nav.dart';
import 'widgets/hero_section.dart';
import 'widgets/live_now_favorites_row.dart';
import 'widgets/premium_row.dart';
import 'widgets/resume_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Index 1 = "Live TV" sur la nouvelle BottomNav (la nav refaite
  // a Live en 0 et Live TV en 1, et l'accueil EST Live TV).
  // Phase 1.0b : Home = index 0 (au lieu de Live TV index 1 dans
  // l'ancienne nav). Voir floating_bottom_nav.dart pour la liste
  // des onglets : Home, Trending, Live, Favoris, Profil.
  int _currentNavIndex = 0;
  final FavoritesRepoSnapshot _favSnap = FavoritesRepoSnapshot();

  /// Cache mémoïsé du bucketing par genre. La home se rebuild à
  /// chaque event stream (refresh, favoris, affinité…), et bucketer
  /// 27 000 chaînes en 8 listes prend ~50 ms — accumulé sur 10
  /// rebuilds, c'est visible. On garde la dernière computation
  /// indexée par l'IDENTITÉ de la liste reçue : tant que le repo
  /// ne ré-émet pas, on réutilise le cache.
  List<Channel>? _bucketCacheKey;
  _Buckets? _bucketCacheValue;

  @override
  void initState() {
    super.initState();
    // Calcule les scores d'affinité + l'heure suggérée au démarrage
    // pour que la première frame ait déjà les rangées dans le bon
    // ordre. Aucune attente — les services sont ChangeNotifier, l'UI
    // rebuilds automatiquement quand le calcul finit (via _onAffinityChanged).
    AffinityService.instance.addListener(_onAffinityChanged);
    AffinityService.instance.ensureFresh();
    TimeOfDayService.instance.refresh();
  }

  @override
  void dispose() {
    AffinityService.instance.removeListener(_onAffinityChanged);
    super.dispose();
  }

  void _onAffinityChanged() {
    if (mounted) setState(() {});
  }

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

  // ----- Catégories rondes (chips Apple TV) -----
  //
  //  Football a son propre écran (FocusedCategoryScreen) qui regroupe
  //  par pays — c'est la demande explicite : "toutes les chaînes
  //  football, mais avec les pays vu différemment". Pour les autres
  //  catégories on réutilise CategorySectionScreen existant (grille
  //  standard) — pas besoin de re-grouper là.

  Future<void> _openFootball() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const FocusedCategoryScreen(
          title: 'Football',
          keywords: <String>[
            'foot', 'soccer', 'bein', 'rmc sport', 'champion',
            'ligue 1', 'ligue 2', 'premier league', 'liga',
            'serie a', 'bundesliga', 'eurosport', 'fox sport',
            'sky sport', 'tnt sport', 'espn',
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    // Sur le flavor Red Room (adultOnly = true), aucun de ces genres
    // n'a de sens — il n'y a pas de Football / Jeunesse / Info dans
    // un catalogue 18+. Phase 1.0c remplacera par des chips Red Room
    // (Couples, Solo, Studios, etc.) ; pour 1.0b on hide simplement.
    if (FlavorConfig.current.adultOnly) {
      return const SizedBox.shrink();
    }
    // Phase 1+/2026-06-01 : icones line art (outlined) au lieu des
    // pleines rondes, pour matcher l'estehique "premium streaming
    // dashboard" demandee par l'utilisateur.
    return RoundCategoryRow(
      items: <RoundCategoryItem>[
        RoundCategoryItem(
          label: 'Football',
          icon: Icons.sports_soccer_outlined,
          onTap: _openFootball,
        ),
        RoundCategoryItem(
          label: 'Jeunesse',
          icon: Icons.child_friendly_outlined,
          onTap: () => _openSection('Jeunesse', ChannelGenre.kids),
        ),
        RoundCategoryItem(
          label: 'Cinema',
          icon: Icons.movie_creation_outlined,
          onTap: () => _openSection(
            'Divertissement',
            ChannelGenre.entertainment,
          ),
        ),
        RoundCategoryItem(
          label: 'Actu',
          icon: Icons.newspaper_outlined,
          onTap: () => _openSection('Info', ChannelGenre.news),
        ),
        RoundCategoryItem(
          label: 'Docu',
          icon: Icons.travel_explore_outlined,
          onTap: () => _openSection('Documentaires', ChannelGenre.documentary),
        ),
        RoundCategoryItem(
          label: 'Musique',
          icon: Icons.music_note_outlined,
          onTap: () => _openSection('Musique', ChannelGenre.music),
        ),
      ],
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // La signature ne défile plus en pied d'écran — elle
                // vit maintenant en haut, collée sous le logo dans
                // l'AppBar (cf. _buildAppBar). Voir BrandSignature.
                FloatingBottomNav(
                  currentIndex: _currentNavIndex,
                  onTap: _onNavTap,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    // Refonte Phase 1.0b : top bar minimal style Netflix / Apple TV+.
    // L'ancienne AppBar exposait 5 boutons (Refresh, Cast, Guide TV,
    // Recherche, Reglages) — visuel de console d'admin, pas de
    // plateforme premium. Tout ca part dans l'onglet Profil de la
    // nav du bas, sauf la Recherche qui reste dispo en 1 tap.
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const BrandLogo.compact(),
      titleSpacing: CinematicSpacing.l,
      actions: <Widget>[
        IconButton(
          tooltip: 'Recherche',
          onPressed: _openSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: 'Profil',
          onPressed: _goToProfile,
          icon: const Icon(Icons.person_rounded),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  /// Bascule sur l'onglet Profil (index 4) — utilise par l'icone
  /// profile en haut a droite, qui doit ouvrir la meme vue que le
  /// tap sur la nav du bas (coherence Apple TV+ / Mubi).
  void _goToProfile() {
    setState(() => _currentNavIndex = 4);
  }

  // ============================================================
  //  Contenu principal — liste verticale de sections
  // ============================================================

  Widget _buildContent(List<Channel> all) {
    // ----- Memoization : on bucketise UNE FOIS par liste -----
    //  L'identity check (`identical`) suffit car le repo crée une
    //  nouvelle List<Channel> à chaque émission. Tant que la même
    //  liste est passée → on réutilise les buckets calculés.
    _Buckets buckets;
    if (identical(_bucketCacheKey, all) && _bucketCacheValue != null) {
      buckets = _bucketCacheValue!;
    } else {
      buckets = _Buckets.fromAll(all);
      _bucketCacheKey = all;
      _bucketCacheValue = buckets;
    }
    final Map<String, Channel> byId = buckets.byId;
    final List<Channel> sports = buckets.sports;
    final List<Channel> movies = buckets.movies;
    final List<Channel> series = buckets.series;
    final List<Channel> kids = buckets.kids;
    final List<Channel> news = buckets.news;
    final List<Channel> music = buckets.music;
    final List<Channel> docs = buckets.docs;
    final List<Channel> live = buckets.live;

    // Hero : prend la 1ʳᵉ chaîne avec un logo (plus joli) sinon la 1ʳᵉ
    final Channel hero =
        all.firstWhere((Channel c) => c.hasLogo, orElse: () => all.first);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        const SliverPadding(padding: EdgeInsets.only(top: 64)),

        // ----- Bannière "Reprendre où tu t'es arrêté" -----
        //  Hook Model — Continue Watching. Visible seulement si la
        //  dernière session date de < 60 min (sinon SizedBox.shrink).
        const SliverToBoxAdapter(child: ResumeBanner()),

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

        // ----- Catégories rondes (Apple TV chips) -----
        //  Raccourcis directs : Football, Jeunesse, Divertissement,
        //  Info, Doc. Pour l'utilisateur qui sait DÉJÀ ce qu'il
        //  cherche, plus rapide que de scanner les rails par genre.
        //  Football ouvre une vue dédiée regroupée par pays.
        SliverToBoxAdapter(child: _buildCategoryChips()),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),

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

        // ----- LIVE MAINTENANT SUR TES FAVORIS -----
        //  Hook Model — variable reward + investment :
        //  chaque seconde un programme différent passe sur tes
        //  chaînes favorites. Chaque ouverture = nouveauté.
        const SliverToBoxAdapter(child: LiveNowFavoritesRow()),

        // ----- En direct maintenant (Live Now) -----
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

        // ----- Rangées par genre, triées par affinité (Hook Model) -----
        //  Le genre dominant remonte en haut. On rebuilds quand le
        //  service notifie un changement (nouveaux scores).
        ..._buildGenreSlivers(<ChannelGenre, List<Channel>>{
          ChannelGenre.sports: sports,
          ChannelGenre.movies: movies,
          ChannelGenre.series: series,
          ChannelGenre.kids: kids,
          ChannelGenre.news: news,
          ChannelGenre.music: music,
          ChannelGenre.documentary: docs,
        }),

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

  /// Construit les slivers de rangées par genre, triés par affinité
  /// (genre le plus regardé en premier). Si aucune affinité encore
  /// calculée → ordre par défaut "marketing" (Sports → Films → Séries…).
  /// Le ListenableBuilder repaint quand AffinityService notifie.
  List<Widget> _buildGenreSlivers(Map<ChannelGenre, List<Channel>> byGenre) {
    // Ordre par défaut (avant qu'on ait des données utilisateur)
    const List<ChannelGenre> defaultOrder = <ChannelGenre>[
      ChannelGenre.sports,
      ChannelGenre.movies,
      ChannelGenre.series,
      ChannelGenre.kids,
      ChannelGenre.news,
      ChannelGenre.music,
      ChannelGenre.documentary,
    ];

    final List<ChannelGenre> ranked = AffinityService.instance.rankedGenres;
    final List<ChannelGenre> order = <ChannelGenre>[];
    // 1) Genres rankés par affinité d'abord (dans l'ordre du service)
    for (final ChannelGenre g in ranked) {
      if (defaultOrder.contains(g) && !order.contains(g)) {
        order.add(g);
      }
    }
    // 2) Puis le reste dans l'ordre par défaut
    for (final ChannelGenre g in defaultOrder) {
      if (!order.contains(g)) order.add(g);
    }

    return <Widget>[
      for (final ChannelGenre g in order)
        if ((byGenre[g] ?? <Channel>[]).isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PremiumRow(
                title: _genreLabel(g),
                subtitle: '${(byGenre[g] ?? <Channel>[]).length} chaînes',
                channels: (byGenre[g] ?? <Channel>[]).take(20).toList(),
                onChannelTap: _onChannelTap,
                onChannelLongPress: _onChannelLongPress,
                onSeeAll: () => _openSection(_genreLabel(g), g),
              ),
            ),
          ),
    ];
  }

  String _genreLabel(ChannelGenre g) {
    switch (g) {
      case ChannelGenre.sports:
        return 'Sports en direct';
      case ChannelGenre.movies:
        return 'Films';
      case ChannelGenre.series:
        return 'Séries';
      case ChannelGenre.kids:
        return 'Jeunesse';
      case ChannelGenre.news:
        return 'Info & Actualités';
      case ChannelGenre.music:
        return 'Musique';
      case ChannelGenre.documentary:
        return 'Documentaires';
      case ChannelGenre.entertainment:
        return 'Divertissement';
      case ChannelGenre.international:
        return 'International';
      case ChannelGenre.adult:
        return 'Adulte';
      case ChannelGenre.other:
        return 'Autres';
    }
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

  // ----- Bottom Nav (Phase 1.0b standards OTT) -----
  //
  //    0 = Home      (l'ecran actuel : hero + rails)
  //    1 = Trending  (provisoire : Cinema qui contient la VOD)
  //    2 = Live      (sport et chaines live)
  //    3 = Favoris   (liste personnelle)
  //    4 = Profil    (settings + guide TV + cast + about)
  //
  //  Le contenu reel des sections Trending et Live sera retravaille
  //  en Phase 1.0c (vrais rails de discovery au lieu d'un push de
  //  grille generique). Pour 1.0b, on garde le pattern push existant
  //  qui marche deja, pour ne pas mettre le doigt dans le contenu.

  void _onNavTap(int index) {
    setState(() => _currentNavIndex = index);
    switch (index) {
      case 0:
        break; // deja sur l'accueil
      case 1:
        // Trending : provisoire = Cinema (VOD). Sera un vrai rail
        // de discovery en Phase 1.0c.
        _openSection('Trending', ChannelGenre.movies).then((_) => _resetNav());
      case 2:
        // Live : sport en direct + (a terme) chaines live. Pour
        // l'instant on route sport, c'est l'usage majoritaire.
        _openSection('Live', ChannelGenre.sports).then((_) => _resetNav());
      case 3:
        _openFavorites().then((_) => _resetNav());
      case 4:
        Navigator.of(context)
            .push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileScreen(),
              ),
            )
            .then((_) => _resetNav());
    }
  }

  /// Ouvre la section Adulte UNIQUEMENT après authentification
  /// biométrique réussie. Sinon toast d'erreur et abandon.
  Future<void> _openAdultGuarded() async {
    final bool supported = await BiometricAuth.instance.isSupported();
    if (!supported) {
      // Device sans capteur ni PIN système (très rare) : on tolère
      // l'accès sans bloquer — c'est le comportement local_auth par
      // défaut. À l'usage, sur tous les Android récents l'auth
      // est disponible et bloquera.
      if (!mounted) return;
      await _openSection('Adulte', ChannelGenre.adult);
      return;
    }
    final bool authed = await BiometricAuth.instance.authenticate(
      reason: 'Accède à la section Adulte',
    );
    if (!authed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surfaceHigh,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
          content: Text(
            'Authentification annulée — section Adulte verrouillée',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    await _openSection('Adulte', ChannelGenre.adult);
  }

  void _resetNav() {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      // Reset sur 0 = Home (cf. nav Phase 1.0b).
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

// ============================================================
//  _Buckets — Résultat memoïsé du bucketing par genre
// ============================================================
//  Construit en O(N) une fois par liste reçue, puis réutilisé
//  par les rebuilds suivants tant que la liste est la même
//  instance (identity check côté caller).
// ============================================================

class _Buckets {
  _Buckets({
    required this.byId,
    required this.sports,
    required this.movies,
    required this.series,
    required this.kids,
    required this.news,
    required this.music,
    required this.docs,
    required this.live,
  });

  final Map<String, Channel> byId;
  final List<Channel> sports;
  final List<Channel> movies;
  final List<Channel> series;
  final List<Channel> kids;
  final List<Channel> news;
  final List<Channel> music;
  final List<Channel> docs;
  final List<Channel> live;

  factory _Buckets.fromAll(List<Channel> all) {
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
    return _Buckets(
      byId: byId,
      sports: sports,
      movies: movies,
      series: series,
      kids: kids,
      news: news,
      music: music,
      docs: docs,
      live: live,
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

// L'ancien _RefreshButton de la AppBar est retire en Phase 1.0b
// (top bar minimal). Le rafraichissement automatique des playlists
// vieilles se fait deja au boot via PlaylistRepository.refreshStale ;
// un pull-to-refresh sur Home pourra etre ajoute en Phase 1.0c
// quand le scaffold de discovery sera reecrit.
