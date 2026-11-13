import '../../simple_home/data/home_sections.dart';
import 'package:tv_king/core/theme/remote_palette.dart';
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
import '../data/featured_repository.dart';
import '../data/popularity_repository.dart';
import '../data/text_scale_repository.dart';
import 'widgets/channel_list_row.dart';
import 'widgets/hero_card.dart';
import 'widgets/popular_card.dart';

class CountryHomeView extends StatelessWidget {
  const CountryHomeView(
      {super.key,
      required this.channels,
      this.trailing,
      this.onPlay,
      this.television = false});

  /// Chaînes de CE pays (déjà filtrées par l'appelant).
  final List<Channel> channels;

  /// Zone optionnelle ajoutée en bas (ex. Cinéma verrouillé).
  final Widget? trailing;
  final void Function(BuildContext, Channel, List<Channel>)? onPlay;
  final bool television;

  void _play(BuildContext context, Channel c, List<Channel> list) {
    PopularityRepository.instance.recordOpen(c.id);
    if (onPlay != null) {
      onPlay!(context, c, list);
    } else {
      playChannel(context, c, zapPlaylist: list);
    }
  }

  @override
  Widget build(BuildContext context) {
    RemotePalette.watch(context);
    return ListenableBuilder(
      listenable: TextScaleRepository.instance,
      builder: (BuildContext context, _) {
        final double scale = television
            ? TextScaleRepository.instance.factor * 1.25
            : TextScaleRepository.instance.factor;
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
                    FeaturedRepository.instance,
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
    final List<Widget> items = <Widget>[];

    // 1) Réglage accessibilité.
    items.add(_textScaleToggle(scale));

    // 2) HERO : "Favori du jour" (piloté panel) s'il correspond à une
    //    chaîne d'ici, sinon le #1 populaire ("Pour vous").
    Channel? hero;
    String heroLabel = 'POUR VOUS';
    String? heroNote;
    final FeaturedRepository feat = FeaturedRepository.instance;
    if (feat.hasFeatured) {
      hero = matchFeatured(channels, feat.name);
      if (hero != null) {
        heroLabel = 'FAVORI DU JOUR';
        heroNote = feat.note.trim().isEmpty ? null : feat.note.trim();
      }
    }
    hero ??= popular.isNotEmpty
        ? popular.firstWhere((Channel c) => c.isLive,
            orElse: () => popular.first)
        : null;
    if (hero != null) {
      final Channel heroCh = hero;
      items.add(_eyebrow(heroLabel, scale));
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        child: HeroCard(
          channel: heroCh,
          label: heroLabel,
          note: heroNote,
          isFav: favs.contains(heroCh.id),
          scale: scale,
          onWatch: () => _play(context, heroCh, channels),
          onFav: () => FavoritesRepository.instance.toggle(heroCh.id),
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

    // Every supported panel section participates in order, visibility,
    // ribbon and promotion, including recent/favorites/cinema.
    final List<String> order =
        HomeLayoutRepository.instance.orderedVisibleKeys(kDefaultHomeOrder);
    for (final HomeSectionView section in buildHomeSections(
        channels: channels,
        order: order,
        config: HomeLayoutRepository.instance.config,
        favorites: favs,
        recentIds: recentIds)) {
      final Iterable<Channel> top = section.key == HomeSectionKey.recent ||
              section.key == HomeSectionKey.favorites
          ? section.channels.take(12)
          : ChannelHealthRepository.instance.sortByHealth(PopularityRepository
              .instance
              .getPopularChannels(section.channels, top: 12));
      items.add(Container(
        key: ValueKey<String>('home-section-${section.key}'),
        decoration: section.promoted
            ? BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                border:
                    Border(left: BorderSide(color: AppColors.accent, width: 3)))
            : null,
        child: Column(children: <Widget>[
          _sectionTitle(section.title, scale, ribbon: section.ribbon),
          for (final Channel c in top)
            ChannelListRow(
              key: ValueKey<String>('${section.key}-${c.id}'),
              channel: c,
              isFav: favs.contains(c.id),
              scale: scale,
              onTap: () => _play(context, c, section.channels),
              onFav: () => FavoritesRepository.instance.toggle(c.id),
            ),
        ]),
      ));
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
              padding: EdgeInsets.symmetric(
                  horizontal: 12 * scale, vertical: 8 * scale),
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
            style: AppTextStyles.maisonLabel
                .copyWith(color: AppColors.black7Red, fontSize: 12 * scale)),
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
                  style: AppTextStyles.maisonSection
                      .copyWith(fontSize: 20 * scale)),
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
