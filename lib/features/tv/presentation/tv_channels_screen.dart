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

import '../../channels/domain/channel.dart';
import '../../channels/domain/channel_genre.dart';
import '../../epg/data/epg_repository.dart';
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
  String _cat = _kAll;
  List<Channel> _visible = <Channel>[];
  Channel? _preview;
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
    super.dispose();
  }

  void _ingest(List<Channel> channels) {
    final List<String> cats = <String>[_kAll];
    final Set<String> seen = <String>{};
    for (final Channel c in channels) {
      final String g = ChannelClassifier.prettifyCategory(c.category);
      if (g.isEmpty) continue;
      if (seen.add(g)) cats.add(g);
    }
    if (!mounted) return;
    setState(() {
      _all = channels;
      _cats = cats;
      if (!_cats.contains(_cat)) _cat = _kAll;
      _visible = _channelsFor(_cat);
      _preview ??= _visible.isNotEmpty ? _visible.first : null;
      _loading = false;
    });
  }

  List<Channel> _channelsFor(String cat) {
    if (cat == _kAll) return _all;
    return _all
        .where((Channel c) => ChannelClassifier.prettifyCategory(c.category) == cat)
        .toList(growable: false);
  }

  void _selectCat(String cat) {
    setState(() {
      _cat = cat;
      _visible = _channelsFor(cat);
      _preview = _visible.isNotEmpty ? _visible.first : null;
      _selectedId = null; // nouveau groupe → plus de chaîne « confirmée »
    });
  }

  /// Appui OK sur une chaîne de la liste (deux temps, cf. [_selectedId]).
  void _onChannelOk(int i, Channel ch) {
    if (_selectedId == ch.id) {
      _play(i); // 2e OK sur la chaîne déjà sélectionnée → plein écran
      return;
    }
    setState(() {
      _selectedId = ch.id; // 1er OK → sélection : l'aperçu la joue
      _preview = ch;
    });
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
      cat == _kAll ? _all.length : _channelsFor(cat).length;

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
        itemCount: _visible.length,
        itemBuilder: (BuildContext c, int i) {
          final Channel ch = _visible[i];
          return Focus(
            key: ValueKey<String>('ch-${ch.id}-$i'),
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (bool has) {
              if (has && mounted && _preview?.id != ch.id) {
                setState(() => _preview = ch);
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
    final Channel? ch = _preview;
    return _panel(
      title: 'Aperçu',
      child: ch == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Aperçu vidéo EN DIRECT de la chaîne focalisée (muet,
                // anti-rebond ~600 ms, repli logo — cf. TvLivePreview).
                // Une chaîne SÉLECTIONNÉE (OK) démarre sans anti-rebond.
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: TvLivePreview(
                    channel: ch,
                    enabled: _previewLive,
                    startImmediately: ch.id == _selectedId,
                  ),
                ),
                const SizedBox(height: 14),
                Text(ch.cleanName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(TvDimens.title,
                        weight: FontWeight.w800, color: TvTokens.text)),
                const SizedBox(height: 10),
                // Programme du jour (façon IBO) : le programme EN COURS en
                // or, puis les 3 suivants avec leurs horaires.
                Expanded(child: _PreviewPrograms(channelId: ch.id)),
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

  @override
  void initState() {
    super.initState();
    EpgRepository.instance.currentProgram(widget.channel.id).then((EpgProgram? p) {
      if (mounted && p != null) setState(() => _now = p.title);
    });
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
            ? (primary ? const Color(0xFF1A1206) : TvTokens.goldBright)
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
  const _PreviewPrograms({required this.channelId});
  final String channelId;

  @override
  State<_PreviewPrograms> createState() => _PreviewProgramsState();
}

class _PreviewProgramsState extends State<_PreviewPrograms> {
  List<EpgProgram> _programs = const <EpgProgram>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_PreviewPrograms old) {
    super.didUpdateWidget(old);
    if (old.channelId != widget.channelId) {
      _loaded = false;
      _programs = const <EpgProgram>[];
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final String id = widget.channelId;
    List<EpgProgram> today = const <EpgProgram>[];
    try {
      today = await EpgRepository.instance.todayPrograms(id);
    } catch (_) {
      // EPG indisponible → on affichera le repli.
    }
    if (!mounted || id != widget.channelId) return;
    final DateTime now = DateTime.now();
    // En cours + suivantes uniquement (le passé n'intéresse personne ici).
    final List<EpgProgram> upcoming = today
        .where((EpgProgram p) => p.stopDateTime.isAfter(now))
        .take(4)
        .toList();
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
