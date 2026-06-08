// =========================================================
//  country_home_view.dart — Accueil d'un pays "Maison Noir"
// =========================================================
//  Corps scrollable de l'écran d'une catégorie/pays, pensé seniors +
//  découverte (on cure le contenu à leur place) :
//    1. Toggle "Texte plus grand" (accessibilité).
//    2. HERO "Pour vous" — la chaîne #1 populaire (live si possible).
//    3. "Populaires en ce moment" — top par score local.
//    4. "Reprendre" — récemment regardé.
//    5. Sections par genre — ordre / visibilité / rubans pilotés par le
//       panel (HomeLayoutRepository), lignes hautes lisibles.
//    6. `trailing` — zone verrouillée Cinéma & Séries (fournie par
//       l'appelant pour conserver le verrou adulte existant).
//
//  La barre du haut (retour + pays) et la nav du bas sont fournies par
//  SimpleHomeScreen. Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/domain/channel.dart';
import '../../player/presentation/play_channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../simple_home/data/home_layout_repository.dart';
import '../data/channel_health_repository.dart';
import '../data/popularity_repository.dart';
import '../data/text_scale_repository.dart';
import 'widgets/channel_list_row.dart';
import 'widgets/hero_card.dart';
import 'widgets/popular_card.dart';
import 'widgets/resume_card.dart';

/// Correspondance clé de section → (libellé, genres regroupés).
final Map<String, (String, Set<ChannelGenre>)> _kGenreSections =
    <String, (String, Set<ChannelGenre>)>{
  HomeSectionKey.sport: ('Sport', <ChannelGenre>{ChannelGenre.sports}),
  HomeSectionKey.entertainment: (
    'Divertissement',
    <ChannelGenre>{
      ChannelGenre.entertainment,
      ChannelGenre.music,
      ChannelGenre.documentary,
    }
  ),
  HomeSectionKey.info: ('Info', <ChannelGenre>{ChannelGenre.news}),
  HomeSectionKey.kids: ('Enfants', <ChannelGenre>{ChannelGenre.kids}),
  HomeSectionKey.general: (
    'Général',
    <ChannelGenre>{ChannelGenre.other, ChannelGenre.international}
  ),
};

class CountryHomeView extends StatelessWidget {
  const CountryHomeView({super.key, required this.channels, this.trailing});

  /// Chaînes de CE pays (déjà filtrées par l'appelant).
  final List<Channel> channels;

  /// Zone optionnelle ajoutée en bas (ex. Cinéma verrouillé).
  final Widget? trailing;

  void _play(BuildContext context, Channel c, List<Channel> list) {
    PopularityRepository.instance.recordOpen(c.id);
    playChannel(context, c, zapPlaylist: list);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TextScaleRepository.instance,
      builder: (BuildContext context, _) {
        final double scale = TextScaleRepository.instance.factor;
        return StreamBuilder<Set<String>>(
          stream: FavoritesRepository.instance.favoritesStream,
          initialData: FavoritesRepository.instance.current,
          builder: (BuildContext context, AsyncSnapshot<Set<String>> favSnap) {
            final Set<String> favs =
                favSnap.data ?? FavoritesRepository.instance.current;
            return StreamBuilder<List<String>>(
              stream: RecentlyWatchedRepository.instance.stream,
              initialData: RecentlyWatchedRepository.instance.current,
              builder:
                  (BuildContext context, AsyncSnapshot<List<String>> recSnap) {
                return ListenableBuilder(
                  // Re-trie quand la disposition (panel) OU la santé des
                  // chaînes (sondes) change → les mortes reculent en direct.
                  listenable: Listenable.merge(<Listenable>[
                    HomeLayoutRepository.instance,
                    ChannelHealthRepository.instance,
                  ]),
                  builder: (BuildContext context, _) => _build(
                    context,
                    scale,
                    favs,
                    recSnap.data ?? const <String>[],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _build(BuildContext context, double scale, Set<String> favs,
      List<String> recentIds) {
    // Populaires, puis on pousse les chaînes mortes au fond (santé).
    final List<Channel> popular = ChannelHealthRepository.instance.sortByHealth(
        PopularityRepository.instance.getPopularChannels(channels, top: 12));
    final Map<String, Channel> byId = <String, Channel>{
      for (final Channel c in channels) c.id: c,
    };
    final List<Channel> recent = <Channel>[
      for (final String id in recentIds)
        if (byId[id] != null) byId[id]!,
    ];

    final List<Widget> items = <Widget>[];

    // 1) Réglage accessibilité.
    items.add(_textScaleToggle(scale));

    // 2) HERO "Pour vous".
    if (popular.isNotEmpty) {
      final Channel hero = popular.firstWhere(
        (Channel c) => c.isLive,
        orElse: () => popular.first,
      );
      items.add(_eyebrow('POUR VOUS', scale));
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        child: HeroCard(
          channel: hero,
          isFav: favs.contains(hero.id),
          scale: scale,
          onWatch: () => _play(context, hero, channels),
          onFav: () => FavoritesRepository.instance.toggle(hero.id),
        ),
      ));
    }

    // 3) Populaires en ce moment.
    if (popular.isNotEmpty) {
      items.add(_sectionTitle('Populaires en ce moment', scale));
      items.add(_horizontal(
        height: 150 * scale,
        children: <Widget>[
          for (int i = 0; i < popular.length; i++)
            PopularCard(
              channel: popular[i],
              rank: i + 1,
              watchers: _watchers(popular[i], i + 1),
              scale: scale,
              onTap: () => _play(context, popular[i], popular),
            ),
        ],
      ));
    }

    // 4) Reprendre.
    if (recent.isNotEmpty) {
      items.add(_sectionTitle('Reprendre', scale));
      items.add(_horizontal(
        height: 132 * scale,
        children: <Widget>[
          for (final Channel c in recent.take(12))
            ResumeCard(
              channel: c,
              scale: scale,
              onTap: () => _play(context, c, recent),
            ),
        ],
      ));
    }

    // 5) Sections par genre, dans l'ordre piloté par le panel.
    final List<String> order =
        HomeLayoutRepository.instance.orderedVisibleKeys(kDefaultHomeOrder);
    for (final String key in order) {
      final (String, Set<ChannelGenre>)? def = _kGenreSections[key];
      if (def == null) continue; // recent/favorites/cinema gérés ailleurs
      final List<Channel> inGenre = channels
          .where((Channel c) => def.$2.contains(c.genre))
          .toList();
      if (inGenre.isEmpty) continue;
      final List<Channel> top = ChannelHealthRepository.instance.sortByHealth(
          PopularityRepository.instance.getPopularChannels(inGenre, top: 12));
      final String ribbon =
          HomeLayoutRepository.instance.config(key)?.ribbon ?? '';
      items.add(_sectionTitle(def.$1, scale, ribbon: ribbon));
      for (final Channel c in top) {
        items.add(ChannelListRow(
          channel: c,
          isFav: favs.contains(c.id),
          scale: scale,
          onTap: () => _play(context, c, inGenre),
          onFav: () => FavoritesRepository.instance.toggle(c.id),
        ));
      }
    }

    // 6) Zone verrouillée (Cinéma & Séries) fournie par l'appelant.
    if (trailing != null) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: trailing!,
      ));
    }

    items.add(const SizedBox(height: 20));

    return ColoredBox(
      color: AppColors.maisonBg,
      child: ListView(
        padding: const EdgeInsets.only(top: 8),
        physics: const BouncingScrollPhysics(),
        children: items,
      ),
    );
  }

  // ---- Sous-widgets ----

  Widget _textScaleToggle(double scale) {
    final bool big = TextScaleRepository.instance.isBig;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: big ? AppColors.black7Red : AppColors.maisonSurfaceHigh,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => TextScaleRepository.instance.toggle(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.text_fields_rounded,
                      size: 18 * scale,
                      color: big ? AppColors.maisonBg : AppColors.maisonInk),
                  SizedBox(width: 6 * scale),
                  Text(
                    'Texte plus grand',
                    style: AppTextStyles.maisonLabel.copyWith(
                      fontSize: 12 * scale,
                      color: big ? AppColors.maisonBg : AppColors.maisonInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _eyebrow(String text, double scale) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Text(text,
            style: AppTextStyles.maisonLabel.copyWith(
                color: AppColors.black7Red, fontSize: 12 * scale)),
      );

  Widget _sectionTitle(String text, double scale, {String ribbon = ''}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Row(
          children: <Widget>[
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTextStyles.maisonSection.copyWith(fontSize: 20 * scale)),
            ),
            if (ribbon.isNotEmpty) ...<Widget>[
              SizedBox(width: 8 * scale),
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 8 * scale, vertical: 3 * scale),
                decoration: BoxDecoration(
                  color: AppColors.liveRed.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(ribbon,
                    style: AppTextStyles.maisonLabel.copyWith(
                        color: AppColors.liveRed, fontSize: 10 * scale)),
              ),
            ],
          ],
        ),
      );

  Widget _horizontal({required double height, required List<Widget> children}) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, int i) => children[i],
      ),
    );
  }

  /// Compteur "X regardent" — déterministe (stable), décroît avec le rang.
  int _watchers(Channel c, int rank) {
    final int jitter = c.id.hashCode.abs() % 140;
    final int base = 1600 - rank * 110 + jitter;
    return base < 30 ? 30 + jitter : base;
  }
}
