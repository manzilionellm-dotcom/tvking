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
import '../../vod/domain/vod_movie.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
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
      _loading = false;
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
      return const Center(child: CircularProgressIndicator());
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
    final bool hasRecent = _recent.isNotEmpty;

    // Rangées : [héro] + [Derniers vus ?] + 1 rangée par catégorie.
    final int railCount = (hasRecent ? 1 : 0) + _cats.length;

    return ListView.builder(
      // La VEDETTE occupe l'index 0, les rangées suivent → tout est lazy.
      addAutomaticKeepAlives: false,
      itemCount: 1 + railCount,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return _HeroBanner(
            movie: hero,
            autofocus: true,
            onPlay: () => _play(<VodMovie>[hero], 0),
          );
        }
        int idx = i - 1;
        if (hasRecent) {
          if (idx == 0) {
            return _Rail(
              title: 'Derniers vus',
              movies: _recent,
              onPlay: (int j) => _play(_recent, j),
            );
          }
          idx -= 1;
        }
        final String cat = _cats[idx];
        final List<VodMovie> movies = _byCat[cat] ?? const <VodMovie>[];
        return _Rail(
          title: cat,
          movies: movies,
          onPlay: (int j) => _play(movies, j),
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
    this.autofocus = false,
  });

  final VodMovie movie;
  final VoidCallback onPlay;
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
                  TvFocusBuilder(
                    autofocus: autofocus,
                    scale: TvFocusScale.small,
                    onSelect: onPlay,
                    builder: (BuildContext context, bool focused) {
                      final Color bg =
                          focused ? TvTokens.gold : TvTokens.badgeBg;
                      final Color fg = focused
                          ? const Color(0xFF1A1206)
                          : TvTokens.goldBright;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius:
                              BorderRadius.circular(TvDimens.cardRadius),
                          border: Border.all(color: TvTokens.gold),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(Icons.play_arrow_rounded, color: fg, size: 24),
                            const SizedBox(width: 8),
                            Text('Regarder',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: fg)),
                          ],
                        ),
                      );
                    },
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
  const _Rail({required this.title, required this.movies, required this.onPlay});

  final String title;
  final List<VodMovie> movies;
  final void Function(int index) onPlay;

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
                  onPlay: () => onPlay(i),
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
  const _PosterCard({required this.movie, required this.onPlay});
  final VodMovie movie;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: onPlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _poster(),
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
