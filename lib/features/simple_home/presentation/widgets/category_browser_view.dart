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
import '../../../channels/data/category_order_store.dart';
import '../../../channels/data/hidden_categories_store.dart';
import '../../../channels/domain/channel.dart';
import '../../../channels/data/recently_watched_repository.dart';
import '../../../channels/data/watch_history_repository.dart';
import '../../../channels/presentation/widgets/live_now_favorites_row.dart';
import '../../../country_home/presentation/widgets/channel_logo.dart';
import '../../../player/presentation/play_channel.dart';
import '../../../playlists/data/favorites_repository.dart';
import '../../../security/data/parental_controls.dart';
import '../../../playlists/data/playlist_repository.dart';
import '../../../playlists/data/remote_source_repository.dart';
import '../../../vod/data/playback_position_repository.dart';
import '../../../vod/presentation/cinema_screen.dart';

/// Nombre de colonnes ADAPTATIF pour les listes verticales (catégories et
/// chaînes) : calculé depuis la LARGEUR RÉELLE au lieu d'être figé à 1
/// colonne « portrait ». Une ligne pleine largeur est parfaite sur un
/// téléphone en portrait (≈ 360–430 dp) mais s'étire de façon absurde en
/// paysage ou sur tablette. Cible ≈ 400 dp par tuile — en dessous de
/// 800 dp de large on garde EXACTEMENT le rendu portrait actuel (1
/// colonne), au-delà on passe à 2, 3… (plafonné à 4 pour ne jamais avoir
/// de tuiles écrasées sur un très grand écran).
int _adaptiveColumns(double width, {double targetTileWidth = 400}) =>
    (width ~/ targetTileWidth).clamp(1, 4).toInt();

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

  /// Groupe (catégorie) actuellement « saisi » pour être déplacé (null=aucun).
  /// APPUI LONG sur un groupe → on l'attrape (rebond + flèches dorées ▲▼) pour
  /// le faire monter/descendre (ex. mettre « Angleterre » tout en haut).
  /// L'ordre est PERSISTÉ (CategoryOrderStore) et partagé partout.
  String? _reorderCat;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    CategoryOrderStore.instance.ensureLoaded();
    CategoryOrderStore.instance.addListener(_onOrderChanged);
    // ignore: discarded_futures
    HiddenCategoriesStore.instance.ensureLoaded();
    HiddenCategoriesStore.instance.addListener(_onOrderChanged);
    // MODE ENFANTS : quand le réglage bascule (depuis les Réglages), le
    // rayon Adulte doit apparaître/disparaître immédiatement — même
    // écoute que côté TV (tv_live_screen).
    ParentalControls.instance.kidsMode.addListener(_onOrderChanged);
  }

  @override
  void dispose() {
    CategoryOrderStore.instance.removeListener(_onOrderChanged);
    HiddenCategoriesStore.instance.removeListener(_onOrderChanged);
    ParentalControls.instance.kidsMode.removeListener(_onOrderChanged);
    super.dispose();
  }

  void _onOrderChanged() {
    if (mounted) setState(() {});
  }

  void _beginReorder(String cat) {
    Haptics.light();
    setState(() => _reorderCat = cat);
  }

  void _endReorder() {
    if (_reorderCat == null) return;
    setState(() => _reorderCat = null);
  }

  /// MASQUE le groupe (le client ne veut pas le voir) — persisté, réversible.
  void _hideCat(String cat) {
    Haptics.light();
    // ignore: discarded_futures
    HiddenCategoriesStore.instance.hide(cat);
    _endReorder();
  }

  /// Feuille « Catégories masquées » : liste les groupes cachés avec un bouton
  /// pour les RÉ-AFFICHER (rien n'est perdu, tout est réversible).
  void _openHiddenSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: ListenableBuilder(
            listenable: HiddenCategoriesStore.instance,
            builder: (BuildContext ctx, Widget? _) {
              final List<String> hidden =
                  HiddenCategoriesStore.instance.hidden.toList()..sort();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      'Catégories masquées',
                      style: AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (hidden.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text('Aucune catégorie masquée.',
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 13,
                              color: AppColors.textSecondary)),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: <Widget>[
                          for (final String c in hidden)
                            ListTile(
                              leading: Icon(Icons.folder_off_rounded,
                                  color: AppColors.textTertiary, size: 20),
                              title: Text(c,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyMedium),
                              trailing: TextButton(
                                onPressed: () => HiddenCategoriesStore.instance
                                    .unhide(c),
                                child: const Text('Afficher'),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Déplace le groupe à [index] de [dir] rang dans [visibleOrdered], puis
  /// PERSISTE : les groupes visibles réordonnés d'abord, suivis des autres
  /// groupes déjà classés (préservés) → ordre partagé cohérent partout.
  void _moveReorder(List<String> visibleOrdered, int index, int dir) {
    final int next = index + dir;
    if (next < 0 || next >= visibleOrdered.length) return;
    final List<String> reordered = List<String>.from(visibleOrdered);
    final String tmp = reordered[index];
    reordered[index] = reordered[next];
    reordered[next] = tmp;
    Haptics.light();
    final List<String> prev = CategoryOrderStore.instance.order;
    final Set<String> vis = reordered.toSet();
    final List<String> merged = <String>[
      ...reordered,
      ...prev.where((String c) => !vis.contains(c)),
    ];
    // ignore: discarded_futures
    CategoryOrderStore.instance.setOrder(merged);
  }

  /// Construit une ligne de groupe réordonnable (capture propre de l'index).
  Widget _categoryRowWidget(
      List<String> cats, int i, Map<String, List<Channel>> grouped) {
    final String cat = cats[i];
    final bool reordering = _reorderCat == cat;
    return Padding(
      key: ValueKey<String>(cat),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: _CategoryRow(
        title: cat,
        count: grouped[cat]!.length,
        onTap: () {
          if (reordering) {
            _endReorder();
          } else {
            setState(() => _selected = cat);
          }
        },
        reordering: reordering,
        canMoveUp: reordering && i > 0,
        canMoveDown: reordering && i < cats.length - 1,
        onLongPress: () => _beginReorder(cat),
        onMoveUp: () => _moveReorder(cats, i, -1),
        onMoveDown: () => _moveReorder(cats, i, 1),
        onHide: () => _hideCat(cat),
        onDoneReorder: _endReorder,
      ),
    );
  }

  /// Une « ligne » de groupes en mode multi-colonnes (paysage / tablette) :
  /// [cols] tuiles côte à côte à partir de [start], complétées par des
  /// espaces vides pour garder des largeurs égales sur la dernière ligne.
  /// À 1 colonne (téléphone portrait) on rend la tuile telle quelle —
  /// AUCUN changement visuel par rapport à avant.
  Widget _categoryRowsChunk(List<String> cats, int start, int cols,
      Map<String, List<Channel>> grouped) {
    if (cols <= 1) return _categoryRowWidget(cats, start, grouped);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int j = start; j < start + cols; j++)
          Expanded(
            child: j < cats.length
                ? _categoryRowWidget(cats, j, grouped)
                : const SizedBox.shrink(),
          ),
      ],
    );
  }

  /// TIRER-POUR-RAFRAÎCHIR : le MÊME rafraîchissement réel que le reste de
  /// l'app — 1) resynchronise la source assignée par le revendeur
  /// (RemoteSourceRepository.sync : dédupliqué, donc quasi gratuit si rien
  /// n'a changé, et récupère une source fraîchement poussée), puis
  /// 2) re-télécharge les playlists existantes (PlaylistRepository.refreshAll,
  /// le moteur historique du bouton « Actualiser »). On ATTEND la fin réelle
  /// pour que l'indicateur reflète le vrai travail ; les chaînes fraîches
  /// arrivent ensuite par channelsStream → l'accueil se reconstruit seul.
  Future<void> _refreshData() async {
    // sync() ne throw jamais (renvoie un résultat) ; refreshAll est
    // best-effort par playlist et possède son propre verrou anti-doublon.
    await RemoteSourceRepository.sync();
    await PlaylistRepository.instance.refreshAll();
  }

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

  /// Rangée « Reprendre » (Continue Watching VOD) : les films / séries
  /// commencés mais pas terminés, avec une VRAIE barre de progression, façon
  /// Netflix. Alimentée par les positions mémorisées par le lecteur
  /// (PlaybackPositionRepository). Se met à jour en direct (ChangeNotifier)
  /// et se cache toute seule si vide. C'est le hook de retour n°1
  /// (≈ 70 % des plays Netflix).
  Widget _buildResumeVodRail() {
    return ListenableBuilder(
      listenable: PlaybackPositionRepository.instance,
      builder: (BuildContext context, _) {
        final List<PlaybackPosition> items = <PlaybackPosition>[
          for (final PlaybackPosition p
              in PlaybackPositionRepository.instance.entries)
            if (p.progress > 0.02 && p.progress < 0.95) p,
        ];
        if (items.isEmpty) return const SizedBox.shrink();
        final List<PlaybackPosition> shown =
            items.length > 12 ? items.sublist(0, 12) : items;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.play_circle_fill_rounded,
                      size: 16, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.sectionResume,
                    style: AppTextStyles.headlineMedium.copyWith(
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: shown.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int i) {
                  final PlaybackPosition p = shown[i];
                  final Channel ch = Channel(
                    id: p.key,
                    name: p.name,
                    category: '',
                    streamUrl: p.streamUrl,
                    isLive: false,
                    logoUrl: p.posterUrl,
                  );
                  return _ResumeVodCard(
                    channel: ch,
                    progress: p.progress,
                    onTap: () => playChannel(context, ch),
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

  /// Rail « Top 10 » : les chaînes les plus regardées (classement réel
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
    // au cinéma (demande client). MODE ENFANTS : le rayon Adulte est
    // masqué entièrement (parité TV) — sauf en flavor Privé où tout le
    // catalogue est adulte par nature (le masquer viderait l'app).
    final bool kidsMode = ParentalControls.instance.kidsMode.value &&
        !FlavorConfig.current.adultOnly;
    final List<_Bucket> ordered = _Bucket.values
        .where((b) => present.contains(b) && !(kidsMode && b == _Bucket.adult))
        .toList();

    // Cas limite : catalogue composé UNIQUEMENT de contenu adulte + mode
    // Enfants → plus aucun rayon. Même message que « aucune catégorie »
    // plutôt qu'un crash sur ordered.first.
    if (ordered.isEmpty) {
      return Center(
        child: Text(
          context.l10n.catNoneInPlaylist,
          style: AppTextStyles.bodyMedium.copyWith(
              fontSize: 14, color: AppColors.textSecondary),
        ),
      );
    }

    // Rayon effectif : celui choisi s'il est présent (et pas masqué par
    // le mode Enfants), sinon le 1er.
    final _Bucket effective =
        (_bucket != null && ordered.contains(_bucket)) ? _bucket! : ordered.first;

    // Catégories visibles = celles du rayon actif (plus de « Tout »),
    // RÉORDONNÉES selon le choix de l'usager, puis les MASQUÉES retirées.
    final List<String> cats = HiddenCategoriesStore.instance.applyFilter(
      CategoryOrderStore.instance.applyOrder(
        allCats.where((String c) => catBucket[c] == effective).toList(),
        (String c) => c,
      ),
      (String c) => c,
    );

    // TOUT défile ensemble (un seul ListView) : les rangées d'engagement
    // en tête, puis la barre de filtres, puis les catégories. Ça évite tout
    // risque de débordement quand plusieurs rails s'empilent (petit écran,
    // power-user) ET donne un vrai accueil scrollable façon Netflix. Chaque
    // rail se cache tout seul quand il est vide (nouvel utilisateur = liste
    // de catégories seule, comme avant).
    //
    // PAYSAGE / TABLETTE : LayoutBuilder mesure la largeur réelle et les
    // groupes passent en 2–4 colonnes au lieu d'une ligne étirée sur toute
    // la largeur. Les rails horizontaux, eux, ont déjà des tuiles de
    // largeur FIXE (62/92 dp) : ils s'allongent naturellement sans jamais
    // produire de tuiles géantes — rien à changer.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final int cols = _adaptiveColumns(box.maxWidth);
        // TIRER-POUR-RAFRAÎCHIR sur le scroll principal de l'accueil.
        return RefreshIndicator(
          onRefresh: _refreshData,
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          child: ListView(
            // Parent AlwaysScrollable : le geste « tirer » doit marcher même
            // quand le contenu tient dans l'écran (petite playlist).
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.only(bottom: 16),
            children: <Widget>[
              // Rangée « Reprendre » (Continue Watching VOD) : films/séries
              // commencés, avec barre de progression. Le hook de retour n°1.
              _buildResumeVodRail(),
              // Rayon « Top 10 » : preuve sociale en tête d'accueil. Classement
              // réel par temps de visionnage, avec repli « tendances du jour ».
              _buildTopRail(),
              // Rayon « Récemment regardées » : dernières chaînes ouvertes (max 10).
              _buildRecentRail(),
              // Rangée « Favoris en direct maintenant » : les favoris qui diffusent
              // en ce moment (widget autonome, se cache s'il n'y a rien).
              const LiveNowFavoritesRow(),
              // Barre de filtres : seulement s'il y a plus d'un rayon.
              if (ordered.length > 1) _buildFilterBar(ordered, effective),
              // Rappel discret des catégories MASQUÉES + accès pour les ré-afficher.
              if (HiddenCategoriesStore.instance.count > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _openHiddenSheet,
                      icon: Icon(Icons.visibility_off_rounded,
                          size: 18, color: AppColors.textTertiary),
                      label: Text(
                        '${HiddenCategoriesStore.instance.count} masquée(s) · Gérer',
                        style: AppTextStyles.labelSmall.copyWith(
                            fontSize: 12, color: AppColors.textTertiary),
                      ),
                    ),
                  ),
                ),
              // Catégories de la playlist (ordre natif préservé), par
              // paquets de [cols] tuiles (1 = rendu portrait inchangé).
              if (cats.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      context.l10n.catEmptyShelf,
                      style: AppTextStyles.bodyMedium.copyWith(
                          fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                for (int i = 0; i < cats.length; i += cols)
                  _categoryRowsChunk(cats, i, cols, grouped),
            ],
          ),
        );
      },
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
            // CINÉMA (2026-07-17) : les rayons Films et Séries ouvrent le
            // VRAI Cinéma (catalogue d'affiches, fiches, téléchargements —
            // le même moteur que la TV) au lieu de la simple liste IPTV.
            // Le rayon TV (et Adulte) garde le comportement existant.
            onTap: () {
              if (b == _Bucket.films || b == _Bucket.series) {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CinemaScreen(
                      initialTab: b == _Bucket.films ? 0 : 1),
                ));
                return;
              }
              setState(() => _bucket = b);
            },
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
          // PAYSAGE / TABLETTE : les lignes de chaînes passent en 2–4
          // colonnes selon la largeur réelle (1 colonne = rendu portrait
          // inchangé). Toujours virtualisé : chaque item du builder est une
          // « rangée » de [cols] chaînes.
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final int cols = _adaptiveColumns(box.maxWidth);
              final int rowCount = (channels.length + cols - 1) ~/ cols;
              return ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
                itemCount: rowCount,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (BuildContext context, int r) {
                  Widget cell(int i) {
                    final Channel c = channels[i];
                    return _ChannelRow(
                      channel: c,
                      number: i + 1,
                      onTap: () =>
                          playChannel(context, c, zapPlaylist: channels),
                    );
                  }

                  if (cols <= 1) return cell(r);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (int j = r * cols; j < (r + 1) * cols; j++)
                        Expanded(
                          child: j < channels.length
                              ? cell(j)
                              : const SizedBox.shrink(),
                        ),
                    ],
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
///
/// APPUI LONG → on « attrape » le groupe (rebond + flèches dorées ▲▼) pour le
/// monter / descendre (ex. Angleterre tout en haut). Ordre partagé partout.
class _CategoryRow extends StatefulWidget {
  const _CategoryRow({
    required this.title,
    required this.count,
    required this.onTap,
    this.reordering = false,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onLongPress,
    this.onMoveUp,
    this.onMoveDown,
    this.onHide,
    this.onDoneReorder,
  });
  final String title;
  final int count;
  final VoidCallback onTap;
  final bool reordering;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onLongPress;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onHide;
  final VoidCallback? onDoneReorder;

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final Animation<double> _bounce =
      TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.05)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 28),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.05, end: 0.985)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 26),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.985, end: 1.02)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 24),
    TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.02, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 22),
  ]).animate(_bounceCtl);

  @override
  void initState() {
    super.initState();
    if (widget.reordering) _bounceCtl.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _CategoryRow old) {
    super.didUpdateWidget(old);
    if (widget.reordering && !old.reordering) _bounceCtl.forward(from: 0);
  }

  @override
  void dispose() {
    _bounceCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reordering = widget.reordering;
    final Widget tile = Material(
      color: reordering ? AppColors.royalGoldSurface : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: reordering
                ? Border.all(color: AppColors.royalGold, width: 1.4)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(Icons.folder_rounded, color: AppColors.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              if (reordering)
                _GroupReorderChevrons(
                  canUp: widget.canMoveUp,
                  canDown: widget.canMoveDown,
                  onUp: widget.onMoveUp ?? () {},
                  onDown: widget.onMoveDown ?? () {},
                  onHide: widget.onHide ?? () {},
                  onDone: widget.onDoneReorder ?? () {},
                )
              else ...<Widget>[
                // Pastille compteur.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.count}',
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
            ],
          ),
        ),
      ),
    );
    if (!reordering) return tile;
    return AnimatedBuilder(
      animation: _bounce,
      builder: (BuildContext context, Widget? child) =>
          Transform.scale(scale: _bounce.value, child: child),
      child: tile,
    );
  }
}

/// Chevrons DORÉS ▲ ▼ (+ ✓) — montent / descendent le groupe. Grisés quand
/// l'action est impossible (déjà tout en haut / tout en bas).
class _GroupReorderChevrons extends StatelessWidget {
  const _GroupReorderChevrons({
    required this.canUp,
    required this.canDown,
    required this.onUp,
    required this.onDown,
    required this.onHide,
    required this.onDone,
  });
  final bool canUp;
  final bool canDown;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onHide;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _btn(Icons.keyboard_arrow_up_rounded, true, canUp, onUp),
        _btn(Icons.keyboard_arrow_down_rounded, true, canDown, onDown),
        // MASQUER ce groupe (œil barré) — le client ne veut pas le voir.
        _btn(Icons.visibility_off_rounded, false, true, onHide),
        _btn(Icons.check_rounded, true, true, onDone),
      ],
    );
  }

  Widget _btn(IconData icon, bool gold, bool enabled, VoidCallback onTap) {
    final Color base = gold ? AppColors.royalGold : AppColors.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(icon,
            size: 26,
            color: enabled ? base : base.withValues(alpha: 0.30)),
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

/// Vignette « Reprendre » : logo + VRAIE barre de progression + nom. La
/// barre montre où en est le film/série (positions du lecteur).
class _ResumeVodCard extends StatelessWidget {
  const _ResumeVodCard({
    required this.channel,
    required this.progress,
    required this.onTap,
  });

  final Channel channel;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ChannelLogo(channel: channel, size: 88, radius: 12),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              channel.cleanName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(fontSize: 11),
            ),
          ],
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
