// =========================================================
//  tv_tivimate_home_screen.dart — Template « TiviMate »
// =========================================================
//  Réplique de l'accueil TiviMate (liste des chaînes en panneau) :
//    • rail d'icônes à gauche (Recherche · TV actif · Films · Séries ·
//      Catch-up · Templates · Réglages)
//    • colonne des GROUPES (« ★ Favoris » + « Toutes les chaînes » en tête,
//      puis les catégories de la playlist)
//    • liste des CHAÎNES du groupe + APERÇU (logo/nom/n°) et EPG now/next
//      — appui long OK sur une chaîne = toggle favori (comme partout)
//  OK sur une chaîne → TvPlayerScreen (ExoPlayer/Media3) → zapping haut/bas.
//
//  COULEURS IDENTIQUES à TiviMate (fond #000000, panneaux #12171C, accent
//  bleu #0A84FF, focus = pill blanc plein / texte noir, chaîne active =
//  n°+nom bleu + ►). SEUL le logo = SEVEN.
//
//  Réutilise UNIQUEMENT des briques EXISTANTES (PlaylistRepository,
//  MiniEpgNowNext, TvChannelLogo, TvPlayerScreen). AUCUN fichier media_kit :
//  la lecture passe par TvPlayerScreen (natif). Aucun fichier cast/lecture/
//  boot touché. 100 % télécommande.
// =========================================================
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/data/category_order_store.dart';
import '../../channels/domain/channel.dart';
import '../../channels/domain/channel_genre.dart';
import '../../epg/presentation/widgets/mini_epg_now_next.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import '../core/tv_memory_guard.dart';
import 'widgets/tv_category_reorder.dart';
import 'tv_films_screen.dart';
import 'tv_home_template_screen.dart';
import 'tv_live_preview.dart';
import 'tv_player_screen.dart';
import 'tv_recordings_screen.dart';
import 'tv_screensaver.dart';
import 'tv_search_screen.dart';
import 'tv_series_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_tivimate_guide_screen.dart';

// ---- Palette TiviMate (tokens §1 de la fiche) ----
const Color _tmBg = Color(0xFF000000); // fond app / vidéo
const Color _tmPanel = Color(0xFF12171C); // surface panneau (groupes/liste)
const Color _tmRail = Color(0xFF0C0F12); // rail d'icônes
const Color _tmItem = Color(0xFF1E2126); // item au repos
const Color _tmAccent = Color(0xFF0A84FF); // ACCENT bleu marque
const Color _tmText = Color(0xFFFFFFFF); // texte principal
const Color _tmText2 = Color(0xFFB8BDC4); // texte secondaire
const Color _tmText3 = Color(0xFF6B7178); // texte tertiaire / n°
const Color _tmSoft = Color(0xFF3A3E45); // sélection douce (groupe non focus)

// Sentinelles INTERNES des pseudo-groupes (jamais affichées telles quelles :
// le libellé visible passe par _groupLabel → l10n). « Toutes les chaînes »
// garde son ancienne valeur (clé de tri/sélection déjà en place) ; le groupe
// FAVORIS (parité TiviMate : les favoris en tête de liste) utilise une clé
// technique qu'aucune vraie catégorie prettifiée ne peut produire.
const String _kAllGroup = 'Toutes les chaînes';
const String _kFavGroup = 'k.tm.favs';

class TvTivimateHomeScreen extends StatefulWidget {
  const TvTivimateHomeScreen({super.key});

  @override
  State<TvTivimateHomeScreen> createState() => _TvTivimateHomeScreenState();
}

class _TvTivimateHomeScreenState extends State<TvTivimateHomeScreen> {
  StreamSubscription<List<Channel>>? _sub;
  List<Channel> _all = <Channel>[];
  List<String> _groups = <String>[_kFavGroup, _kAllGroup];
  String _group = _kAllGroup;
  List<Channel> _visible = <Channel>[];

  /// FAVORIS (parité TiviMate) : IDs de la portée active + écoute live —
  /// un toggle (appui long) ou une bascule d'univers repeint le compteur du
  /// groupe « ★ Favoris », les étoiles des lignes et la liste si on est déjà
  /// dans ce groupe.
  StreamSubscription<Set<String>>? _favSub;
  Set<String> _favIds = <String>{};

  /// Chaîne prévisualisée (focus D-pad). ValueNotifier et non champ +
  /// setState : chaque déplacement de focus ne reconstruit QUE l'aperçu
  /// et le surlignage des lignes concernées, plus jamais l'écran entier
  /// (même patron que tv_channels_screen — zéro saccade au défilement
  /// sur les gros bouquets).
  final ValueNotifier<Channel?> _preview = ValueNotifier<Channel?>(null);
  bool _loading = true;

  /// Aperçu VIDÉO actif ? Coupé sur une frame propre AVANT tout écran
  /// poussé (lecteur, réglages…) — jamais 2 flux ouverts, et la SurfaceView
  /// hybride ne laisse pas sa dernière trame percer par-dessus l'écran
  /// suivant (même garde que le Lanceur).
  bool _previewLive = true;

  @override
  void initState() {
    super.initState();
    // Favoris en direct : cache immédiat, puis flux (même patron que
    // tv_channels_screen / tv_live_screen).
    _favIds = FavoritesRepository.instance.current;
    // ignore: discarded_futures
    FavoritesRepository.instance.initialize();
    _favSub = FavoritesRepository.instance.favoritesStream
        .listen(_onFavoritesChanged);
    _ingest(PlaylistRepository.instance.currentChannels);
    _sub = PlaylistRepository.instance.channelsStream.listen(_ingest);
    // Ordre PERSONNALISÉ des catégories (partagé partout) + écoute live.
    // ignore: discarded_futures
    CategoryOrderStore.instance.ensureLoaded();
    CategoryOrderStore.instance.addListener(_onCatOrderChanged);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _favSub?.cancel();
    CategoryOrderStore.instance.removeListener(_onCatOrderChanged);
    _preview.dispose();
    super.dispose();
  }

  void _onFavoritesChanged(Set<String> ids) {
    if (!mounted) return;
    setState(() {
      _favIds = ids;
      _counts[_kFavGroup] = _favoriteChannels().length;
      if (_group == _kFavGroup) {
        // On regarde le groupe FAVORIS : la liste suit le toggle en direct.
        _visible = _channelsFor(_kFavGroup);
        // L'aperçu peut pointer une chaîne qui vient d'être retirée →
        // resynchronisation sur l'instance encore visible, ou la 1re.
        final String? previewId = _preview.value?.id;
        final int keep = previewId == null
            ? -1
            : _visible.indexWhere((Channel c) => c.id == previewId);
        _preview.value = keep >= 0
            ? _visible[keep]
            : (_visible.isNotEmpty ? _visible.first : null);
      }
    });
  }

  /// Chaînes favorites, dans l'ordre de la playlist (bornes : les favoris
  /// restent une poignée — le filtre O(n) ne tourne qu'au toggle/à l'ingestion,
  /// jamais pendant le défilement).
  List<Channel> _favoriteChannels() =>
      _all.where((Channel c) => _favIds.contains(c.id)).toList();

  void _onCatOrderChanged() {
    if (mounted) setState(() => _groups = _orderedGroups(_groups));
  }

  /// Applique l'ordre personnalisé aux VRAIS groupes (« ★ Favoris » et
  /// « Toutes les chaînes » restent toujours en tête, dans cet ordre).
  List<String> _orderedGroups(List<String> groups) {
    final List<String> pseudo =
        groups.where(_isPseudoGroup).toList();
    final List<String> real =
        groups.where((String g) => !_isPseudoGroup(g)).toList();
    final List<String> orderedReal =
        CategoryOrderStore.instance.applyOrder(real, (String g) => g);
    return <String>[...pseudo, ...orderedReal];
  }

  /// Nombre de chaînes par groupe ET chaînes par groupe — PRÉ-CALCULÉS à
  /// l'ingestion (une seule passe, même patron que tv_channels_screen).
  /// Avant, seuls les compteurs l'étaient : chaque OK sur un groupe
  /// refaisait un `where(prettifyCategory(...))` sur le bouquet ENTIER
  /// (10 000-20 000 regex sur le thread UI ≈ 50-300 ms de gel par
  /// changement d'onglet au D-pad).
  Map<String, int> _counts = <String, int>{};
  Map<String, List<Channel>> _byGroup = <String, List<Channel>>{};

  void _ingest(List<Channel> channels) {
    // Groupes = catégories nettoyées, dans l'ordre de première apparition.
    // « ★ Favoris » puis « Toutes les chaînes » toujours en tête (TiviMate).
    final List<String> groups = <String>[_kFavGroup, _kAllGroup];
    final Set<String> seen = <String>{};
    final Map<String, int> counts = <String, int>{};
    final Map<String, List<Channel>> byGroup = <String, List<Channel>>{};
    for (final Channel c in channels) {
      final String g = ChannelClassifier.prettifyCategory(c.category);
      if (g.isEmpty) continue;
      if (seen.add(g)) groups.add(g);
      counts[g] = (counts[g] ?? 0) + 1;
      (byGroup[g] ??= <Channel>[]).add(c);
    }
    counts[_kAllGroup] = channels.length;
    counts[_kFavGroup] =
        channels.where((Channel c) => _favIds.contains(c.id)).length;
    if (!mounted) return;
    setState(() {
      _all = channels;
      // ORDRE PERSONNALISÉ appliqué par-dessus l'ordre d'import.
      _groups = _orderedGroups(groups);
      _counts = counts;
      _byGroup = byGroup;
      if (!_groups.contains(_group)) _group = _kAllGroup;
      _visible = _channelsFor(_group);
      // RESYNC / CHANGEMENT de playlist : l'aperçu peut pointer une chaîne
      // qui n'existe plus (ou une instance périmée). Le `??=` d'avant ne le
      // réalignait JAMAIS → l'en-tête gardait une « chaîne fantôme » (nom +
      // EPG de l'ancienne playlist) jusqu'au prochain cran de D-pad. On
      // resynchronise sur l'instance fraîche, ou la 1re chaîne visible.
      final String? previewId = _preview.value?.id;
      final int keep = previewId == null
          ? -1
          : _visible.indexWhere((Channel c) => c.id == previewId);
      _preview.value = keep >= 0
          ? _visible[keep]
          : (_visible.isNotEmpty ? _visible.first : null);
      _loading = false;
    });
  }

  // ---- Réorganisation (monter / descendre) — premium, partagée ----

  /// Groupe actuellement « saisi » pour être déplacé (null = aucun).
  String? _reorderGroup;

  bool _isPseudoGroup(String g) => g == _kAllGroup || g == _kFavGroup;

  /// Libellé VISIBLE d'un groupe : les sentinelles passent par l10n (langue
  /// active), les vraies catégories s'affichent telles quelles.
  String _groupLabel(BuildContext context, String g) {
    if (g == _kFavGroup) return '★ ${context.l10n.navFavorites}';
    if (g == _kAllGroup) return context.l10n.tvTmAllChannels;
    return g;
  }

  List<String> _realGroups() =>
      _groups.where((String g) => !_isPseudoGroup(g)).toList();

  void _beginReorder(String g) {
    if (_isPseudoGroup(g)) return;
    HapticFeedback.mediumImpact();
    setState(() => _reorderGroup = g);
  }

  void _endReorder() {
    if (_reorderGroup == null) return;
    HapticFeedback.selectionClick();
    setState(() => _reorderGroup = null);
  }

  void _moveReorder(String g, int dir) {
    final List<String> order = _realGroups();
    final int idx = order.indexOf(g);
    if (idx < 0) return;
    final int next = idx + dir;
    if (next < 0 || next >= order.length) return;
    final String tmp = order[idx];
    order[idx] = order[next];
    order[next] = tmp;
    HapticFeedback.selectionClick();
    // ignore: discarded_futures
    CategoryOrderStore.instance.setOrder(order);
  }

  bool _canMoveUp(String g) => _realGroups().indexOf(g) > 0;
  bool _canMoveDown(String g) {
    final List<String> r = _realGroups();
    final int i = r.indexOf(g);
    return i >= 0 && i < r.length - 1;
  }

  // DOUBLE-CLIC OK = MODE DÉPLACEMENT (télécommande). 1 OK sélectionne ; 2 OK
  // rapprochés sur un vrai groupe l'« attrapent » → HAUT/BAS le déplacent.
  String? _lastOkGroup;
  DateTime? _lastOkAt;
  void _onGroupOk(String g) {
    final DateTime now = DateTime.now();
    final bool doubleOk = _lastOkGroup == g &&
        _lastOkAt != null &&
        now.difference(_lastOkAt!) < const Duration(milliseconds: 600);
    _lastOkGroup = g;
    _lastOkAt = now;
    if (doubleOk && !_isPseudoGroup(g)) {
      _lastOkGroup = null;
      _lastOkAt = null;
      _beginReorder(g);
      return;
    }
    _selectGroup(g);
  }

  /// Le Retour qui POSE le groupe est consommé au KeyDown ; il faut AUSSI
  /// avaler son KeyUp. Sinon (le mode étant déjà terminé au relâchement,
  /// `_reorderGroup == null`), l'UP non géré remontait à Android qui
  /// déclenchait le back SYSTÈME → `_onBack()` déplaçait le focus vers le
  /// rail (voire ouvrait la boîte « Quitter ») juste après avoir posé.
  bool _swallowBackUp = false;

  /// Mode déplacement : HAUT/BAS déplacent le groupe saisi ; GAUCHE/DROITE
  /// neutralisées ; Retour/Échap pose.
  KeyEventResult _onReorderKey(FocusNode node, KeyEvent event) {
    final LogicalKeyboardKey k = event.logicalKey;
    final bool isBack = k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.browserBack;
    if (event is KeyUpEvent) {
      // Relâchement du Retour qui vient de poser le groupe (cf. doc de
      // _swallowBackUp) : avalé, pour ne pas déclencher le back système.
      if (isBack && _swallowBackUp) {
        _swallowBackUp = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final String? rg = _reorderGroup;
    if (rg == null) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_canMoveUp(rg)) _moveReorder(rg, -1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_canMoveDown(rg)) _moveReorder(rg, 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    if (isBack) {
      _swallowBackUp = true;
      _endReorder();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<Channel> _channelsFor(String group) {
    if (group == _kFavGroup) return _favoriteChannels();
    if (group == _kAllGroup) return _all;
    return _byGroup[group] ?? const <Channel>[];
  }

  void _selectGroup(String group) {
    setState(() {
      _group = group;
      _visible = _channelsFor(group);
      _preview.value = _visible.isNotEmpty ? _visible.first : null;
    });
  }

  /// Suspend l'aperçu vidéo sur une frame PROPRE avant de pousser un écran,
  /// puis le ré-arme au retour (BACK). Cf. doc de [_previewLive].
  Future<void> _suspendPreview() async {
    setState(() => _previewLive = false);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _play(int index) async {
    if (_visible.isEmpty) return;
    await _suspendPreview();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvPlayerScreen(channels: _visible, startIndex: index),
      ),
    );
    if (mounted) setState(() => _previewLive = true);
  }

  Future<void> _open(Widget screen) async {
    // Material (transparent) OBLIGATOIRE : sans ancêtre Material, Flutter dessine
    // des DOUBLES SOULIGNEMENTS JAUNES sous chaque texte. Les écrans « bucket »
    // (Réglages, Recherche, Séries, Films…) ne s'enveloppent pas eux-mêmes → on
    // le fait ici (comme le Lanceur) → typographie NETTE, pas de lignes jaunes.
    await _suspendPreview();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            Material(type: MaterialType.transparency, child: screen)));
    if (mounted) setState(() => _previewLive = true);
  }

  /// RETOUR PROGRESSIF (« bout à bout ») — plus JAMAIS de fermeture brutale de
  /// l'app au premier Retour. On recule d'UN cran vers la GAUCHE : chaînes →
  /// groupes → rail d'icônes (via le focus directionnel intégré de Flutter). Ce
  /// n'est QUE lorsqu'on est déjà tout à gauche (plus rien à gauche) qu'on
  /// PROPOSE de quitter (avec confirmation), au lieu de fermer sans rien
  /// demander. Pensé pour les personnes âgées : un Retour = un petit pas en
  /// arrière, prévisible.
  Future<void> _onBack() async {
    final bool moved =
        FocusScope.of(context).focusInDirection(TraversalDirection.left);
    if (moved) return; // il restait un cran à gauche → on a juste reculé
    // Déjà tout à gauche : on demande confirmation avant de quitter l'app.
    final bool? quit = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        backgroundColor: _tmPanel,
        title: Text(d.l10n.tvTmQuitTitle,
            style: const TextStyle(
                color: _tmText, fontSize: 22, fontWeight: FontWeight.w700)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(d.l10n.buttonCancel,
                style: const TextStyle(color: _tmText2, fontSize: 18)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(d.l10n.tvQuit,
                style: const TextStyle(
                    color: _tmAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (quit == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        await _onBack();
      },
      // ÉCRAN DE VEILLE anti burn-in (parité avec les accueils Classique,
      // Lanceur et Rails) : une box laissée sur cet accueil affichait le
      // rail et la grille en continu → marquage OLED. Le watcher ne s'arme
      // que quand l'accueil est la route visible (garde-fou interne).
      child: TvScreensaverWatcher(
        child: Container(
        color: _tmBg,
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _iconRail(),
                _groupsColumn(),
                Expanded(child: _channelPane()),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  // ---- Rail d'icônes (gauche) ----
  Widget _iconRail() {
    return Container(
      width: 76,
      color: _tmRail,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: <Widget>[
          _RailIcon(
              icon: Icons.search_rounded,
              onSelect: () => _open(const TvSearchScreen())),
          const SizedBox(height: 14),
          const _RailIcon(icon: Icons.live_tv_rounded, active: true),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.movie_rounded,
              onSelect: () => _open(const TvFilmsScreen())),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.video_library_rounded,
              onSelect: () => _open(const TvSeriesScreen())),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.replay_rounded,
              onSelect: () => _open(const TvRecordingsScreen())),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.grid_view_rounded,
              onSelect: () => _open(const TvTivimateGuideScreen())),
          const Spacer(),
          _RailIcon(
              icon: Icons.dashboard_customize_rounded,
              onSelect: () => _open(const TvHomeTemplateScreen())),
          const SizedBox(height: 14),
          _RailIcon(
              icon: Icons.settings_outlined,
              onSelect: () => _open(const TvSettingsScreen())),
        ],
      ),
    );
  }

  // ---- Colonne des groupes ----
  Widget _groupsColumn() {
    return Container(
      width: 300,
      color: _tmPanel,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // RECHERCHE INTELLIGENTE — gros bouton en HAUT, bien visible
          // (personnes âgées / fatiguées). Ouvre la recherche globale.
          // Passe par _open : l'aperçu vidéo est suspendu avant le push
          // (même règle que le rail d'icônes) + Material transparent.
          _TmSearchButton(
            onSelect: () => _open(const TvSearchScreen()),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Text(context.l10n.tvTmGroups,
                style: const TextStyle(
                    color: _tmText3,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
          ),
          Expanded(
            // MODE DÉPLACEMENT (télécommande) : HAUT/BAS déplacent le groupe
            // saisi tant que _reorderGroup != null (cf. _onReorderKey).
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onReorderKey,
              child: ListView.builder(
              // Hauteur de rangée MESURÉE une fois (prototype) : sans
              // extent, chaque frame de scroll re-mesure les enfants et la
              // position est estimée (scrollbar qui saute, jumpTo imprécis).
              prototypeItem: _GroupTile(
                label: 'Prototype',
                count: 0,
                active: false,
                autofocus: false,
                onSelect: () {},
              ),
              itemCount: _groups.length,
              itemBuilder: (BuildContext context, int i) {
                final String g = _groups[i];
                final bool reordering = _reorderGroup == g;
                final List<String> real = _realGroups();
                final int ri = real.indexOf(g);
                return _GroupTile(
                  key: ValueKey<String>(g),
                  label: _groupLabel(context, g),
                  count: _counts[g] ?? 0,
                  active: g == _group,
                  autofocus: false,
                  reordering: reordering,
                  reorderable: !_isPseudoGroup(g),
                  canMoveUp: reordering && ri > 0,
                  canMoveDown: reordering && ri >= 0 && ri < real.length - 1,
                  onSelect: () {
                    if (reordering) {
                      _endReorder();
                    } else {
                      _onGroupOk(g);
                    }
                  },
                  // Appui long : en déplacement il TERMINE (plus besoin de
                  // « Retour ») ; sinon il attrape.
                  onLongPress: () =>
                      reordering ? _endReorder() : _beginReorder(g),
                  onMoveUp: () => _moveReorder(g, -1),
                  onMoveDown: () => _moveReorder(g, 1),
                );
              },
            ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Panneau chaînes : aperçu (haut) + liste (bas) ----
  Widget _channelPane() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: _tmAccent));
    }
    if (_visible.isEmpty) {
      return Center(
        child: Text(context.l10n.tvTmNoChannelInGroup,
            style: const TextStyle(color: _tmText2, fontSize: 18)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Rebuild ciblé : seul l'aperçu écoute le ValueNotifier — le
        // défilement D-pad ne reconstruit jamais la liste entière.
        ValueListenableBuilder<Channel?>(
          valueListenable: _preview,
          builder: (BuildContext context, Channel? p, _) =>
              p == null ? const SizedBox.shrink() : _previewHeader(p),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            // Rangées à hauteur constante (logo 44 + paddings, nom sur 1
            // ligne) : le prototype fige l'extent → scroll D-pad sans
            // re-mesure, position exacte même sur le bouquet entier.
            prototypeItem: _ChannelRow(
              number: 8888,
              channel: _visible.first,
              active: false,
              favorite: false,
              autofocus: false,
              onSelect: () {},
            ),
            itemCount: _visible.length,
            itemBuilder: (BuildContext context, int i) {
              final Channel c = _visible[i];
              return Focus(
                key: ValueKey<String>('tm-focus-${c.id}-$i'),
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (bool has) {
                  // Pas de setState : le ValueNotifier notifie l'aperçu
                  // et les surlignages de ligne, rien d'autre.
                  if (has && mounted && _preview.value?.id != c.id) {
                    _preview.value = c;
                  }
                },
                // _ActiveWatcher (et non ValueListenableBuilder) : un
                // déplacement de focus notifiait TOUTES les lignes visibles
                // (~12-15 _ChannelRow reconstruites) pour 2 qui changent —
                // ici seule la ligne qui GAGNE et celle qui PERD `active`
                // se reconstruisent.
                child: _ActiveWatcher(
                  listenable: _preview,
                  channelId: c.id,
                  builder: (BuildContext context, bool active) =>
                      _ChannelRow(
                    number: i + 1,
                    channel: c,
                    active: active,
                    favorite: _favIds.contains(c.id),
                    autofocus: i == 0,
                    onSelect: () => _play(i),
                    // Appui long OK = toggle favori (parité avec les autres
                    // écrans — même geste que tv_channels_screen).
                    onLongPress: () =>
                        FavoritesRepository.instance.toggle(c.id),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---- Aperçu (logo + nom + EPG now/next + VIDÉO en direct) ----
  Widget _previewHeader(Channel c) {
    // APERÇU VIDÉO de la chaîne focalisée (parité TiviMate, la référence de
    // ce template) : vignette muette, anti-rebond ~600 ms (défiler la liste
    // n'ouvre AUCUN flux pour les chaînes traversées), repli logo — toute
    // la mécanique éprouvée de TvLivePreview. PETITE BOX (profil léger) :
    // pas de vidéo permanente — l'en-tête reste logo + EPG.
    final bool video = !TvMemoryGuard.instance.lowSpec;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _tmPanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TvChannelLogo(logoUrl: c.logoUrl, label: c.name, size: 84, radius: 10),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _tmText,
                      fontSize: 26,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                // Débouncé : l'aperçu suit le FOCUS — sans répit, défiler
                // 50 chaînes = 100 requêtes SQLite (patron des 400 ms de
                // _PreviewPrograms, tv_channels_screen).
                MiniEpgNowNext(
                    channelId: c.id,
                    debounce: const Duration(milliseconds: 350)),
              ],
            ),
          ),
          if (video) ...<Widget>[
            const SizedBox(width: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 256,
                height: 144, // 16:9
                child: TvLivePreview(channel: c, enabled: _previewLive),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =========================================================
//  Sous-widgets
// =========================================================

/// Icône du rail gauche. `active` = onglet courant (fond bleu accent).
class _RailIcon extends StatelessWidget {
  const _RailIcon({required this.icon, this.onSelect, this.active = false});
  final IconData icon;
  final VoidCallback? onSelect;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Onglet COURANT (pas de onSelect) : rendu DIRECT, sans TvFocusBuilder.
    // Passer par `enabled: false` enveloppait l'icône dans le voile
    // « désactivé » de TvFocusable (Opacity 0.45) → le pill bleu accent de
    // l'onglet ACTIF apparaissait délavé. Même rendu, toujours non focusable.
    if (onSelect == null) return _pill(focused: false);
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) => _pill(focused: focused),
    );
  }

  Widget _pill({required bool focused}) {
    final Color bg = focused
        ? _tmText // pill blanc au focus
        : active
            ? _tmAccent
            : Colors.transparent;
    final Color fg = focused
        ? _tmBg
        : active
            ? _tmText
            : _tmText3;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(icon, size: 26, color: fg),
    );
  }
}

/// Ligne de groupe (catégorie). Focus = pill blanc ; actif = texte bleu.
/// Gros bouton RECHERCHE INTELLIGENTE en tête de la colonne Groupes (tivimate).
/// Accent bleu marque, très visible (conçu pour les personnes âgées).
class _TmSearchButton extends StatelessWidget {
  const _TmSearchButton({required this.onSelect});
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: focused ? _tmAccent : _tmAccent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _tmAccent, width: 1.4),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.search_rounded,
                  size: 22, color: focused ? _tmText : _tmAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.l10n.tvTmSmartSearch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _tmText)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
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

  /// Nombre de chaînes du groupe — affiché à droite (demande client).
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
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      onLongPress: reorderable ? onLongPress : null,
      builder: (BuildContext context, bool focused) {
        final Color bg = reordering
            ? _tmAccent.withValues(alpha: 0.18)
            : focused
                ? _tmText
                : active
                    ? _tmSoft
                    : Colors.transparent;
        final Color fg = reordering
            ? _tmText
            : focused
                ? _tmBg
                : active
                    ? _tmAccent
                    : _tmText2;
        final Widget tile = AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(28),
            border: reordering
                ? Border.all(color: _tmAccent, width: 1.4)
                : null,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg,
                      fontSize: 17,
                      fontWeight: (active || reordering)
                          ? FontWeight.w700
                          : FontWeight.w500),
                ),
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
              else ...<Widget>[
                // Compteur de chaînes du groupe (ex. « Sports FR · 240 »).
                Text('$count',
                    style: TextStyle(
                        color: focused ? _tmBg : _tmText3,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                if (active && !focused) ...<Widget>[
                  const SizedBox(width: 6),
                  const Icon(Icons.play_arrow_rounded,
                      size: 18, color: _tmAccent),
                ],
              ],
            ],
          ),
        );
        return TvReorderBounce(active: reordering, child: tile);
      },
    );
  }
}

/// Écoute [listenable] mais ne reconstruit QUE si `active` (== « la chaîne
/// prévisualisée est la mienne ») CHANGE. Un ValueListenableBuilder par
/// ligne reconstruisait toutes les lignes visibles à chaque cran de D-pad ;
/// ici, seules la ligne qui gagne et celle qui perd le surlignage bougent.
class _ActiveWatcher extends StatefulWidget {
  const _ActiveWatcher({
    required this.listenable,
    required this.channelId,
    required this.builder,
  });

  final ValueListenable<Channel?> listenable;
  final String channelId;
  final Widget Function(BuildContext context, bool active) builder;

  @override
  State<_ActiveWatcher> createState() => _ActiveWatcherState();
}

class _ActiveWatcherState extends State<_ActiveWatcher> {
  late bool _active = widget.listenable.value?.id == widget.channelId;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(_ActiveWatcher old) {
    super.didUpdateWidget(old);
    if (!identical(old.listenable, widget.listenable)) {
      old.listenable.removeListener(_onChanged);
      widget.listenable.addListener(_onChanged);
    }
    // Recyclage d'item (le builder réutilise ce State pour une autre
    // chaîne) : on réévalue sans attendre une notification.
    _active = widget.listenable.value?.id == widget.channelId;
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final bool now = widget.listenable.value?.id == widget.channelId;
    if (now != _active && mounted) setState(() => _active = now);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _active);
}

/// Ligne de chaîne : [n°] [logo] [nom] [★ si favorite] [► si active].
/// Focus = pill blanc. Appui long = toggle favori (comme partout).
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.number,
    required this.channel,
    required this.active,
    required this.favorite,
    required this.autofocus,
    required this.onSelect,
    this.onLongPress,
  });
  final int number;
  final Channel channel;
  final bool active;
  final bool favorite;
  final bool autofocus;
  final VoidCallback onSelect;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      onLongPress: onLongPress,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? _tmText
            : active
                ? _tmItem
                : Colors.transparent;
        final Color nameColor = focused
            ? _tmBg
            : active
                ? _tmAccent
                : _tmText;
        final Color numColor = focused
            ? _tmBg
            : active
                ? _tmAccent
                : _tmText3;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 44,
                child: Text(
                  '$number',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: numColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              TvChannelLogo(
                  logoUrl: channel.logoUrl,
                  label: channel.name,
                  size: 44,
                  radius: 8),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: nameColor,
                      fontSize: 18,
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              // ★ favori — même jaune que les autres écrans ; sur le pill
              // blanc (focus), le noir garde le contraste.
              if (favorite) ...<Widget>[
                const SizedBox(width: 6),
                Icon(Icons.star_rounded,
                    size: 18,
                    color: focused ? _tmBg : const Color(0xFFFFC107)),
              ],
              if (active && !focused)
                const Icon(Icons.play_arrow_rounded,
                    size: 20, color: _tmAccent),
            ],
          ),
        );
      },
    );
  }
}
