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

import '../../../core/i18n/l10n_extension.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../l10n/generated/app_localizations.dart';
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
import 'widgets/resume_card.dart';

/// Correspondance clé de section → (libellé traduit, genres regroupés).
/// Le libellé est une FONCTION de [AppLocalizations] (pas une chaîne en
/// dur) pour que les titres de sections suivent la langue du téléphone.
/// On réutilise les clés simple* déjà traduites (mêmes valeurs).
final Map<String, (String Function(AppLocalizations), Set<ChannelGenre>)>
    _kGenreSections =
    <String, (String Function(AppLocalizations), Set<ChannelGenre>)>{
  HomeSectionKey.sport: (
    (AppLocalizations l10n) => l10n.simpleSport,
    <ChannelGenre>{ChannelGenre.sports}
  ),
  HomeSectionKey.entertainment: (
    (AppLocalizations l10n) => l10n.simpleEntertainment,
    <ChannelGenre>{
      ChannelGenre.entertainment,
      ChannelGenre.music,
      ChannelGenre.documentary,
    }
  ),
  HomeSectionKey.info: (
    (AppLocalizations l10n) => l10n.simpleInfo,
    <ChannelGenre>{ChannelGenre.news}
  ),
  HomeSectionKey.kids: (
    (AppLocalizations l10n) => l10n.simpleKids,
    <ChannelGenre>{ChannelGenre.kids}
  ),
  HomeSectionKey.general: (
    (AppLocalizations l10n) => l10n.simpleGeneral,
    <ChannelGenre>{ChannelGenre.other, ChannelGenre.international}
  ),
};

class CountryHomeView extends StatelessWidget {
  const CountryHomeView(
      {super.key, required this.channels, this.trailing, this.onRetry});

  /// Action « Réessayer » de l'état vide (ré-import / rechargement). Optionnel :
  /// si null, l'état vide affiche le message sans bouton d'action.
  final VoidCallback? onRetry;

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
    // ÉTAT VIDE EXPLICITE (correctif d'audit — plainte « ça ne marche pas »
    // sans feedback) : si aucune chaîne n'est disponible (import échoué,
    // région bloquée), on n'affiche PLUS un écran quasi blanc mais un message
    // clair et actionnable (vérifier la connexion + réessayer). Sans ça,
    // l'utilisateur ne savait pas quoi faire.
    if (channels.isEmpty) {
      return _emptyState(context, scale);
    }
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
    items.add(_textScaleToggle(context, scale));

    // 2) HERO : "Favori du jour" (piloté panel) s'il correspond à une
    //    chaîne d'ici, sinon le #1 populaire ("Pour vous").
    Channel? hero;
    String heroLabel = context.l10n.heroForYou;
    String? heroNote;
    final FeaturedRepository feat = FeaturedRepository.instance;
    if (feat.hasFeatured) {
      final String q = feat.name.trim().toLowerCase();
      for (final Channel c in channels) {
        if (c.name.toLowerCase().contains(q)) {
          hero = c;
          heroLabel = context.l10n.heroFeaturedOfDay;
          heroNote = feat.note.trim().isEmpty ? null : feat.note.trim();
          break;
        }
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
      items.add(_sectionTitle(context.l10n.homePopularNow, scale));
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
      items.add(_sectionTitle(context.l10n.sectionResume, scale));
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
      final (String Function(AppLocalizations), Set<ChannelGenre>)? def =
          _kGenreSections[key];
      if (def == null) continue; // recent/favorites/cinema gérés ailleurs
      final List<Channel> inGenre = channels
          .where((Channel c) => def.$2.contains(c.genre))
          .toList();
      if (inGenre.isEmpty) continue;
      final List<Channel> top = ChannelHealthRepository.instance.sortByHealth(
          PopularityRepository.instance.getPopularChannels(inGenre, top: 12));
      final String ribbon =
          HomeLayoutRepository.instance.config(key)?.ribbon ?? '';
      items.add(_sectionTitle(def.$1(context.l10n), scale, ribbon: ribbon));
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

  /// État vide actionnable : message clair + bouton « Réessayer » (si
  /// [onRetry] fourni). Couleurs/typo via AppColors/AppTextStyles.
  Widget _emptyState(BuildContext context, double scale) {
    return ColoredBox(
      color: AppColors.maisonBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.tv_off_rounded,
                  size: 56 * scale,
                  color: AppColors.maisonInk.withValues(alpha: 0.35)),
              SizedBox(height: 16 * scale),
              Text(
                context.l10n.gridEmptyTitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.maisonSection.copyWith(fontSize: 20 * scale),
              ),
              SizedBox(height: 10 * scale),
              Text(
                context.l10n.countryHomeEmptyBody,
                textAlign: TextAlign.center,
                style: AppTextStyles.maisonProgram.copyWith(fontSize: 14 * scale),
              ),
              if (onRetry != null) ...<Widget>[
                SizedBox(height: 20 * scale),
                Material(
                  color: AppColors.black7Red,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onRetry,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 22 * scale, vertical: 12 * scale),
                      child: Text(
                        context.l10n.buttonRetry,
                        style: AppTextStyles.maisonCta.copyWith(fontSize: 14 * scale),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _textScaleToggle(BuildContext context, double scale) {
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
                    context.l10n.homeBiggerText,
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
