// =========================================================
//  red_room_home_screen.dart — Accueil premium Red Room (VIP)
// =========================================================
//  UI/UX SEULEMENT. On ne touche NI au backend, NI aux URLs de
//  stream, NI au player : on réutilise `playChannel`, `VodRepository`,
//  `MoviesScreen`, etc. Cet écran ne fait QUE la présentation.
//
//  Structure (style Netflix / Apple TV / Max) :
//    Header fixe → Hero vedette → rails horizontaux → bottom nav 5 onglets.
//
//  Palette imposée par la demande produit (marque Red Room). Exception
//  assumée à la règle "couleurs via AppColors" : ce sont les hex exacts
//  de la charte Red Room, isolés ici dans des constantes locales.
// =========================================================

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../about/data/update_checker.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../channels/presentation/search_screen.dart';
import '../../channels/presentation/widgets/source_choice_sheet.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/domain/vod_movie.dart';
import '../../vod/presentation/movies_screen.dart';

// ----- Charte Red Room -----
const Color _kBg = Color(0xFF050505);
const Color _kSurface = Color(0xFF15151C);
const Color _kRed = Color(0xFFE50914);
const Color _kNavBg = Color(0xFF101014);
const Color _kTextSecondary = Color(0xFF8A8A8A);
const Color _kInactive = Color(0xFF777777);

// =========================================================
//  Coque : 5 onglets (Accueil / Live / Films / VIP / Profil)
// =========================================================
class RedRoomHomeScreen extends StatefulWidget {
  const RedRoomHomeScreen({super.key});

  @override
  State<RedRoomHomeScreen> createState() => _RedRoomHomeScreenState();
}

class _RedRoomHomeScreenState extends State<RedRoomHomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Auto-update : on vérifie la release Red Room au démarrage et on
    // propose le téléchargement DIRECT si une nouvelle build est dispo.
    unawaited(_checkUpdate());
  }

  Future<void> _checkUpdate() async {
    final UpdateInfo? info = await UpdateChecker.instance.check();
    if (!mounted || info == null || !info.hasUpdate) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showUpdateDialog(info);
    });
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text(
          'Mise à jour disponible',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Une nouvelle version de Red Room est prête. Télécharge-la pour '
          'profiter des dernières améliorations.',
          style: TextStyle(color: _kTextSecondary, height: 1.4),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              UpdateChecker.instance.acknowledge(info);
              Navigator.of(ctx).pop();
            },
            child: const Text('Plus tard', style: TextStyle(color: _kInactive)),
          ),
          FilledButton(
            onPressed: () {
              UpdateChecker.instance.acknowledge(info);
              unawaited(launchUrl(
                Uri.parse(info.releaseUrl),
                mode: LaunchMode.externalApplication,
              ));
              Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: IndexedStack(
        index: _tab,
        children: const <Widget>[
          _HomeTab(),
          _LiveGridPage(),
          MoviesScreen(),
          _FavoritesPage(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        index: _tab,
        onTap: (int i) => setState(() => _tab = i),
      ),
    );
  }
}

// =========================================================
//  Modèle de tuile générique (chaîne live OU film VOD)
// =========================================================
class _Tile {
  const _Tile({
    required this.id,
    required this.title,
    required this.image,
    required this.onTap,
  });
  final String id;
  final String title;
  final String? image;
  final VoidCallback onTap;
}

/// Nettoie un titre technique en titre lisible :
///  - retire extensions (.mp4/.m3u8/.mkv…)
///  - remplace _ . - par des espaces, écrase les espaces multiples
///  - met une majuscule par mot
///  - coupe à 24 caractères
String _pretty(String raw) {
  String s = raw.trim();
  s = s.replaceAll(
      RegExp(r'\.(mp4|m3u8|mkv|avi|ts|mov|flv)$', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'[._\-]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return 'Sans titre';
  s = s
      .split(' ')
      .map((String w) =>
          w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
  if (s.length > 24) s = '${s.substring(0, 24).trimRight()}…';
  return s;
}

// =========================================================
//  Onglet ACCUEIL — Header + Hero + rails
// =========================================================
class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  late Future<List<VodMovie>> _moviesFuture;

  @override
  void initState() {
    super.initState();
    // VOD chargé une fois (catalogue Cinéma). Best-effort : si pas de VOD,
    // la liste est vide et on s'appuie sur les chaînes live.
    _moviesFuture = VodRepository.instance.fetchMovies();
  }

  void _playMovie(VodMovie m) {
    playChannel(
      context,
      Channel(
        id: m.id,
        name: m.name,
        category: m.category,
        streamUrl: m.streamUrl,
        isLive: false,
        logoUrl: m.posterUrl,
      ),
      overrideTitle: m.name,
    );
  }

  _Tile _fromChannel(Channel c, List<Channel> zap) => _Tile(
        id: c.id,
        title: _pretty(c.cleanName),
        image: c.hasLogo ? c.logoUrl : null,
        onTap: () => playChannel(context, c, zapPlaylist: zap),
      );

  _Tile _fromMovie(VodMovie m) => _Tile(
        id: m.id,
        title: _pretty(m.name),
        image: m.posterUrl,
        onTap: () => _playMovie(m),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const _Header(),
        Expanded(
          child: StreamBuilder<List<Channel>>(
            stream: PlaylistRepository.instance.channelsStream,
            initialData: PlaylistRepository.instance.currentChannels,
            builder: (BuildContext context,
                AsyncSnapshot<List<Channel>> csnap) {
              final List<Channel> all = csnap.data ?? const <Channel>[];
              final List<Channel> live =
                  all.where((Channel c) => c.isLive).toList();
              return FutureBuilder<List<VodMovie>>(
                future: _moviesFuture,
                builder: (BuildContext context,
                    AsyncSnapshot<List<VodMovie>> msnap) {
                  final List<VodMovie> movies =
                      msnap.data ?? const <VodMovie>[];
                  return _buildBody(all, live, movies);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
      List<Channel> all, List<Channel> live, List<VodMovie> movies) {
    if (all.isEmpty && movies.isEmpty) return const _RedRoomEmpty();

    // Index id → chaîne (pour résoudre "récemment regardé").
    final Map<String, Channel> byId = <String, Channel>{
      for (final Channel c in all) c.id: c,
    };
    final List<Channel> recent = RecentlyWatchedRepository.instance.current
        .map((String id) => byId[id])
        .whereType<Channel>()
        .toList();
    final Set<String> favIds = FavoritesRepository.instance.current;
    final List<Channel> favs =
        all.where((Channel c) => favIds.contains(c.id)).toList();

    // Vedette : un film avec affiche en priorité, sinon une chaîne live.
    final VodMovie? heroMovie = movies.where((VodMovie m) =>
            (m.posterUrl ?? '').isNotEmpty).cast<VodMovie?>().firstWhere(
          (VodMovie? m) => true,
          orElse: () => movies.isNotEmpty ? movies.first : null,
        );
    final _Tile? hero = heroMovie != null
        ? _fromMovie(heroMovie)
        : (live.isNotEmpty ? _fromChannel(live.first, live) : null);

    final List<Widget> rails = <Widget>[];
    if (hero != null) {
      rails.add(_Hero(
        tile: hero,
        isLive: heroMovie == null,
      ));
    }
    if (recent.isNotEmpty) {
      rails.add(_rail('Continuer à regarder',
          recent.map((Channel c) => _fromChannel(c, recent)).toList()));
    }
    if (live.isNotEmpty) {
      rails.add(_rail('En direct maintenant',
          live.take(18).map((Channel c) => _fromChannel(c, live)).toList()));
    }
    if (movies.isNotEmpty) {
      rails.add(_rail('Nouveautés VIP',
          movies.take(18).map(_fromMovie).toList()));
    }
    if (live.length > 18) {
      rails.add(_rail(
          'Tendances',
          live
              .skip(18)
              .take(18)
              .map((Channel c) => _fromChannel(c, live))
              .toList()));
    }
    if (movies.length > 8) {
      rails.add(_rail('Films',
          movies.reversed.take(18).map(_fromMovie).toList()));
    }
    if (favs.isNotEmpty) {
      rails.add(_rail('Favoris',
          favs.map((Channel c) => _fromChannel(c, favs)).toList()));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: rails,
    );
  }

  Widget _rail(String title, List<_Tile> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int i) =>
                _PosterCard(tile: tiles[i]),
          ),
        ),
      ],
    );
  }
}

// =========================================================
//  Header fixe (72 px) — logo + recherche + profil
// =========================================================
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 72,
        color: _kBg,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            const Text(
              'RED ROOM',
              style: TextStyle(
                color: _kRed,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'VIP',
                style: TextStyle(
                  color: _kTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.search_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.person_outline_rounded,
                  color: Colors.white),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
//  Hero vedette (look cinéma, coins droits)
// =========================================================
class _Hero extends StatelessWidget {
  const _Hero({required this.tile, required this.isLive});
  final _Tile tile;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Fond
          if ((tile.image ?? '').isNotEmpty)
            CachedNetworkImage(
              imageUrl: tile.image!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: _kSurface),
              errorWidget: (_, __, ___) => Container(color: _kSurface),
            )
          else
            Container(color: _kSurface),
          // Dégradé noir en bas
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.transparent, Colors.transparent, _kBg],
                stops: <double>[0.0, 0.45, 1.0],
              ),
            ),
          ),
          // Contenu
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _badge('VIP', _kRed),
                    const SizedBox(width: 8),
                    _badge(isLive ? 'LIVE' : 'NEW',
                        isLive ? _kRed : Colors.white24),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  tile.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    ElevatedButton.icon(
                      onPressed: tile.onTap,
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: const Text('Regarder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 10),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        FavoritesRepository.instance.toggle(tile.id);
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(const SnackBar(
                            backgroundColor: _kSurface,
                            behavior: SnackBarBehavior.floating,
                            content: Text('Ajouté à tes favoris'),
                          ));
                      },
                      icon: const Icon(Icons.add_rounded, size: 22),
                      label: const Text('Favoris'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// =========================================================
//  Carte poster 2:3 (rail + grilles)
// =========================================================
class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.tile, this.width = 120});
  final _Tile tile;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Material(
                color: _kSurface,
                child: InkWell(
                  onTap: tile.onTap,
                  child: (tile.image ?? '').isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: tile.image!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              const ColoredBox(color: _kSurface),
                          errorWidget: (_, __, ___) => _fallback(),
                        )
                      : _fallback(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tile.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    final String s = tile.title.trim();
    return Center(
      child: Text(
        s.isNotEmpty ? s[0].toUpperCase() : '•',
        style: const TextStyle(
          color: _kRed,
          fontSize: 30,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// =========================================================
//  Onglet LIVE — grille complète (réservée à cette page)
// =========================================================
class _LiveGridPage extends StatelessWidget {
  const _LiveGridPage();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const _SimpleTitleBar(title: 'Live'),
        Expanded(
          child: StreamBuilder<List<Channel>>(
            stream: PlaylistRepository.instance.channelsStream,
            initialData: PlaylistRepository.instance.currentChannels,
            builder: (BuildContext context,
                AsyncSnapshot<List<Channel>> snap) {
              final List<Channel> live = (snap.data ?? const <Channel>[])
                  .where((Channel c) => c.isLive)
                  .toList();
              if (live.isEmpty) return const _RedRoomEmpty();
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.52,
                ),
                itemCount: live.length,
                itemBuilder: (BuildContext context, int i) {
                  final Channel c = live[i];
                  return _PosterCard(
                    width: double.infinity,
                    tile: _Tile(
                      id: c.id,
                      title: _pretty(c.cleanName),
                      image: c.hasLogo ? c.logoUrl : null,
                      onTap: () =>
                          playChannel(context, c, zapPlaylist: live),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// =========================================================
//  Onglet VIP — favoris
// =========================================================
class _FavoritesPage extends StatelessWidget {
  const _FavoritesPage();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const _SimpleTitleBar(title: 'VIP · Favoris'),
        Expanded(
          child: StreamBuilder<Set<String>>(
            stream: FavoritesRepository.instance.favoritesStream,
            initialData: FavoritesRepository.instance.current,
            builder: (BuildContext context,
                AsyncSnapshot<Set<String>> fsnap) {
              final Set<String> favIds = fsnap.data ?? <String>{};
              final List<Channel> favs = PlaylistRepository
                  .instance.currentChannels
                  .where((Channel c) => favIds.contains(c.id))
                  .toList();
              if (favs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'Aucun favori pour le moment.\nAppuie sur ♥ sur un contenu pour le retrouver ici.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _kTextSecondary, height: 1.5),
                    ),
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.52,
                ),
                itemCount: favs.length,
                itemBuilder: (BuildContext context, int i) {
                  final Channel c = favs[i];
                  return _PosterCard(
                    width: double.infinity,
                    tile: _Tile(
                      id: c.id,
                      title: _pretty(c.cleanName),
                      image: c.hasLogo ? c.logoUrl : null,
                      onTap: () =>
                          playChannel(context, c, zapPlaylist: favs),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// =========================================================
//  Barre de titre simple (Live / VIP)
// =========================================================
class _SimpleTitleBar extends StatelessWidget {
  const _SimpleTitleBar({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 64,
        color: _kBg,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// =========================================================
//  Bottom nav (5 onglets)
// =========================================================
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onTap});
  final int index;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kNavBg,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              _item(0, Icons.home_rounded, 'Accueil'),
              _item(1, Icons.live_tv_rounded, 'Live'),
              _item(2, Icons.movie_rounded, 'Films'),
              _item(3, Icons.workspace_premium_rounded, 'VIP'),
              _item(4, Icons.person_rounded, 'Profil'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, String label) {
    final bool active = i == index;
    final Color color = active ? _kRed : _kInactive;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================
//  État vide (aucune source)
// =========================================================
class _RedRoomEmpty extends StatelessWidget {
  const _RedRoomEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.lock_clock_rounded, size: 56, color: _kTextSecondary),
            const SizedBox(height: 14),
            const Text(
              'Aucun contenu pour le moment',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajoute ta source (codes Xtream ou lien M3U) pour charger '
              'tes chaînes et tes films.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextSecondary, height: 1.5, fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => showSourceChoiceSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter ma source'),
              style: FilledButton.styleFrom(
                backgroundColor: _kRed,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
