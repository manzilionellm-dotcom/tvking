// =========================================================
//  tv_films_screen.dart — Films (VOD) 10-foot
// =========================================================
//  Onglet FILMS : catalogue VOD du compte Xtream connecté. À gauche, les
//  catégories (focusables) ; à droite, une grille d'AFFICHES navigable à la
//  télécommande. OK sur un film → lecteur plein écran (ExoPlayer).
//
//  Données : VodRepository.fetchMovies() (récupéré une fois depuis Xtream et
//  mis en cache mémoire, déjà PLAFONNÉ selon la RAM de la box — anti-OOM). Le
//  filtrage par catégorie se fait sur cette liste bornée.
//
//  S'il n'y a pas de compte Xtream (que du M3U) ou pas de VOD → message clair.
// =========================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
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
  String? _selectedCat;
  List<VodMovie> _shown = const <VodMovie>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) setState(() => _loading = true);
    final List<VodMovie> movies =
        await VodRepository.instance.fetchMovies(forceRefresh: force);
    if (!mounted) return;
    // Catégories dans l'ordre d'apparition (dédup via Set).
    final List<String> cats = <String>[];
    final Set<String> seen = <String>{};
    for (final VodMovie m in movies) {
      final String c = m.category.trim().isEmpty ? 'Autres' : m.category.trim();
      if (seen.add(c)) cats.add(c);
    }
    setState(() {
      _all = movies;
      _cats = cats;
      _loading = false;
      _selectedCat ??= cats.isNotEmpty ? cats.first : null;
      _recompute();
    });
  }

  void _recompute() {
    if (_selectedCat == null) {
      _shown = _all;
      return;
    }
    _shown = _all
        .where((VodMovie m) =>
            (m.category.trim().isEmpty ? 'Autres' : m.category.trim()) ==
            _selectedCat)
        .toList(growable: false);
  }

  void _select(String cat) {
    if (_selectedCat == cat) return;
    setState(() {
      _selectedCat = cat;
      _recompute();
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

  void _play(int index) {
    final List<Channel> list =
        _shown.map(_asChannel).toList(growable: false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: list, startIndex: index),
      ),
    );
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ----- Catégories (rail vertical) -----
        SizedBox(
          width: 300,
          child: ListView.builder(
            itemExtent: 46,
            itemCount: _cats.length,
            itemBuilder: (BuildContext context, int i) {
              final String cat = _cats[i];
              return _CatRow(
                label: cat,
                selected: cat == _selectedCat,
                autofocus: i == 0,
                onSelect: () => _select(cat),
                onFocused: () => _select(cat),
              );
            },
          ),
        ),
        const SizedBox(width: TvDimens.gutter),
        // ----- Grille d'affiches -----
        Expanded(
          child: GridView.builder(
            addAutomaticKeepAlives: false,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              childAspectRatio: 0.62, // affiche 2:3 + place pour le titre
              crossAxisSpacing: TvDimens.gutter,
              mainAxisSpacing: TvDimens.gutter,
            ),
            itemCount: _shown.length,
            itemBuilder: (BuildContext context, int i) => _PosterCard(
              movie: _shown[i],
              onPlay: () => _play(i),
            ),
          ),
        ),
      ],
    );
  }
}

class _CatRow extends StatelessWidget {
  const _CatRow({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onSelect,
    required this.onFocused,
  });
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelect;
  final VoidCallback onFocused;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 4),
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          if (focused) onFocused();
          final bool active = selected && !focused;
          final Color bg =
              (focused || active) ? TvTokens.sel : Colors.transparent;
          final Color fg = focused
              ? TvTokens.goldBright
              : (active ? TvTokens.text : TvTokens.muted);
          return Container(
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
              border: focused
                  ? Border.all(color: TvTokens.gold, width: TvDimens.focusOutline)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: TvDimens.body,
                  fontWeight: (focused || active)
                      ? FontWeight.w700
                      : FontWeight.w600,
                  color: fg),
            ),
          );
        },
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
