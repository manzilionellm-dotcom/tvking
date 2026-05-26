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
import '../../../core/branding/powered_by_marquee.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../cast/presentation/cast_button.dart';
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
  int _currentNavIndex = 1;
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
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Logo + signature discrète juste en-dessous — baseline maison
      // de couture sous le monogramme. La signature animée du pied
      // d'écran a été supprimée (effet ticker = pas premium).
      title: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BrandLogo.compact(),
          SizedBox(height: 2),
          BrandSignature(),
        ],
      ),
      actions: <Widget>[
        // Bouton Actualiser — visible, première position d'actions.
        // L'app rafraîchit déjà les playlists vieilles au démarrage,
        // mais l'utilisateur a aussi le droit de forcer manuellement.
        const _RefreshButton(),
        const CastButton(),
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

  // ----- Bottom Nav -----
  //
  //  Refonte UX :
  //    0 = Live      (sport en direct, foot principalement)
  //    1 = Live TV   (accueil = vue par défaut, ce qu'on voit déjà)
  //    2 = Cinéma    (films / VOD)
  //    3 = Séries    (séries TV)
  //    4 = Adulte    (contenu adulte ; PIN parental à ajouter plus tard)

  void _onNavTap(int index) {
    setState(() => _currentNavIndex = index);
    switch (index) {
      case 0:
        _openSection('Live', ChannelGenre.sports).then((_) => _resetNav());
      case 1:
        break; // déjà sur l'accueil Live TV
      case 2:
        _openSection('Cinéma', ChannelGenre.movies).then((_) => _resetNav());
      case 3:
        _openSection('Séries', ChannelGenre.series).then((_) => _resetNav());
      case 4:
        _openSection('Adulte', ChannelGenre.adult).then((_) => _resetNav());
    }
  }

  void _resetNav() {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      // Reset sur 1 = Live TV = accueil par défaut (cf. _currentNavIndex)
      if (mounted) setState(() => _currentNavIndex = 1);
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

// ============================================================
//  Bouton Actualiser dans l'AppBar
// ============================================================
//  Tape → refresh.all() en arrière-plan, l'icône tourne pendant
//  la sync, snackbar discret avec le résultat. L'utilisateur n'est
//  pas bloqué — il peut continuer à scroller pendant que ça
//  tourne.
// ============================================================

class _RefreshButton extends StatefulWidget {
  const _RefreshButton();

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    _spin.repeat();
    final ScaffoldMessengerState messenger =
        ScaffoldMessenger.of(context);
    try {
      final int ok = await PlaylistRepository.instance.refreshAll();
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            ok == 0
                ? 'Aucune playlist actualisée.'
                : 'Actualisé : $ok playlist(s).',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    } catch (e) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.live,
          content: Text(
            'Erreur : ${e.toString().replaceFirst('Exception: ', '')}',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      );
    } finally {
      _spin.stop();
      _spin.reset();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Actualiser les playlists',
      onPressed: _busy ? null : _refresh,
      icon: RotationTransition(
        turns: _spin,
        child: Icon(
          Icons.refresh_rounded,
          color: _busy ? AppColors.accent : null,
        ),
      ),
    );
  }
}
