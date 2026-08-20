// =========================================================
//  tv_collections_screen.dart — Mes collections de favoris (TV)
// =========================================================
//  Ranger ses chaînes favorites par thème (« Sport », « Enfants »…), façon
//  listes Netflix. Écran DÉDIÉ, accessible depuis les Réglages :
//    • liste des collections (nom + nombre de chaînes) → OK = ouvrir ;
//    • création par PASTILLES de noms proposés (pas de clavier fastidieux) ;
//    • dans une collection : rangée « Dans la collection » (OK = lecture) +
//      grille « Mes favoris » avec coche (OK = ajouter/retirer).
//
//  STABILITÉ : ne touche NI au lecteur NI à l'écran Direct. Données via
//  FavoriteCollectionsRepository (SharedPreferences) et résolution des
//  chaînes par PlaylistRepository.getChannelsByExternalIds (déjà utilisée
//  par la rangée Favoris du Direct — lecture seule, bornée).
// =========================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/favorite_collections_repository.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import 'tv_player_screen.dart';
import 'tv_shell.dart';

/// Noms proposés à la création (clic direct, pas de clavier), traduits
/// dans la langue active.
List<String> _presetNames(BuildContext context) => <String>[
      context.l10n.catSport,
      context.l10n.catMovies,
      context.l10n.sectionSeries,
      context.l10n.catKids,
      context.l10n.tvCollectionsPresetNews,
      context.l10n.catMusic,
      context.l10n.sectionDocs,
      context.l10n.tvCollectionsPresetCustom1,
      context.l10n.tvCollectionsPresetCustom2,
    ];

// =========================================================
//  ÉCRAN 1 — liste des collections + création
// =========================================================
class TvCollectionsScreen extends StatefulWidget {
  const TvCollectionsScreen({super.key});

  @override
  State<TvCollectionsScreen> createState() => _TvCollectionsScreenState();
}

class _TvCollectionsScreenState extends State<TvCollectionsScreen> {
  @override
  void initState() {
    super.initState();
    FavoriteCollectionsRepository.instance.load();
    FavoritesRepository.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final FavoriteCollectionsRepository repo =
        FavoriteCollectionsRepository.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: repo,
        builder: (BuildContext context, _) {
          final List<FavoriteCollection> cols = repo.collections;
          final List<String> available = _presetNames(context)
              .where((String n) => repo.byName(n) == null)
              .toList(growable: false);
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: ListView(
              children: <Widget>[
                Text(
                  context.l10n.tvCollectionsTitle,
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: TvTokens.text),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.tvCollectionsSubtitle,
                  style: const TextStyle(fontSize: 15, color: TvTokens.muted),
                ),
                const SizedBox(height: 22),
                // ----- Collections existantes -----
                if (cols.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(context.l10n.tvCollectionsEmpty,
                        style: const TextStyle(
                            fontSize: 15, color: TvTokens.mutedDim)),
                  ),
                for (final FavoriteCollection c in cols)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TvFocusBuilder(
                      scale: TvFocusScale.large,
                      onSelect: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TvShell(
                              child:
                                  _TvCollectionDetailScreen(name: c.name)),
                        ),
                      ),
                      builder: (BuildContext context, bool focused) {
                        final Color bg =
                            focused ? TvTokens.gold : TvTokens.sel;
                        final Color fg = focused
                            ? TvTokens.onGold
                            : TvTokens.goldBright;
                        return Container(
                          width: 760,
                          decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(
                                  TvDimens.cardRadius)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 16),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.collections_bookmark_rounded,
                                  color: fg, size: 26),
                              const SizedBox(width: 12),
                              Text(c.name,
                                  style: TextStyle(
                                      fontSize: TvDimens.title,
                                      fontWeight: FontWeight.w700,
                                      color: fg)),
                              const Spacer(),
                              Text(context.l10n.channelCount(c.ids.length),
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: fg)),
                              const SizedBox(width: 10),
                              Icon(Icons.chevron_right_rounded,
                                  color: fg, size: 26),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 18),
                // ----- Création (pastilles de noms) -----
                if (available.isNotEmpty) ...<Widget>[
                  Text(
                    context.l10n.tvCollectionsCreateSection,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.mutedDim,
                        letterSpacing: 1.6),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      for (final String n in available)
                        TvFocusBuilder(
                          scale: TvFocusScale.small,
                          onSelect: () => repo.create(n),
                          builder: (BuildContext context, bool focused) {
                            final Color bg =
                                focused ? TvTokens.gold : TvTokens.card;
                            final Color fg = focused
                                ? TvTokens.onGold
                                : TvTokens.text;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(
                                    TvDimens.cardRadius),
                                border:
                                    Border.all(color: TvTokens.lineSoft),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(Icons.add_rounded,
                                      size: 18,
                                      color: focused
                                          ? fg
                                          : TvTokens.muted),
                                  const SizedBox(width: 6),
                                  Text(n,
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: fg)),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// =========================================================
//  ÉCRAN 2 — détail d'une collection
// =========================================================
class _TvCollectionDetailScreen extends StatefulWidget {
  const _TvCollectionDetailScreen({required this.name});

  final String name;

  @override
  State<_TvCollectionDetailScreen> createState() =>
      _TvCollectionDetailScreenState();
}

class _TvCollectionDetailScreenState
    extends State<_TvCollectionDetailScreen> {
  bool _confirmDelete = false;

  Future<List<Channel>> _resolve(List<String> ids) =>
      PlaylistRepository.instance.getChannelsByExternalIds(ids);

  // MÉMOÏSATION (revue perf) : les futures étaient créés INLINE dans build,
  // sous un ListenableBuilder qui rebâtit à CHAQUE toggle OK → chaque appui
  // relançait les 2 requêtes getChannelsByExternalIds et rebâtissait tout.
  // Ici on ne re-résout que si la liste d'ids a réellement changé.
  Future<List<Channel>>? _colFuture;
  String _colKey = '';

  Future<List<Channel>> _colChannels(List<String> ids) {
    final String key = ids.join('');
    if (_colFuture == null || key != _colKey) {
      _colKey = key;
      _colFuture = _resolve(ids);
    }
    return _colFuture!;
  }

  /// Favoris RÉSOLUS en état (et non FutureBuilder) : la grille passe en
  /// SliverGrid.builder — VIRTUALISÉE — au lieu d'un Wrap qui posait
  /// toutes les tuiles d'un coup (100-500 favoris possibles ≈ 100-300 ms
  /// de layout + décodage de centaines de logos à l'ouverture).
  List<Channel> _favs = const <Channel>[];
  String _favKey = '';

  void _ensureFavs(List<String> ids) {
    final String key = ids.join('');
    if (key == _favKey) return; // idempotent : sûr depuis build
    _favKey = key;
    _resolve(ids).then((List<Channel> list) {
      if (mounted && _favKey == key) setState(() => _favs = list);
    }).catchError((Object _) {
      // Échec SQLite : on garde l'affichage courant (avant, le
      // FutureBuilder absorbait l'erreur — même tolérance ici).
    });
  }

  @override
  Widget build(BuildContext context) {
    final FavoriteCollectionsRepository repo =
        FavoriteCollectionsRepository.instance;
    return SafeArea(
      child: ListenableBuilder(
        listenable: repo,
        builder: (BuildContext context, _) {
          final FavoriteCollection? col = repo.byName(widget.name);
          if (col == null) {
            // Collection supprimée → retour.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
            return const SizedBox.shrink();
          }
          final List<String> favIds =
              FavoritesRepository.instance.current.toList(growable: false);
          _ensureFavs(favIds);
          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: CustomScrollView(slivers: <Widget>[
              SliverList.list(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        col.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: TvTokens.text),
                      ),
                    ),
                    // Suppression en DEUX temps (anti-fausse-manip TV) :
                    // 1er OK → « Confirmer ? », 2e OK → suppression.
                    TvFocusBuilder(
                      scale: TvFocusScale.small,
                      onSelect: () {
                        if (_confirmDelete) {
                          repo.delete(col.name);
                        } else {
                          setState(() => _confirmDelete = true);
                        }
                      },
                      builder: (BuildContext context, bool focused) {
                        final Color bg = focused
                            ? (_confirmDelete
                                ? TvTokens.live
                                : TvTokens.gold)
                            : TvTokens.card;
                        final Color fg = focused
                            ? Colors.white
                            : (_confirmDelete
                                ? TvTokens.live
                                : TvTokens.muted);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius:
                                BorderRadius.circular(TvDimens.cardRadius),
                            border: Border.all(color: TvTokens.lineSoft),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.delete_outline_rounded,
                                  size: 20, color: fg),
                              const SizedBox(width: 6),
                              Text(
                                  _confirmDelete
                                      ? context.l10n.tvConfirmAsk
                                      : context.l10n.buttonDelete,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: fg)),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // ----- Chaînes de la collection (OK = lecture) -----
                _section(
                    context.l10n.tvCollectionsInCollection(col.ids.length)),
                const SizedBox(height: 10),
                if (col.ids.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(context.l10n.tvCollectionsEmptyDetail,
                        style: const TextStyle(
                            fontSize: 15, color: TvTokens.mutedDim)),
                  )
                else
                  SizedBox(
                    height: 128,
                    child: FutureBuilder<List<Channel>>(
                      future: _colChannels(col.ids),
                      builder: (BuildContext context,
                          AsyncSnapshot<List<Channel>> snap) {
                        final List<Channel> chans =
                            snap.data ?? const <Channel>[];
                        if (chans.isEmpty) return const SizedBox.shrink();
                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          addAutomaticKeepAlives: false,
                          itemExtent: 208,
                          itemCount: chans.length,
                          itemBuilder: (BuildContext context, int i) =>
                              Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _ChannelTile(
                              channel: chans[i],
                              onSelect: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => TvPlayerScreen(
                                      channels: chans, startIndex: i),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 22),
                // ----- Mes favoris (OK = ajouter/retirer) -----
                _section(context.l10n.tvCollectionsFavsSection),
                const SizedBox(height: 10),
                if (favIds.isEmpty)
                  Text(context.l10n.tvCollectionsNoFavorites,
                      style: const TextStyle(
                          fontSize: 15, color: TvTokens.mutedDim)),
              ]),
              // Grille VIRTUALISÉE (SliverGrid remplace l'ancien Wrap qui
              // posait tous les favoris d'un coup dans le scroll).
              if (favIds.isNotEmpty && _favs.isNotEmpty)
                SliverGrid.builder(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 208,
                    mainAxisExtent: 118,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: _favs.length,
                  itemBuilder: (BuildContext context, int i) {
                    final Channel ch = _favs[i];
                    return _ChannelTile(
                      channel: ch,
                      checked: repo.contains(col.name, ch.id),
                      onSelect: () => repo.toggle(col.name, ch.id),
                    );
                  },
                ),
            ]),
          );
        },
      ),
    );
  }

  Widget _section(String t) => Text(
        t,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: TvTokens.mutedDim,
            letterSpacing: 1.6),
      );
}

/// Vignette chaîne (logo + nom), avec coche optionnelle (appartenance).
class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.onSelect,
    this.checked,
  });

  final Channel channel;
  final VoidCallback onSelect;

  /// null = pas de coche (mode lecture) ; true/false = mode ajout/retrait.
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final Widget initials = Center(
      child: Text(channel.initials,
          style: TextStyle(
              fontSize: TvDimens.title,
              fontWeight: FontWeight.w800,
              color: TvTokens.muted)),
    );
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      onSelect: onSelect,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: (channel.logoUrl != null &&
                            channel.logoUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: channel.logoUrl!,
                            fit: BoxFit.contain,
                            memCacheWidth: 200,
                            fadeInDuration:
                                const Duration(milliseconds: 150),
                            placeholder: (_, __) =>
                                Opacity(opacity: 0.35, child: initials),
                            errorWidget: (_, __, ___) => initials)
                        : initials,
                  ),
                  const SizedBox(height: 6),
                  Text(channel.cleanName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: TvDimens.caption,
                          fontWeight: FontWeight.w600,
                          color: TvTokens.text)),
                ],
              ),
            ),
          ),
          if (checked == true)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: TvTokens.gold,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 16, color: TvTokens.onGold),
              ),
            ),
        ],
      ),
    );
  }
}
