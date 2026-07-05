// =========================================================
//  tv_films_screen.dart — Films (VOD) 10-foot, présentation « Netflix »
// =========================================================
//  Onglet FILMS refondu façon Netflix :
//    • en HAUT : une grande AFFICHE VEDETTE (le dernier film vu, sinon le
//      premier du catalogue) avec titre, année/note et bouton ▶ Regarder ;
//    • en dessous : des RANGÉES HORIZONTALES défilables au D-pad —
//      d'abord « Derniers vus » (mémoire locale), puis une rangée PAR
//      catégorie du catalogue.
//
//  PERF (box RAM limitée) : tout est PARESSEUX. La liste verticale des
//  rangées est un ListView.builder (seules les rangées visibles existent),
//  et chaque rangée est un ListView.builder horizontal (seules les affiches
//  visibles sont construites). Les affiches passent par CachedNetworkImage
//  avec memCacheWidth (déjà la règle dans l'app). Le catalogue vient de
//  VodRepository (cache mémoire PLAFONNÉ selon la RAM — inchangé).
//
//  Données : VodRepository.fetchMovies(). S'il n'y a pas de VOD → message.
//  Zéro contact avec le lecteur vidéo (on pousse TvPlayerScreen comme avant).
// =========================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../vod/data/recent_vod_repository.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/data/vod_watchlist_repository.dart';
import '../../vod/domain/vod_movie.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../../vod/data/vod_download_service.dart';
import 'tv_components.dart';
import 'tv_player_screen.dart';

class TvFilmsScreen extends StatefulWidget {
  const TvFilmsScreen({super.key});

  @override
  State<TvFilmsScreen> createState() => _TvFilmsScreenState();
}

class _TvFilmsScreenState extends State<TvFilmsScreen> {
  bool _loading = true;
  List<VodMovie> _all = const <VodMovie>[];
  List<String> _cats = const <String>[];
  Map<String, List<VodMovie>> _byCat = const <String, List<VodMovie>>{};
  List<VodMovie> _recent = const <VodMovie>[];
  List<VodMovie> _watchlist = const <VodMovie>[];
  // Ids présents dans « Ma Liste » (repère rapide pour l'affichage du ✓).
  Set<String> _inList = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) setState(() => _loading = true);
    final List<VodMovie> movies =
        await VodRepository.instance.fetchMovies(forceRefresh: force);
    await RecentVodRepository.instance.load();
    await VodWatchlistRepository.instance.load();
    if (!mounted) return;
    // Groupement UNE fois par catégorie (ordre d'apparition). Les listes
    // référencent les mêmes objets VodMovie → pas de duplication mémoire.
    final List<String> cats = <String>[];
    final Map<String, List<VodMovie>> byCat = <String, List<VodMovie>>{};
    for (final VodMovie m in movies) {
      final String c = m.category.trim().isEmpty ? 'Autres' : m.category.trim();
      final List<VodMovie>? existing = byCat[c];
      if (existing == null) {
        cats.add(c);
        byCat[c] = <VodMovie>[m];
      } else {
        existing.add(m);
      }
    }
    setState(() {
      _all = movies;
      _cats = cats;
      _byCat = byCat;
      _recent = RecentVodRepository.instance.items;
      _watchlist = VodWatchlistRepository.instance.items;
      _inList = _watchlist.map((VodMovie m) => m.id).toSet();
      _loading = false;
    });
  }

  /// Ajoute/retire [m] de « Ma Liste » (par profil) et rafraîchit l'affichage.
  Future<void> _toggleList(VodMovie m) async {
    await VodWatchlistRepository.instance.toggle(m);
    if (!mounted) return;
    setState(() {
      _watchlist = VodWatchlistRepository.instance.items;
      _inList = _watchlist.map((VodMovie e) => e.id).toSet();
    });
  }

  /// Adapte un film en Channel pour le lecteur (ExoPlayer lit l'URL du fichier).
  Channel _asChannel(VodMovie m) => Channel(
        id: m.id,
        name: m.name,
        category: m.category,
        streamUrl: m.streamUrl,
        isLive: false,
        logoUrl: m.posterUrl,
      );

  /// Lance la lecture de [list] à partir de [index], et mémorise le film dans
  /// « Derniers vus ». Au retour du lecteur, on rafraîchit la rangée.
  void _play(List<VodMovie> list, int index) {
    RecentVodRepository.instance.add(list[index]);
    final List<Channel> channels =
        list.map(_asChannel).toList(growable: false);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => TvPlayerScreen(channels: channels, startIndex: index),
        ))
        .then((_) {
      if (mounted) {
        setState(() => _recent = RecentVodRepository.instance.items);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // Squelette « respirant » : la structure de la page (vedette +
      // rangées) apparaît tout de suite — perception de fluidité premium.
      return const TvSkeletonRails(withHero: true, rails: 2);
    }
    if (_all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.movie_outlined, size: 52, color: TvTokens.mutedDim),
            const SizedBox(height: 14),
            Text(context.l10n.tvNavFilms,
                style: TvTokens.display(26, color: TvTokens.text)),
            const SizedBox(height: 8),
            Text(
                'Aucun film pour le moment.\n(Source sans VOD, ou compte M3U sans films.)',
                textAlign: TextAlign.center,
                style: TvTokens.ui(15, color: TvTokens.mutedDim)),
          ],
        ),
      );
    }

    // Film mis en avant : le dernier vu, sinon le premier du catalogue.
    final VodMovie hero = _recent.isNotEmpty ? _recent.first : _all.first;

    // Rangées, dans l'ordre façon Netflix : Ma Liste (si non vide), puis
    // Derniers vus, puis une rangée par catégorie. On les assemble en une
    // liste ordonnée → pas d'arithmétique d'index fragile.
    final List<({String title, List<VodMovie> movies})> rails =
        <({String title, List<VodMovie> movies})>[
      if (_watchlist.isNotEmpty) (title: context.l10n.tvMyList, movies: _watchlist),
      if (_recent.isNotEmpty) (title: context.l10n.tvRailRecent, movies: _recent),
      for (final String cat in _cats)
        (title: cat, movies: _byCat[cat] ?? const <VodMovie>[]),
    ];

    return ListView.builder(
      // La VEDETTE occupe l'index 0, les rangées suivent → tout est lazy.
      addAutomaticKeepAlives: false,
      itemCount: 1 + rails.length,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return _HeroBanner(
            movie: hero,
            autofocus: true,
            inList: _inList.contains(hero.id),
            onPlay: () => _play(<VodMovie>[hero], 0),
            onToggleList: () => _toggleList(hero),
          );
        }
        final ({String title, List<VodMovie> movies}) rail = rails[i - 1];
        return _Rail(
          title: rail.title,
          movies: rail.movies,
          inList: _inList,
          onPlay: (int j) => _play(rail.movies, j),
          onToggleList: (int j) => _toggleList(rail.movies[j]),
        );
      },
    );
  }
}

/// Grande affiche vedette (haut de page) : visuel + titre + méta + ▶ Regarder.
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.movie,
    required this.onPlay,
    required this.inList,
    required this.onToggleList,
    this.autofocus = false,
  });

  final VodMovie movie;
  final VoidCallback onPlay;
  final bool inList;
  final VoidCallback onToggleList;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final String meta = <String>[
      if (movie.year != null && movie.year!.isNotEmpty) movie.year!,
      if (movie.rating != null && movie.rating!.isNotEmpty)
        '★ ${movie.rating}',
      if (movie.category.trim().isNotEmpty) movie.category.trim(),
    ].join('   ·   ');

    return Container(
      height: 210,
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[TvTokens.sel, TvTokens.card],
        ),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: <Widget>[
          // ----- Infos + bouton -----
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    movie.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.display(28, color: TvTokens.text),
                  ),
                  if (meta.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(14, color: TvTokens.muted)),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      _HeroButton(
                        icon: Icons.play_arrow_rounded,
                        label: context.l10n.tvWatch,
                        autofocus: autofocus,
                        primary: true,
                        onSelect: onPlay,
                      ),
                      const SizedBox(width: 12),
                      // « Ma Liste » : ajoute/retire le film vedette (par profil).
                      _HeroButton(
                        icon: inList
                            ? Icons.check_rounded
                            : Icons.add_rounded,
                        label: inList ? context.l10n.tvInMyList : context.l10n.tvMyList,
                        primary: false,
                        onSelect: onToggleList,
                      ),
                      const SizedBox(width: 12),
                      // « Télécharger » : garde le film pour le regarder hors-ligne.
                      _HeroDownloadButton(movie: movie),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // ----- Visuel (affiche à droite, plein cadre) -----
          SizedBox(
            width: 340,
            child: _HeroPoster(url: movie.posterUrl),
          ),
        ],
      ),
    );
  }
}

/// Bouton d'action de la vedette (▶ Regarder / + Ma Liste), focusable.
/// Bouton « Télécharger » de la vedette : écoute VodDownloadService pour
/// afficher l'état en direct (Télécharger → % → ✓ Téléchargé). OK :
/// démarre / met en pause / (si terminé) ne refait rien.
class _HeroDownloadButton extends StatelessWidget {
  const _HeroDownloadButton({required this.movie});
  final VodMovie movie;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VodDownloadService.instance,
      builder: (BuildContext context, _) {
        final VodDownload? d = VodDownloadService.instance.byId(movie.id);
        IconData icon = Icons.download_rounded;
        String label = context.l10n.tvDownload;
        VoidCallback onSelect =
            () => VodDownloadService.instance.downloadMovie(movie);
        if (d != null) {
          switch (d.status) {
            case VodDownloadStatus.done:
              icon = Icons.download_done_rounded;
              label = context.l10n.tvDownloaded;
              onSelect = () {};
            case VodDownloadStatus.downloading:
              icon = Icons.pause_rounded;
              label = context.l10n.tvPercent((d.progress * 100).round());
              onSelect = () => VodDownloadService.instance.pause(movie.id);
            case VodDownloadStatus.paused:
            case VodDownloadStatus.error:
            case VodDownloadStatus.queued:
              icon = Icons.download_rounded;
              label = context.l10n.tvResume;
              onSelect = () => VodDownloadService.instance.resume(movie.id);
          }
        }
        return _HeroButton(
          icon: icon,
          label: label,
          primary: false,
          onSelect: onSelect,
        );
      },
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.primary = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? TvTokens.gold
            : (primary ? TvTokens.badgeBg : TvTokens.card);
        final Color fg = focused
            ? const Color(0xFF1A1206)
            : (primary ? TvTokens.goldBright : TvTokens.text);
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: primary ? TvTokens.gold : TvTokens.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: fg)),
            ],
          ),
        );
      },
    );
  }
}

class _HeroPoster extends StatelessWidget {
  const _HeroPoster({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      color: TvTokens.tile,
      child: Center(
        child: Icon(Icons.movie_rounded, size: 44, color: TvTokens.mutedDim),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      memCacheWidth: 480,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

/// Une RANGÉE horizontale d'affiches (titre + liste paresseuse), façon Netflix.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.title,
    required this.movies,
    required this.inList,
    required this.onPlay,
    required this.onToggleList,
  });

  final String title;
  final List<VodMovie> movies;
  final Set<String> inList;
  final void Function(int index) onPlay;
  final void Function(int index) onToggleList;

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.ui(13,
                  weight: FontWeight.w700,
                  color: TvTokens.mutedDim,
                  spacing: 1.6),
            ),
          ),
          SizedBox(
            height: 218,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              addAutomaticKeepAlives: false,
              itemExtent: 142,
              itemCount: movies.length,
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _PosterCard(
                  movie: movies[i],
                  inList: inList.contains(movies[i].id),
                  onPlay: () => onPlay(i),
                  onToggleList: () => onToggleList(i),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Affiche d'un film (poster 2:3) + titre, focusable. OK = lecture.
class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.movie,
    required this.inList,
    required this.onPlay,
    required this.onToggleList,
  });
  final VodMovie movie;
  final bool inList;
  final VoidCallback onPlay;
  final VoidCallback onToggleList;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: onPlay,
      // Appui LONG sur OK = ajouter/retirer de « Ma Liste » (façon Netflix).
      onLongPress: onToggleList,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _poster(),
                  // Pastille ✓ quand le film est dans « Ma Liste ».
                  if (inList)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: TvTokens.gold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded,
                            size: 15, color: Color(0xFF1A1206)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              movie.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: TvDimens.caption,
                  fontWeight: FontWeight.w600,
                  color: TvTokens.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _poster() {
    final Widget fallback = Container(
      color: TvTokens.tile,
      child: Center(
        child: Icon(Icons.movie_rounded, size: 30, color: TvTokens.mutedDim),
      ),
    );
    final String? url = movie.posterUrl;
    if (url == null || url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 300,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}
