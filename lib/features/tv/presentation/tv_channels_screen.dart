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

import '../../channels/data/category_order_store.dart';
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
import 'widgets/tv_category_reorder.dart';
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
    // Ordre PERSONNALISÉ des catégories (partagé partout) : on le charge et on
    // écoute ses changements pour ré-ordonner la colonne en live.
    // ignore: discarded_futures
    CategoryOrderStore.instance.ensureLoaded();
    CategoryOrderStore.instance.addListener(_onCatOrderChanged);
  }

  @override
  void dispose() {
    _chanSub?.cancel();
    _favSub?.cancel();
    CategoryOrderStore.instance.removeListener(_onCatOrderChanged);
    _preview.dispose();
    super.dispose();
  }

  void _onCatOrderChanged() {
    if (mounted) setState(() => _cats = _orderedCats(_cats));
  }

  /// Applique l'ordre personnalisé de l'usager aux VRAIES catégories (la
  /// pseudo « Toutes les chaînes » reste toujours en tête).
  List<String> _orderedCats(List<String> cats) {
    final List<String> pseudo =
        cats.where((String c) => c == _kAll).toList();
    final List<String> real = cats.where((String c) => c != _kAll).toList();
    final List<String> orderedReal =
        CategoryOrderStore.instance.applyOrder(real, (String c) => c);
    return <String>[...pseudo, ...orderedReal];
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
      // ORDRE PERSONNALISÉ appliqué par-dessus l'ordre d'import.
      _cats = _orderedCats(cats);
      _groups = groups;
      if (!_cats.contains(_cat)) _cat = _kAll;
      _visible = _channelsFor(_cat);
      _preview.value ??= _visible.isNotEmpty ? _visible.first : null;
      _loading = false;
    });
  }

  // ---- Réorganisation (monter / descendre) — premium, partagée ----

  /// Catégorie actuellement « saisie » pour être déplacée (null = aucune).
  String? _reorderCat;

  bool _isPseudoCat(String cat) => cat == _kAll;

  void _beginReorder(String cat) {
    if (_isPseudoCat(cat)) return;
    setState(() => _reorderCat = cat);
  }

  void _endReorder() {
    if (_reorderCat == null) return;
    setState(() => _reorderCat = null);
  }

  /// Vraies catégories (hors pseudo) dans l'ordre courant.
  List<String> _realCats() => _cats.where((String c) => !_isPseudoCat(c)).toList();

  void _moveReorder(String cat, int dir) {
    final List<String> order = _realCats();
    final int idx = order.indexOf(cat);
    if (idx < 0) return;
    final int next = idx + dir;
    if (next < 0 || next >= order.length) return;
    final String tmp = order[idx];
    order[idx] = order[next];
    order[next] = tmp;
    // Persiste l'ordre complet → le store notifie et tous les écrans se
    // ré-ordonnent (y compris celui-ci via _onCatOrderChanged).
    // ignore: discarded_futures
    CategoryOrderStore.instance.setOrder(order);
  }

  bool _canMoveUp(String cat) => _realCats().indexOf(cat) > 0;
  bool _canMoveDown(String cat) {
    final List<String> r = _realCats();
    final int i = r.indexOf(cat);
    return i >= 0 && i < r.length - 1;
  }

  // DOUBLE-CLIC OK = MODE DÉPLACEMENT (télécommande). 1 OK sélectionne ; 2 OK
  // rapprochés sur une vraie catégorie l'« attrapent » → HAUT/BAS la déplacent.
  String? _lastOkCat;
  DateTime? _lastOkAt;
  void _onCatOk(String cat) {
    final DateTime now = DateTime.now();
    final bool doubleOk = _lastOkCat == cat &&
        _lastOkAt != null &&
        now.difference(_lastOkAt!) < const Duration(milliseconds: 600);
    _lastOkCat = cat;
    _lastOkAt = now;
    if (doubleOk && !_isPseudoCat(cat)) {
      _lastOkCat = null;
      _lastOkAt = null;
      _beginReorder(cat);
      return;
    }
    _selectCat(cat);
  }

  /// Mode déplacement : HAUT/BAS déplacent la catégorie saisie (au lieu de
  /// bouger le focus) ; GAUCHE/DROITE neutralisées ; Retour/Échap pose.
  KeyEventResult _onReorderKey(FocusNode node, KeyEvent event) {
    final String? rc = _reorderCat;
    if (rc == null) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_canMoveUp(rc)) _moveReorder(rc, -1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_canMoveDown(rc)) _moveReorder(rc, 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack) {
      _endReorder();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
            // MODE DÉPLACEMENT (télécommande) : HAUT/BAS déplacent la catégorie
            // saisie tant que _reorderCat != null (cf. _onReorderKey).
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onReorderKey,
              child: ListView.builder(
              itemCount: _cats.length,
              itemBuilder: (BuildContext c, int i) {
                final String cat = _cats[i];
                final bool reordering = _reorderCat == cat;
                final List<String> real = _realCats();
                final int ri = real.indexOf(cat);
                return _RowTile(
                  key: ValueKey<String>(cat),
                  label: cat,
                  count: _countFor(cat),
                  active: cat == _cat,
                  autofocus: i == 0,
                  reordering: reordering,
                  reorderable: !_isPseudoCat(cat),
                  canMoveUp: reordering && ri > 0,
                  canMoveDown: reordering && ri >= 0 && ri < real.length - 1,
                  onSelect: () {
                    if (reordering) {
                      _endReorder();
                    } else {
                      _onCatOk(cat);
                    }
                  },
                  onLongPress: () => _beginReorder(cat),
                  onMoveUp: () => _moveReorder(cat, -1),
                  onMoveDown: () => _moveReorder(cat, 1),
                );
              },
            ),
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
                // TACTILE (téléphone/tablette) : un TAP sur la vignette ouvre
                // le plein écran — GestureDetector pur, AUCUN FocusNode ajouté
                // → le parcours D-pad (liste → boutons) reste identique.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
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
                // « NOS ÉVÉNEMENTS » (demande client) : les émissions à venir
                // de la chaîne, sous l'aperçu — en-tête de section + le
                // programme EN COURS en or, puis les suivants avec horaires.
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
    super.key,
    required this.label,
    required this.count,
    required this.active,
    required this.autofocus,
    required this.onSelect,
    this.reordering = false,
    this.reorderable = false,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onLongPress,
    this.onMoveUp,
    this.onMoveDown,
  });
  final String label;
  final int count;
  final bool active;
  final bool autofocus;
  final VoidCallback onSelect;
  // Réorganisation (monter / descendre) — premium, partagée.
  final bool reordering;
  final bool reorderable;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onLongPress;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocusBuilder(
        autofocus: autofocus,
        scale: TvFocusScale.small,
        onSelect: onSelect,
        onLongPress: reorderable ? onLongPress : null,
        builder: (BuildContext context, bool focused) {
          final Color bg = reordering
              ? TvTokens.gold.withValues(alpha: 0.16)
              : focused
                  ? TvTokens.sel
                  : (active
                      ? TvTokens.sel.withValues(alpha: 0.6)
                      : Colors.transparent);
          final Color fg = (focused || active || reordering)
              ? TvTokens.text
              : TvTokens.muted;
          final Widget row = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvTokens.rMenuItem),
              border: reordering
                  ? Border.all(color: TvTokens.gold, width: 1.4)
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: TvDimens.body,
                          fontWeight: (focused || active || reordering)
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: fg)),
                ),
                const SizedBox(width: 8),
                if (reordering)
                  TvReorderChevrons(
                    canUp: canMoveUp,
                    canDown: canMoveDown,
                    onUp: onMoveUp ?? () {},
                    onDown: onMoveDown ?? () {},
                    onDone: onSelect,
                  )
                else
                  Text('$count',
                      style: const TextStyle(
                          fontSize: TvDimens.caption,
                          fontWeight: FontWeight.w700,
                          color: TvTokens.mutedDim)),
              ],
            ),
          );
          return TvReorderBounce(active: reordering, child: row);
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
    List<EpgProgram> today = const <EpgProgram>[];
    try {
      today = await EpgRepository.instance.todayPrograms(id);
    } catch (_) {
      // EPG indisponible → on affichera le repli.
    }
    if (!mounted || id != widget.channel.id) return;
    final DateTime now = DateTime.now();
    // En cours + suivantes uniquement (le passé n'intéresse personne ici).
    List<EpgProgram> upcoming = today
        .where((EpgProgram p) => p.stopDateTime.isAfter(now))
        .take(4)
        .toList();
    // REPLI « EPG courte » (demande client — la section restait vide) : si la
    // base XMLTV ne connaît pas cette chaîne, on demande au panel Xtream ses
    // « maintenant + suivants » (une requête API, cachée 10 min — cf.
    // ShortEpgService). Chaînes M3U sans XMLTV : rien de plus à tenter.
    if (upcoming.isEmpty) {
      final List<EpgProgram> short =
          await ShortEpgService.instance.upcomingFor(widget.channel);
      if (!mounted || id != widget.channel.id) return;
      upcoming = short.take(4).toList();
    }
    setState(() {
      _programs = upcoming;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_programs.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text('Programme non disponible',
            style: TvTokens.ui(TvDimens.caption, color: TvTokens.mutedDim)),
      );
    }
    final DateTime now = DateTime.now();
    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _programs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (BuildContext c, int i) {
        final EpgProgram p = _programs[i];
        final bool live = p.isLiveAt(now);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(p.timeRangeShort,
                style: TvTokens.ui(TvDimens.caption,
                    weight: FontWeight.w700,
                    color: live ? TvTokens.gold : TvTokens.mutedDim)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.ui(TvDimens.caption,
                      weight: live ? FontWeight.w700 : FontWeight.w500,
                      color: live ? TvTokens.text : TvTokens.muted)),
            ),
          ],
        );
      },
    );
  }
}
