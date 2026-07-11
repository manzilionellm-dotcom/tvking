// =========================================================
//  category_browser_view.dart — Navigation par CATÉGORIES
// =========================================================
//  Le client navigue EXACTEMENT comme dans sa playlist : on respecte
//  les catégories d'origine (`group-title` M3U / `category_name`
//  Xtream) ET LEUR ORDRE D'ORIGINE — aucune reclassification ni tri
//  maison. Si le M3U commence par l'Afrique, l'app commence par
//  l'Afrique. Trois niveaux, propres et évidents (façon TiviMate) :
//
//    Niveau 0 — FILTRES (barre du haut)
//      « Tout · TV · Films · Séries · Adultes »
//      Sépare proprement le direct, le cinéma, les séries et l'adulte
//      (détection auto via ChannelClassifier). La barre n'affiche que
//      les onglets réellement présents dans la playlist.
//
//    Niveau 1 — LISTE DES CATÉGORIES (dans l'ordre de la playlist)
//      « FR| FRANCE SPORT VIP » … 161
//      « FR| CINÉMA HD/4K »     …  40
//      (le chiffre = nombre de chaînes dans la catégorie)
//
//    Niveau 2 — LISTE DES CHAÎNES de la catégorie choisie
//      logo + nom propre, on tape → lecture.
//
//  Virtualisé (ListView.builder) → fluide même avec des milliers de
//  catégories/chaînes. Aucune dépendance au cast.
// =========================================================

import 'package:flutter/material.dart';

import '../../../../core/flavor/flavor.dart';
import '../../../../core/i18n/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/haptics/haptics.dart';
import '../../../channels/domain/channel.dart';
import '../../../channels/data/recently_watched_repository.dart';
import '../../../channels/data/watch_history_repository.dart';
import '../../../country_home/presentation/widgets/channel_logo.dart';
import '../../../player/presentation/play_channel.dart';
import '../../../playlists/data/favorites_repository.dart';

/// Grands « rayons » de contenu, pour la barre de filtres du haut.
/// Tout ce qui n'est ni film, ni série, ni adulte tombe dans [tv]
/// (le direct : chaînes, sport, info, jeunesse, musique…).
enum _Bucket {
  tv(Icons.live_tv_rounded),
  films(Icons.movie_outlined),
  series(Icons.video_library_outlined),
  adult(Icons.no_adult_content_rounded);

  const _Bucket(this.icon);
  final IconData icon;

  /// Libellé traduit du rayon (TV · Cinéma · Série · Adulte).
  String label(BuildContext context) {
    switch (this) {
      case _Bucket.tv:
        return context.l10n.catFilterTv;
      case _Bucket.films:
        return context.l10n.catFilterMovies;
      case _Bucket.series:
        return context.l10n.catFilterSeries;
      case _Bucket.adult:
        return context.l10n.catFilterAdult;
    }
  }
}

/// Range une catégorie dans un rayon à partir de son genre détecté.
/// On s'appuie sur le classifier partagé, puis on rattrape le cas très
/// courant des rayons « VOD » (que le classifier ne capte pas) : on les
/// met en Séries s'ils mentionnent une série, sinon en Films.
_Bucket _bucketOf(String category) {
  switch (ChannelClassifier.classifyGenre('', category)) {
    case ChannelGenre.movies:
      return _Bucket.films;
    case ChannelGenre.series:
      return _Bucket.series;
    case ChannelGenre.adult:
      return _Bucket.adult;
    default:
      final String t = category.toLowerCase();
      if (t.contains('vod')) {
        return t.contains('seri') ? _Bucket.series : _Bucket.films;
      }
      return _Bucket.tv;
  }
}

/// Variante CONTENU-AWARE : détecte le rayon « Adulte » même quand le
/// group-title est générique. Une catégorie bascule en Adulte si son nom
/// est adulte OU si une part notable (≥ 40 %) de ses chaînes l'est — cas
/// fréquent des bouquets VOD X où seul le NOM des chaînes trahit le
/// contenu (le group-title, lui, reste neutre). Ça fait apparaître le
/// rayon Adulte là où la détection par nom de catégorie le ratait.
_Bucket _bucketOfCategory(String category, List<Channel> channels) {
  if (ChannelClassifier.classifyGenre('', category) == ChannelGenre.adult) {
    return _Bucket.adult;
  }
  if (channels.isNotEmpty) {
    int adult = 0;
    for (final Channel c in channels) {
      if (c.genre == ChannelGenre.adult) adult++;
    }
    if (adult * 100 >= channels.length * 40) return _Bucket.adult;
  }
  return _bucketOf(category);
}

class CategoryBrowserView extends StatefulWidget {
  const CategoryBrowserView({super.key, required this.channels});

  /// Toutes les chaînes de la playlist active, DANS L'ORDRE de la
  /// playlist (le repository les renvoie triées par ordre d'insertion).
  final List<Channel> channels;

  @override
  State<CategoryBrowserView> createState() => _CategoryBrowserViewState();
}

class _CategoryBrowserViewState extends State<CategoryBrowserView> {
  /// Catégorie ouverte (`null` = on est sur la liste des catégories).
  String? _selected;

  /// Rayon actif (TV / Cinéma / Série / Adulte). `null` au tout début
  /// = pas encore choisi → on prend le 1er rayon présent (plus de bouton
  /// « Tout » : il embrouillait, demande client). Toujours un rayon
  /// sélectionné, bien séparé et lisible.
  _Bucket? _bucket;

  /// Cache MAC id→chaîne pour le rail « Récemment regardées ». Reconstruit
  /// seulement quand la liste de chaînes change de référence (pas à chaque
  /// tap de filtre) → évite de re-parcourir 20 000+ chaînes pour rien.
  Map<String, Channel>? _byIdCache;
  List<Channel>? _byIdFor;

  Map<String, Channel> _channelsById() {
    if (!identical(_byIdFor, widget.channels)) {
      _byIdCache = <String, Channel>{
        for (final Channel c in widget.channels) c.id: c,
      };
      _byIdFor = widget.channels;
    }
    return _byIdCache!;
  }

  /// Rail horizontal des dernières chaînes regardées (max 10), façon
  /// « Continuer à regarder » des grandes apps. Se met à jour en direct
  /// (stream) et ne montre QUE des chaînes présentes dans la liste active.
  Widget _buildRecentRail() {
    return StreamBuilder<List<String>>(
      stream: RecentlyWatchedRepository.instance.stream,
      initialData: RecentlyWatchedRepository.instance.current,
      builder: (BuildContext context, AsyncSnapshot<List<String>> snap) {
        final List<String> ids = snap.data ?? const <String>[];
        if (ids.isEmpty) return const SizedBox.shrink();
        final Map<String, Channel> byId = _channelsById();
        final List<Channel> recent = <Channel>[];
        for (final String id in ids) {
          final Channel? c = byId[id];
          if (c != null) {
            recent.add(c);
            if (recent.length >= 10) break;
          }
        }
        if (recent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.history_rounded,
                      size: 16, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.homeRecentlyWatched,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int i) {
                  return _RecentCard(
                    channel: recent[i],
                    onTap: () => playChannel(
                      context,
                      recent[i],
                      zapPlaylist: widget.channels,
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: AppColors.surface),
          ],
        );
      },
    );
  }

  /// Temps de visionnage par chaîne sur 30 jours, calculé UNE SEULE fois
  /// (la requête SQLite ne dépend pas du filtre courant). En mode Privé
  /// le tracking est désactivé → ce Future renvoie une map vide et on
  /// bascule sur le repli « tendances du jour ».
  late final Future<Map<String, int>> _topFuture =
      WatchHistoryRepository.instance.watchTimeByChannel(days: 30);

  /// Rail « 🔥 Top 10 » : les chaînes les plus regardées (classement réel
  /// par temps de visionnage). Quand l'historique est vide — nouvel
  /// utilisateur OU mode Privé où l'on ne piste rien — on complète par une
  /// sélection « tendances du jour » déterministe (qui tourne chaque jour)
  /// pour que le rail reste vivant et accrocheur. La pastille de rang
  /// numéroté est LE secret « preuve sociale » des apps US premium.
  Widget _buildTopRail() {
    return FutureBuilder<Map<String, int>>(
      future: _topFuture,
      builder: (BuildContext context, AsyncSnapshot<Map<String, int>> snap) {
        final List<Channel> top = _computeTop(snap.data ?? const <String, int>{});
        if (top.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.local_fire_department_rounded,
                      size: 16, color: AppColors.live),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.sectionTop10Today,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: top.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int i) {
                  return _TopCard(
                    channel: top[i],
                    rank: i + 1,
                    onTap: () => playChannel(
                      context,
                      top[i],
                      zapPlaylist: widget.channels,
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: AppColors.surface),
          ],
        );
      },
    );
  }

  /// Construit la liste du Top 10 : d'abord les chaînes RÉELLEMENT les
  /// plus regardées (temps de visionnage décroissant), puis complément
  /// « tendances du jour » si on n'atteint pas 10.
  List<Channel> _computeTop(Map<String, int> watchTime) {
    final Map<String, Channel> byId = _channelsById();
    final List<Channel> top = <Channel>[];
    final Set<String> used = <String>{};

    // 1) Classement réel par temps de visionnage (quand on a des données).
    final List<MapEntry<String, int>> ranked = watchTime.entries
        .where((MapEntry<String, int> e) =>
            e.value > 0 && byId.containsKey(e.key))
        .toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value));
    for (final MapEntry<String, int> e in ranked) {
      top.add(byId[e.key]!);
      used.add(e.key);
      if (top.length >= 10) return top;
    }

    // 2) Complément « tendances du jour » : sélection déterministe qui
    //    tourne chaque jour parmi les chaînes éligibles. AUCUNE donnée en
    //    dur : ce sont LES chaînes du client, simplement réordonnées par
    //    un décalage basé sur la date. On évite le rayon adulte hors mode
    //    Privé (où, lui, tout est adulte par nature).
    final bool allowAdult = FlavorConfig.current.adultOnly;
    final List<Channel> pool = <Channel>[
      for (final Channel c in widget.channels)
        if (!used.contains(c.id) &&
            (allowAdult || c.genre != ChannelGenre.adult))
          c,
    ];
    if (pool.isEmpty) return top;
    final int dayIndex =
        DateTime.now().difference(DateTime(2026)).inDays.abs();
    final int start = dayIndex % pool.length;
    for (int k = 0; k < pool.length && top.length < 10; k++) {
      top.add(pool[(start + k) % pool.length]);
    }
    return top;
  }

  /// Regroupe les chaînes par catégorie BRUTE (group-title) en
  /// CONSERVANT l'ordre d'apparition — des catégories ET des chaînes.
  /// (LinkedHashMap : l'ordre des clés = ordre de 1re apparition.)
  Map<String, List<Channel>> _grouped() {
    // Libellé traduit pour les chaînes sans catégorie dans la playlist.
    final String noCat = context.l10n.sectionOthers;
    final Map<String, List<Channel>> map = <String, List<Channel>>{};
    for (final Channel c in widget.channels) {
      final String raw = c.category.trim();
      final String cat = raw.isEmpty ? noCat : raw;
      (map[cat] ??= <Channel>[]).add(c);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Channel>> grouped = _grouped();
    final bool inCategory =
        _selected != null && grouped.containsKey(_selected);

    // On intercepte le « retour » système pour remonter d'abord de la
    // liste des chaînes vers la liste des catégories (au lieu de quitter).
    return PopScope<Object?>(
      canPop: !inCategory,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && inCategory) setState(() => _selected = null);
      },
      child: inCategory
          ? _buildChannelList(_selected!, grouped[_selected]!)
          : _buildCategoryList(grouped),
    );
  }

  // ----- Niveau 1 : la liste des catégories (+ barre de filtres) -----
  Widget _buildCategoryList(Map<String, List<Channel>> grouped) {
    if (grouped.isEmpty) {
      return Center(
        child: Text(
          context.l10n.catNoneInPlaylist,
          style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 14, color: AppColors.textSecondary),
        ),
      );
    }

    // ORDRE NATIF : on garde l'ordre d'apparition des catégories dans la
    // playlist (PAS de tri alphabétique). On calcule le rayon de chaque
    // catégorie une seule fois, et les rayons réellement présents.
    final List<String> allCats = grouped.keys.toList();
    final Map<String, _Bucket> catBucket = <String, _Bucket>{
      for (final String c in allCats) c: _bucketOfCategory(c, grouped[c]!),
    };
    final Set<_Bucket> present = catBucket.values.toSet();

    // Rayons présents, dans un ordre fixe et lisible (TV → Cinéma →
    // Série → Adulte). L'adulte reste un rayon À PART, jamais mélangé
    // au cinéma (demande client).
    final List<_Bucket> ordered =
        _Bucket.values.where(present.contains).toList();

    // Rayon effectif : celui choisi s'il est présent, sinon le 1er.
    final _Bucket effective =
        (_bucket != null && present.contains(_bucket)) ? _bucket! : ordered.first;

    // Catégories visibles = celles du rayon actif (plus de « Tout »).
    final List<String> cats =
        allCats.where((String c) => catBucket[c] == effective).toList();

    return Column(
      children: <Widget>[
        // Rayon « 🔥 Top 10 » : preuve sociale en tête d'accueil (secret
        // des apps US premium). Classement réel par temps de visionnage,
        // avec repli « tendances du jour » pour ne jamais être vide.
        _buildTopRail(),
        // Rayon « Récemment regardées » : rail horizontal élégant des
        // dernières chaînes ouvertes par le client (max 10). Disparaît
        // tout seul s'il n'y a pas encore d'historique.
        _buildRecentRail(),
        // Barre de filtres : affichée seulement s'il y a plus d'un rayon
        // (sinon inutile, on n'affiche que ce rayon unique).
        if (ordered.length > 1) _buildFilterBar(ordered, effective),
        Expanded(
          child: cats.isEmpty
              ? Center(
                  child: Text(
                    context.l10n.catEmptyShelf,
                    style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 14, color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int i) {
                    final String cat = cats[i];
                    return _CategoryRow(
                      title: cat,
                      count: grouped[cat]!.length,
                      onTap: () => setState(() => _selected = cat),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Barre horizontale de filtres : uniquement les rayons présents
  /// (TV · Cinéma · Série · Adulte). PAS de bouton « Tout » — il
  /// embrouillait (demande client). Un rayon est toujours actif.
  Widget _buildFilterBar(List<_Bucket> ordered, _Bucket effective) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        itemCount: ordered.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final _Bucket b = ordered[i];
          return _FilterChip(
            label: b.label(context),
            icon: b.icon,
            active: b == effective,
            onTap: () => setState(() => _bucket = b),
          );
        },
      ),
    );
  }

  // ----- Niveau 2 : les chaînes d'une catégorie -----
  Widget _buildChannelList(String category, List<Channel> channels) {
    return Column(
      children: <Widget>[
        // En-tête de catégorie : retour + nom + compteur.
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _selected = null),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.arrow_back_rounded, size: 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headlineMedium.copyWith(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${channels.length}',
                    style: AppTextStyles.labelSmall.copyWith(
                        fontSize: 13, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.surface),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (BuildContext context, int i) {
              final Channel c = channels[i];
              return _ChannelRow(
                channel: c,
                number: i + 1,
                onTap: () => playChannel(context, c, zapPlaylist: channels),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---- Sous-widgets ----

/// Puce de filtre (rayon). Teintée ember quand active.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? AppColors.accent : AppColors.textSecondary;
    return Material(
      color: active ? AppColors.accentSurface : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 13,
                  color: fg,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne de catégorie : dossier + nom + pastille « nombre de chaînes ».
class _CategoryRow extends StatelessWidget {
  const _CategoryRow(
      {required this.title, required this.count, required this.onTap});
  final String title;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(Icons.folder_rounded,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              // Pastille compteur.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne de chaîne : numéro + logo + nom propre. Tape → lecture.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow(
      {required this.channel, required this.number, required this.onTap});
  final Channel channel;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // Appui long = favori (geste « façon TikTok »). Investissement Hook :
        // plus l'utilisateur dépose de favoris, plus il a de raisons de revenir.
        onLongPress: () {
          Haptics.light();
          FavoritesRepository.instance.toggle(channel.id);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 30,
                child: Text(
                  '$number',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 12, color: AppColors.textTertiary),
                ),
              ),
              ChannelLogo(channel: channel, size: 44, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  channel.cleanName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 14),
                ),
              ),
              // Cœur favori : ajout/retrait DEPUIS la navigation (avant, le
              // cœur n'existait que dans le player → l'onglet Favoris restait
              // vide. Friction d'investissement n°1 levée.)
              StreamBuilder<Set<String>>(
                stream: FavoritesRepository.instance.favoritesStream,
                initialData: FavoritesRepository.instance.current,
                builder:
                    (BuildContext context, AsyncSnapshot<Set<String>> snap) {
                  final bool fav = snap.data?.contains(channel.id) ?? false;
                  return IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      fav ? Icons.favorite : Icons.favorite_border,
                      color: fav ? AppColors.accent : AppColors.textTertiary,
                      size: 20,
                    ),
                    onPressed: () {
                      Haptics.light();
                      FavoritesRepository.instance.toggle(channel.id);
                    },
                  );
                },
              ),
              const Icon(Icons.play_arrow_rounded,
                  color: AppColors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vignette compacte du rail « Récemment regardées » : logo arrondi +
/// nom propre sur une ligne. Sobre et élégant, façon carrousel premium.
class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.channel, required this.onTap});

  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ChannelLogo(channel: channel, size: 56, radius: 14),
            const SizedBox(height: 6),
            Text(
              channel.cleanName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vignette du rail « Top 10 » : comme [_RecentCard], mais avec une
/// pastille de RANG (1…10) en coin. Ce numéro est le déclencheur de
/// « preuve sociale » qui rend le classement irrésistible (façon Netflix).
class _TopCard extends StatelessWidget {
  const _TopCard({
    required this.channel,
    required this.rank,
    required this.onTap,
  });

  final Channel channel;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                ChannelLogo(channel: channel, size: 56, radius: 14),
                // Pastille de rang : numéro blanc sur fond « live » (rouge),
                // cerclé de la couleur de fond pour bien détacher du logo.
                Positioned(
                  top: -4,
                  left: -4,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.live,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.background, width: 2),
                    ),
                    child: Text(
                      '$rank',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              channel.cleanName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
