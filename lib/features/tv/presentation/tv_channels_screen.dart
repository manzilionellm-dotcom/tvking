// =========================================================
//  tv_channels_screen.dart — « En direct » PREMIUM (3 colonnes)
// =========================================================
//  Le parcours chaînes standard du métier, dans l'identité SEVEN :
//    • gauche  : CATÉGORIES (compact, focus = pill plein, jamais de « ligne
//      jaune ») ;
//    • centre  : liste des CHAÎNES du groupe (n° + logo + nom + ★ favori +
//      programme en cours). OK À DEUX TEMPS (façon TiviMate) : 1er OK =
//      SÉLECTION (l'aperçu joue la chaîne, on reste dans la liste), 2e OK
//      sur la même chaîne = plein écran ;
//    • droite  : APERÇU de la chaîne survolée (aperçu VIDÉO en direct — muet,
//      anti-rebond, repli logo) + programme du jour (en cours + suivants,
//      façon IBO) + boutons Regarder / ★ Favori / Rechercher.
//
//  Réutilise UNIQUEMENT des briques existantes (PlaylistRepository,
//  EpgRepository, FavoritesRepository, TvChannelLogo,
//  TvPlayerScreen). Lecture = TvPlayerScreen (natif) → aucun media_kit.
//  100 % télécommande. Code SEVEN original (aucun asset/écran tiers copié).
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../channels/domain/channel_genre.dart';
import '../../epg/data/epg_repository.dart';
import '../../epg/data/short_epg_service.dart';
import '../../epg/domain/epg_program.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import '../core/tv_tokens.dart';
import 'tv_live_preview.dart';
import 'tv_player_screen.dart';
import 'tv_search_screen.dart';

const String _kAll = 'Toutes les chaînes';

class TvChannelsScreen extends StatefulWidget {
  const TvChannelsScreen({super.key});

  @override
  State<TvChannelsScreen> createState() => _TvChannelsScreenState();
}

class _TvChannelsScreenState extends State<TvChannelsScreen> {
  StreamSubscription<List<Channel>>? _chanSub;
  StreamSubscription<Set<String>>? _favSub;

  List<Channel> _all = <Channel>[];
  List<String> _cats = <String>[_kAll];

  /// Chaînes REGROUPÉES par catégorie « prettifiée », calculées UNE SEULE
  /// fois à l'ingestion. Avant, chaque tuile de catégorie (compteur) et
  /// chaque changement de groupe re-filtrait les 10 000+ chaînes en
  /// appelant `prettifyCategory` (2 RegExp/chaîne) — et comme un simple
  /// déplacement du D-pad déclenche un `setState` (aperçu), l'écran « En
  /// direct » re-scannait tout le bouquet à CHAQUE frame → saccade. Ici,
  /// compteur et liste d'un groupe sont de simples lectures O(1).
  Map<String, List<Channel>> _groups = <String, List<Channel>>{};
  String _cat = _kAll;
  List<Channel> _visible = <Channel>[];

  /// Chaîne mise en APERÇU (colonne 3). En ValueNotifier — PAS un simple
  /// champ + setState — pour que le DÉFILEMENT dans la liste ne reconstruise
  /// QUE la colonne d'aperçu (via ValueListenableBuilder), et jamais les
  /// colonnes Catégories/Chaînes. Avant, chaque déplacement du D-pad faisait
  /// un setState global → tout l'écran se reconstruisait juste pour changer
  /// l'aperçu → micro-accroc. C'est le dernier point de fluidité de l'écran.
  final ValueNotifier<Channel?> _preview = ValueNotifier<Channel?>(null);
  Set<String> _favs = <String>{};
  bool _loading = true;

  /// Aperçu vidéo actif ? Passé à `false` AVANT d'ouvrir le plein écran
  /// (le lecteur d'aperçu est libéré → jamais 2 flux ouverts en même temps),
  /// puis rétabli au retour.
  bool _previewLive = true;

  /// SÉLECTION à deux temps (façon TiviMate) : le 1er OK sur une chaîne la
  /// SÉLECTIONNE (l'aperçu la joue, on reste dans la liste) ; un 2e OK sur
  /// la MÊME chaîne ouvre le plein écran. OK sur une AUTRE chaîne = nouvelle
  /// sélection. Le simple focus (défilement) continue d'alimenter l'aperçu
  /// après l'anti-rebond — l'OK ne fait que CONFIRMER.
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _favs = FavoritesRepository.instance.current;
    _favSub = FavoritesRepository.instance.favoritesStream.listen((Set<String> s) {
      if (mounted) setState(() => _favs = s);
    });
    _ingest(PlaylistRepository.instance.currentChannels);
    _chanSub = PlaylistRepository.instance.channelsStream.listen(_ingest);
  }

  @override
  void dispose() {
    _chanSub?.cancel();
    _favSub?.cancel();
    _preview.dispose();
    super.dispose();
  }

  void _ingest(List<Channel> channels) {
    // UN SEUL passage : on prettifie chaque catégorie une fois, on construit
    // l'ordre des groupes ET on range chaque chaîne dans son groupe. Aucune
    // RegExp ne sera rejouée ensuite au rendu (compteurs et listes lisent ces
    // structures pré-calculées).
    final List<String> cats = <String>[_kAll];
    final Set<String> seen = <String>{};
    final Map<String, List<Channel>> groups = <String, List<Channel>>{};
    for (final Channel c in channels) {
      final String g = ChannelClassifier.prettifyCategory(c.category);
      if (g.isEmpty) continue;
      if (seen.add(g)) cats.add(g);
      (groups[g] ??= <Channel>[]).add(c);
    }
    if (!mounted) return;
    setState(() {
      _all = channels;
      _cats = cats;
      _groups = groups;
      if (!_cats.contains(_cat)) _cat = _kAll;
      _visible = _channelsFor(_cat);
      _preview.value ??= _visible.isNotEmpty ? _visible.first : null;
      _loading = false;
    });
  }

  /// Lecture O(1) du groupe pré-calculé (plus aucun filtrage/RegExp au rendu).
  List<Channel> _channelsFor(String cat) {
    if (cat == _kAll) return _all;
    return _groups[cat] ?? const <Channel>[];
  }

  void _selectCat(String cat) {
    setState(() {
      _cat = cat;
      _visible = _channelsFor(cat);
      _selectedId = null; // nouveau groupe → plus de chaîne « confirmée »
    });
    _preview.value = _visible.isNotEmpty ? _visible.first : null;
  }

  /// Appui OK sur une chaîne de la liste (deux temps, cf. [_selectedId]).
  void _onChannelOk(int i, Channel ch) {
    if (_selectedId == ch.id) {
      _play(i); // 2e OK sur la chaîne déjà sélectionnée → plein écran
      return;
    }
    setState(() {
      _selectedId = ch.id; // 1er OK → sélection (met à jour la pastille tuile)
    });
    _preview.value = ch; // l'aperçu la joue (démarrage immédiat)
  }

  Future<void> _play(int i) async {
    if (_visible.isEmpty) return;
    final List<Channel> channels = _visible;
    // Libère le lecteur d'APERÇU avant d'ouvrir le plein écran (l'écran reste
    // monté sous la route poussée : sans ça, les 2 flux resteraient ouverts).
    setState(() => _previewLive = false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TvPlayerScreen(channels: channels, startIndex: i),
    ));
    if (mounted) setState(() => _previewLive = true);
  }

  int _countFor(String cat) =>
      cat == _kAll ? _all.length : (_groups[cat]?.length ?? 0);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[TvTokens.bg, TvTokens.panel],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: TvTokens.gold))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(width: 300, child: _categories()),
                      const SizedBox(width: 16),
                      Expanded(flex: 5, child: _channels()),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: _previewPane()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ---- Colonne 1 : catégories ----
  Widget _categories() {
    return _panel(
      title: 'Catégories',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // BOUTON « ACCUEIL » : retour au menu principal. Indispensable au
          // TACTILE (téléphone/tablette : pas de touche Retour télécommande)
          // et plus clair pour tout le monde sur TV. TvFocusBuilder = D-pad
          // ET tap gérés.
          _HomeTile(onSelect: () => Navigator.of(context).maybePop()),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              // Extent MESURÉ (prototype) : scroll sans re-mesure par frame
              // sur des centaines de catégories possibles.
              prototypeItem: _RowTile(
                label: 'Prototype',
                count: 0,
                active: false,
                autofocus: false,
                onSelect: () {},
              ),
              itemCount: _cats.length,
              itemBuilder: (BuildContext c, int i) {
                final String cat = _cats[i];
                return _RowTile(
                  label: cat,
                  count: _countFor(cat),
                  active: cat == _cat,
                  autofocus: i == 0,
                  onSelect: () => _selectCat(cat),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- Colonne 2 : chaînes ----
  Widget _channels() {
    if (_visible.isEmpty) {
      return _panel(
        title: 'Chaînes',
        child: const Center(
          child: Text('Aucune chaîne dans ce groupe',
              style: TextStyle(color: TvTokens.muted, fontSize: 16)),
        ),
      );
    }
    return _panel(
      title: 'Chaînes · ${_visible.length}',
      child: ListView.builder(
        // Extent MESURÉ (prototype) : la liste peut porter le bouquet
        // entier (10 000+ sur « Toutes ») — sans extent, chaque frame de
        // scroll re-mesure et la position reste estimée.
        prototypeItem: _ChannelTile(
          number: 8888,
          channel: _visible.first,
          favorite: false,
          selected: false,
          autofocus: false,
          onSelect: () {},
          onFavorite: () {},
        ),
        itemCount: _visible.length,
        itemBuilder: (BuildContext c, int i) {
          final Channel ch = _visible[i];
          return Focus(
            key: ValueKey<String>('ch-${ch.id}-$i'),
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (bool has) {
              // DÉFILEMENT (hot path) : on met à jour l'aperçu SANS setState →
              // seul le ValueListenableBuilder de la colonne 3 se reconstruit,
              // les listes Catégories/Chaînes ne bougent pas → défilement lisse.
              if (has && mounted && _preview.value?.id != ch.id) {
                _preview.value = ch;
              }
            },
            child: _ChannelTile(
              number: i + 1,
              channel: ch,
              favorite: _favs.contains(ch.id),
              selected: ch.id == _selectedId,
              autofocus: i == 0,
              onSelect: () => _onChannelOk(i, ch),
              onFavorite: () => FavoritesRepository.instance.toggle(ch.id),
            ),
          );
        },
      ),
    );
  }

  // ---- Colonne 3 : aperçu ----
  Widget _previewPane() {
    return _panel(
      title: 'Aperçu',
      // Seul ce builder se reconstruit quand la chaîne focalisée change
      // (défilement) — les deux autres colonnes restent intactes.
      child: ValueListenableBuilder<Channel?>(
        valueListenable: _preview,
        builder: (BuildContext context, Channel? ch, _) {
          if (ch == null) return const SizedBox.shrink();
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Aperçu vidéo EN DIRECT de la chaîne focalisée (muet,
                // anti-rebond ~600 ms, repli logo — cf. TvLivePreview).
                // Une chaîne SÉLECTIONNÉE (OK) démarre sans anti-rebond.
                // Le cadre est FOCUSABLE : OK dessus = plein écran de la
                // chaîne affichée (même action que « Regarder »). Le tap
                // TACTILE (téléphone/tablette) est géré à l'intérieur de
                // _PreviewFrame → un seul chemin de code pour D-pad ET doigt.
                _PreviewFrame(
                  onSelect: () {
                    final int idx =
                        _visible.indexWhere((Channel x) => x.id == ch.id);
                    _play(idx < 0 ? 0 : idx);
                  },
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: TvLivePreview(
                      channel: ch,
                      enabled: _previewLive,
                      startImmediately: ch.id == _selectedId,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(ch.cleanName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(TvDimens.title,
                        weight: FontWeight.w800, color: TvTokens.text)),
                const SizedBox(height: 10),
                // « NOS ÉVÉNEMENTS » (demande client) : en-tête de section
                // au-dessus de l'EPG « En ce moment » (barre de progression)
                // + « À suivre » — même appariement que la grille TiviMate,
                // replis en cascade : EPG courte du panel, puis catégorie.
                Text('NOS ÉVÉNEMENTS',
                    style: TvTokens.ui(12,
                        weight: FontWeight.w700,
                        color: TvTokens.mutedDim,
                        spacing: 1.4)),
                const SizedBox(height: 8),
                Expanded(child: _PreviewPrograms(channel: ch)),
                const SizedBox(height: 10),
                // Boutons d'action (façon IBO) : Regarder / ★ Favori /
                // Rechercher — « Regarder » garde la place d'honneur.
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: _ActionButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'Regarder',
                        primary: true,
                        onSelect: () {
                          final int idx = _visible
                              .indexWhere((Channel x) => x.id == ch.id);
                          _play(idx < 0 ? 0 : idx);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: _favs.contains(ch.id)
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        label: 'Favori',
                        onSelect: () =>
                            FavoritesRepository.instance.toggle(ch.id),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.search_rounded,
                        label: 'Rechercher',
                        onSelect: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const TvSearchScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                if (ch.id == _selectedId) ...<Widget>[
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: double.infinity,
                    child: Text('Appuyez encore sur OK pour le plein écran',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: TvDimens.caption, color: TvTokens.muted)),
                  ),
                ],
              ],
            );
          },
        ),
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TvTokens.card.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(TvDimens.panelRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
            child: Text(title.toUpperCase(),
                style: TvTokens.ui(12,
                    weight: FontWeight.w700,
                    color: TvTokens.mutedDim,
                    spacing: 1.4)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Bouton « Accueil » en tête des catégories : quitte l'écran En direct et
/// revient au menu principal (pop de la route). Toujours visible — le
/// tactile n'a pas de touche Retour.
class _HomeTile extends StatelessWidget {
  const _HomeTile({required this.onSelect});
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color fg = focused ? TvTokens.text : TvTokens.muted;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: focused ? TvTokens.sel : TvTokens.card,
            borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
            border: Border.all(
                color: focused ? TvTokens.gold : TvTokens.hairline),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.arrow_back_rounded,
                  size: 18, color: focused ? TvTokens.gold : TvTokens.mutedDim),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Accueil',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.body,
                        fontWeight: FontWeight.w700,
                        color: fg)),
              ),
              Icon(Icons.home_rounded,
                  size: 18, color: focused ? TvTokens.gold : TvTokens.mutedDim),
            ],
          ),
        );
      },
    );
  }
}

/// Ligne de catégorie — compacte, focus = fond plein (jamais de « ligne jaune »).
class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.label,
    required this.count,
    required this.active,
    required this.autofocus,
    required this.onSelect,
  });
  final String label;
  final int count;
  final bool active;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) {
          final Color bg = focused
              ? TvTokens.sel
              : (active ? TvTokens.sel.withValues(alpha: 0.6) : Colors.transparent);
          final Color fg = (focused || active) ? TvTokens.text : TvTokens.muted;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: TvDimens.body,
                          fontWeight:
                              (focused || active) ? FontWeight.w700 : FontWeight.w600,
                          color: fg)),
                ),
                const SizedBox(width: 8),
                Text('$count',
                    style: const TextStyle(
                        fontSize: TvDimens.caption,
                        fontWeight: FontWeight.w700,
                        color: TvTokens.mutedDim)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Ligne de chaîne : n° + logo + nom + programme en cours + ★ favori.
class _ChannelTile extends StatefulWidget {
  const _ChannelTile({
    required this.number,
    required this.channel,
    required this.favorite,
    required this.selected,
    required this.autofocus,
    required this.onSelect,
    required this.onFavorite,
  });
  final int number;
  final Channel channel;
  final bool favorite;

  /// Chaîne CONFIRMÉE par un 1er OK (l'aperçu la joue) : fond marqué même
  /// sans focus — le prochain OK dessus ouvrira le plein écran.
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelect;
  final VoidCallback onFavorite;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  String? _now;
  Timer? _epgTimer;

  @override
  void initState() {
    super.initState();
    // 1) INSTANTANÉ : si le programme est déjà en cache mémoire, on l'affiche
    //    SANS aucune requête (fluidité du défilement).
    _now = EpgRepository.instance.cachedCurrent(widget.channel.id)?.title;
    // 2) Sinon, on interroge la base MAIS APRÈS un court répit (250 ms) : si
    //    la tuile est déjà recyclée (défilement rapide), on n'aura tiré
    //    aucune requête pour elle — plus de rafale SQLite pendant le scroll.
    if (_now == null) {
      _epgTimer = Timer(const Duration(milliseconds: 250), () {
        EpgRepository.instance
            .currentProgram(widget.channel.id)
            .then((EpgProgram? p) {
          if (mounted && p != null) setState(() => _now = p.title);
        });
      });
    }
  }

  @override
  void dispose() {
    _epgTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocusBuilder(
        autofocus: widget.autofocus,
        scale: TvFocusScale.small,
        onSelect: widget.onSelect,
        onLongPress: widget.onFavorite,
        builder: (BuildContext context, bool focused) {
          // Même langage visuel que les catégories : focus = fond plein,
          // sélection (sans focus) = fond atténué.
          final Color bg = focused
              ? TvTokens.sel
              : (widget.selected
                  ? TvTokens.sel.withValues(alpha: 0.6)
                  : Colors.transparent);
          const Color name = TvTokens.text;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
              border: (focused || widget.selected)
                  ? Border.all(color: TvTokens.gold)
                  : null,
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 40,
                  child: Text('${widget.number}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.mutedDim)),
                ),
                const SizedBox(width: 6),
                TvChannelLogo(
                    logoUrl: widget.channel.logoUrl,
                    label: widget.channel.name,
                    size: 42,
                    radius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(widget.channel.cleanName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: TvDimens.body,
                              fontWeight: FontWeight.w700,
                              color: name)),
                      if (_now != null)
                        Text(_now!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: TvTokens.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  widget.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 20,
                  color: widget.favorite ? TvTokens.gold : TvTokens.mutedDim,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Cadre FOCUSABLE autour de l'aperçu vidéo : OK (ou tap) = plein écran de
/// la chaîne affichée. On N'utilise PAS TvFocusBuilder ici : son AnimatedScale
/// transformerait la SurfaceView native (hybrid composition) → risque de
/// « trame fantôme » (cf. tv_live_preview / dispose natif). On se contente
/// d'un Focus + liseré or au focus, sans transformer la surface.
class _PreviewFrame extends StatefulWidget {
  const _PreviewFrame({required this.child, required this.onSelect});
  final Widget child;
  final VoidCallback onSelect;

  @override
  State<_PreviewFrame> createState() => _PreviewFrameState();
}

class _PreviewFrameState extends State<_PreviewFrame> {
  final FocusNode _node = FocusNode(debugLabel: 'preview-frame');
  bool _focused = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA ||
      k == LogicalKeyboardKey.space;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && _isOk(event.logicalKey)) {
      widget.onSelect();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      onKeyEvent: _onKey,
      onFocusChange: (bool f) => setState(() => _focused = f),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _node.requestFocus();
          widget.onSelect();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: _focused ? TvTokens.gold : TvTokens.lineSoft,
                width: _focused ? 2 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(TvDimens.cardRadius - 3),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Bouton d'action du panneau Aperçu (Regarder / Favori / Rechercher).
/// [primary] = pastille or au focus (l'action principale se voit).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? (primary ? TvTokens.gold : TvTokens.sel)
            : TvTokens.card;
        final Color fg = focused
            ? (primary ? TvTokens.onGold : TvTokens.goldBright)
            : TvTokens.muted;
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: focused ? TvTokens.gold : TvTokens.hairline),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: TvDimens.caption,
                        fontWeight: FontWeight.w800,
                        color: fg)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Programme du jour de la chaîne (façon IBO) : l'émission EN COURS en or,
/// puis les suivantes avec leurs horaires. Sans EPG → petit mot discret
/// (jamais un trou vide).
class _PreviewPrograms extends StatefulWidget {
  const _PreviewPrograms({required this.channel});

  /// Chaîne complète (et pas seulement son id) : nécessaire au REPLI
  /// « EPG courte » (ShortEpgService interroge le panel Xtream avec la
  /// chaîne entière) et au repli catégorie (`channel.category`).
  final Channel channel;

  @override
  State<_PreviewPrograms> createState() => _PreviewProgramsState();
}

class _PreviewProgramsState extends State<_PreviewPrograms> {
  List<EpgProgram> _programs = const <EpgProgram>[];
  bool _loaded = false;

  /// Anti-rebond (revue de code) : défiler 200 chaînes ne doit pas tirer
  /// 200 requêtes EPG — la requête part 400 ms après la stabilisation du
  /// focus (même esprit que l'aperçu vidéo voisin).
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(_PreviewPrograms old) {
    super.didUpdateWidget(old);
    if (old.channel.id != widget.channel.id) {
      _loaded = false;
      _programs = const <EpgProgram>[];
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        unawaited(_load());
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final String id = widget.channel.id;
    List<EpgProgram> progs = const <EpgProgram>[];
    try {
      // APPARIEMENT IDENTIQUE À LA GRILLE TiviMate : `programsBetween` par
      // `channel.id` (= tvg-id côté M3U / stream-id côté Xtream), sur une
      // FENÊTRE GLISSANTE [-1 h ; +24 h]. Capte l'émission en cours même si
      // elle a commencé la veille, et le « À suivre » même passé minuit —
      // là où l'ancien `todayPrograms` (bornes minuit→minuit) ratait le
      // programme suivant en fin de soirée.
      final DateTime now = DateTime.now();
      progs = await EpgRepository.instance.programsBetween(
        id,
        now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
      );
    } catch (_) {
      // EPG indisponible → on affichera le repli intelligent.
    }
    if (!mounted || id != widget.channel.id) return;
    // REPLI « EPG courte » (demande client — la section restait vide) : si la
    // fenêtre glissante XMLTV ne donne AUCUN programme encore pertinent
    // (rien dont la fin est dans le futur), on demande au panel Xtream ses
    // « maintenant + suivants » (une requête API légère, cachée 10 min —
    // cf. ShortEpgService, JAMAIS une connexion de flux). Chaînes M3U sans
    // XMLTV : le repli catégorie du build() prend ensuite le relais.
    final DateTime nowCheck = DateTime.now();
    final bool hasUseful =
        progs.any((EpgProgram p) => p.stopDateTime.isAfter(nowCheck));
    if (!hasUseful) {
      final List<EpgProgram> short =
          await ShortEpgService.instance.upcomingFor(widget.channel);
      if (!mounted || id != widget.channel.id) return;
      if (short.isNotEmpty) progs = short.take(4).toList();
    }
    setState(() {
      _programs = progs;
      _loaded = true;
    });
  }

  double _progress(EpgProgram p, DateTime now) {
    final int span = p.stopTime - p.startTime;
    if (span <= 0) return 0;
    return ((now.millisecondsSinceEpoch - p.startTime) / span)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    // Programmes triés par start_time ASC (programsBetween) → on prend le
    // 1er « en cours » et le 1er « à venir ».
    final DateTime now = DateTime.now();
    final int nowMs = now.millisecondsSinceEpoch;
    EpgProgram? current;
    EpgProgram? next;
    for (final EpgProgram p in _programs) {
      if (current == null && p.isLiveAt(now)) {
        current = p;
      } else if (next == null && p.startTime > nowMs) {
        next = p;
      }
      if (current != null && next != null) break;
    }

    // FALLBACK INTELLIGENT : jamais « Programme non disponible » brut face
    // au client. Nom de catégorie si dispo, sinon « EN DIRECT » (clé
    // existante, localisée). Cas : source sans EPG ou tvg-id non apparié.
    if (current == null && next == null) {
      final String cat =
          ChannelClassifier.prettifyCategory(widget.channel.category);
      final String label = (cat.isNotEmpty && cat.toLowerCase() != 'autres')
          ? cat
          : context.l10n.tvProgramLive;
      return Align(
        alignment: Alignment.topLeft,
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TvTokens.ui(TvDimens.caption, color: TvTokens.mutedDim)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (current != null) ...<Widget>[
          // « EN CE MOMENT · <titre> » (clé tvLiveNowPlaying, 8 langues).
          Text(context.l10n.tvLiveNowPlaying(current.title),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.ui(TvDimens.caption,
                  weight: FontWeight.w700, color: TvTokens.text)),
          const SizedBox(height: 7),
          Row(
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: _progress(current, now),
                    backgroundColor: TvTokens.lineSoft,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(TvTokens.gold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(current.timeRangeShort,
                  style: TvTokens.ui(TvDimens.caption,
                      weight: FontWeight.w700, color: TvTokens.mutedDim)),
            ],
          ),
        ],
        if (next != null) ...<Widget>[
          const SizedBox(height: 12),
          // « À suivre · <titre> » (clé tvGuideUpNextProgram, 8 langues).
          Text(context.l10n.tvGuideUpNextProgram(next.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.ui(TvDimens.caption,
                  weight: FontWeight.w600, color: TvTokens.muted)),
          const SizedBox(height: 2),
          Text(next.timeRangeShort,
              style: TvTokens.ui(TvDimens.caption, color: TvTokens.mutedDim)),
        ],
      ],
    );
  }
}
