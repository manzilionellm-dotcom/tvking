// =========================================================
//  tv_launcher_home_screen.dart — Accueil « salon » (structure IBO, robe SEVEN)
// =========================================================
//  STRUCTURE demandée par le client (référence : accueil IBO Player Pro) :
//    • en haut à gauche  : APERÇU VIDÉO EN DIRECT de la dernière chaîne
//      regardée + bouton « Regarder maintenant » ;
//    • en haut à droite  : grille « Chaînes Favorites » (accès direct) ;
//    • au centre         : 5 grandes tuiles — En direct, Films, Séries,
//      Replay, Rechercher ;
//    • en bas            : rail « Derniers films ajoutés ».
//  La STRUCTURE vient d'IBO (pattern UX standard IPTV) ; les COULEURS et la
//  typo restent 100 % SEVEN (noir mat + or — jamais de clonage du thème
//  violet, conformément au principe accepté par le client).
//
//  Briques réutilisées : TvLivePreview (aperçu muet anti-rebond, moteur
//  natif — jamais media_kit), RecentlyWatchedRepository (dernière chaîne),
//  FavoritesRepository, VodRepository (films). Aucun fichier cast/lecture/
//  boot touché. 100 % télécommande (TvFocusBuilder) ET tactile.
// =========================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../channels/data/recently_watched_repository.dart';
import '../../channels/data/watch_history_repository.dart';
import '../../channels/domain/channel.dart';
import '../../epg/data/epg_repository.dart';
import '../data/channel_reliability.dart';
import '../data/hero_picker.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../vod/data/playback_position_repository.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/domain/vod_movie.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_logo.dart';
import '../core/tv_memory_guard.dart';
import '../core/tv_tokens.dart';
import 'tv_channels_screen.dart';
import 'tv_components.dart';
import 'tv_films_screen.dart';
import 'tv_guide_grid_screen.dart';
import 'tv_home_template_screen.dart';
import 'tv_live_preview.dart';
import 'tv_movie_detail_screen.dart';
import 'tv_player_screen.dart';
import 'tv_profiles_screen.dart';
import 'tv_recordings_screen.dart';
import 'tv_search_screen.dart';
import 'tv_series_screen.dart';
import 'tv_settings_screen.dart';
import 'tv_sources_screen.dart';

class TvLauncherHomeScreen extends StatefulWidget {
  const TvLauncherHomeScreen({super.key});

  @override
  State<TvLauncherHomeScreen> createState() => _TvLauncherHomeScreenState();
}

class _TvLauncherHomeScreenState extends State<TvLauncherHomeScreen> {
  StreamSubscription<List<Channel>>? _chanSub;
  StreamSubscription<List<String>>? _recentSub;

  /// Chaîne du HÉRO : dernière regardée, sinon 1er favori, sinon 1re chaîne.
  Channel? _hero;

  /// Aperçu héro actif ? Coupé AVANT d'ouvrir un plein écran (jamais 2 flux).
  bool _previewLive = true;

  @override
  void initState() {
    super.initState();
    _recomputeHero();
    _chanSub = PlaylistRepository.instance.channelsStream
        .listen((_) => _recomputeHero());
    _recentSub =
        RecentlyWatchedRepository.instance.stream.listen((_) => _recomputeHero());
  }

  @override
  void dispose() {
    _chanSub?.cancel();
    _recentSub?.cancel();
    super.dispose();
  }

  /// `true` quand le héro vient de l'habitude horaire (badge « Ma soirée »).
  bool _heroFromHabit = false;

  /// Mémoïsation du créneau (revue de code) : la requête « Ma soirée »
  /// (scan SQL de l'historique) ne repart qu'au bout de 10 min — inutile de
  /// la refaire à chaque événement de playlist/zapping pour un résultat
  /// identique.
  String? _slotId;
  DateTime? _slotAt;

  // Map id→Channel MÉMOÏSÉE par identité de liste : _recomputeHero repart à
  // chaque événement playlist/zapping — reconstruire une map O(N) du bouquet
  // entier (10-50 k chaînes) à chaque fois coûtait 10-60 ms pour quelques
  // lookups. Tant que la playlist n'a pas changé, la map est réutilisée.
  List<Channel>? _byIdSource;
  Map<String, Channel>? _byIdCache;

  Map<String, Channel> _byId(List<Channel> all) {
    if (!identical(all, _byIdSource)) {
      _byIdSource = all;
      _byIdCache = <String, Channel>{for (final Channel c in all) c.id: c};
    }
    return _byIdCache!;
  }

  /// Candidats du héro (fiables d'abord — n°38) : si l'aperçu du 1er est
  /// indisponible (chaîne coupée côté fournisseur, photo terrain), l'accueil
  /// BASCULE tout seul sur le suivant au lieu de rester sur un cadre mort.
  List<Channel> _candidates = const <Channel>[];
  int _candIndex = 0;

  /// Programme EPG en cours sur le héro (« En ce moment : … »), best-effort.
  String? _heroNow;

  Future<void> _recomputeHero() async {
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    if (all.isEmpty) {
      if (mounted) setState(() => _hero = null);
      return;
    }
    final Map<String, Channel> byId = _byId(all);
    // « MA SOIRÉE » : la chaîne la plus regardée DANS CE CRÉNEAU (heure ± 1,
    // même type de jour). Sur une TV partagée, le contexte temporel prédit
    // mieux que n'importe quel profil (recherche 2024) — et tout reste sur
    // l'appareil (zéro cloud). Signal insuffisant → repli dernière regardée.
    try {
      final DateTime now = DateTime.now();
      if (_slotAt == null ||
          now.difference(_slotAt!) > const Duration(minutes: 10)) {
        _slotId = await WatchHistoryRepository.instance.topChannelForSlot();
        _slotAt = now;
      }
    } catch (_) {
      // historique indisponible → replis classiques (récents/favoris)
    }
    // Ordre d'affection + fiabilité (brique pure hero_picker, testée) :
    // les chaînes que la box SAIT défaillantes passent en dernier recours.
    final List<Channel> candidates = heroCandidates(
      all: all,
      byId: byId,
      slotId: _slotId,
      recents: RecentlyWatchedRepository.instance.current,
      favorites: FavoritesRepository.instance.current,
      isFlaky: ChannelReliability.instance.isFlaky,
    );
    if (candidates.isEmpty) return;
    final Channel hero = candidates.first;
    final bool habit = _slotId != null && hero.id == _slotId;
    if (mounted && (_hero?.id != hero.id || _heroFromHabit != habit)) {
      setState(() {
        _candidates = candidates;
        _candIndex = 0;
        _hero = hero;
        _heroFromHabit = habit;
      });
      unawaited(_refreshHeroNow(hero));
    } else {
      _candidates = candidates;
    }
  }

  /// Bascule sur le candidat SUIVANT quand l'aperçu signale que la chaîne
  /// est injouable (résolution/erreur/aucune image — cf. TvLivePreview
  /// .onUnavailable). Une seule passe sur la liste, jamais de boucle.
  void _advanceHero() {
    if (!mounted) return;
    final int next = _candIndex + 1;
    if (next >= _candidates.length) return; // dernier recours : on reste
    setState(() {
      _candIndex = next;
      _hero = _candidates[next];
      _heroFromHabit = false;
    });
    unawaited(_refreshHeroNow(_candidates[next]));
  }

  /// « En ce moment : … » sous le nom du héro (EPG locale, cache 60 s).
  Future<void> _refreshHeroNow(Channel hero) async {
    String? title;
    try {
      title = (await EpgRepository.instance.currentProgram(hero.id))?.title;
    } catch (_) {
      title = null; // EPG absente → la ligne ne s'affiche pas, c'est tout
    }
    if (mounted && _hero?.id == hero.id && title != _heroNow) {
      setState(() => _heroNow = title);
    }
  }

  /// Navigation vers un écran (Cinéma, Guide, Séries…). L'aperçu héro
  /// est une SurfaceView en HYBRID COMPOSITION : pousser une route sans
  /// la retirer d'abord laisse sa DERNIÈRE TRAME « percer » par-dessus
  /// le nouvel écran (terrain 2026-07-16 : la petite vidéo d'accueil
  /// restait incrustée sur Cinéma — l'accueil reste monté sous la
  /// route, et le RouteAware de TvLivePreview arrive une frame trop
  /// tard). Même garde que _play : on libère la surface sur une frame
  /// PROPRE avant le push, puis on ré-arme l'aperçu au retour.
  Future<void> _open(Widget screen) async {
    setState(() => _previewLive = false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    // Material TRANSPARENT : certains écrans poussés (Cinéma, modèles
    // d'accueil…) n'ont pas de Scaffold à eux — sans Material ancêtre,
    // leurs textes partent en secours Flutter (jaune souligné, monospace).
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            Material(type: MaterialType.transparency, child: screen)));
    if (mounted) setState(() => _previewLive = true);
  }

  /// Lecture plein écran : l'aperçu héro est LIBÉRÉ d'abord (l'accueil reste
  /// monté sous la route poussée — sans ça, 2 flux resteraient ouverts).
  Future<void> _play(List<Channel> list, int index) async {
    setState(() => _previewLive = false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TvPlayerScreen(channels: list, startIndex: index),
    ));
    if (mounted) setState(() => _previewLive = true);
  }

  void _playHero() {
    final Channel? ch = _hero;
    if (ch == null) return;
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    final int idx = all.indexWhere((Channel c) => c.id == ch.id);
    _play(all, idx < 0 ? 0 : idx);
  }

  Future<void> _confirmExit() async {
    final bool? quit = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        backgroundColor: TvTokens.card,
        title: Text('Quitter SEVEN ?',
            style: TvTokens.ui(TvDimens.title, weight: FontWeight.w700)),
        actions: <Widget>[
          TextButton(
            // Focus initial (audit D5) : sans lui le 1er OK est avalé.
            autofocus: true,
            onPressed: () => Navigator.pop(d, false),
            child: Text('Annuler', style: TvTokens.ui(TvDimens.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text('Quitter',
                style: TvTokens.ui(TvDimens.body, color: TvTokens.goldBright)),
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
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        _confirmExit();
      },
      child: Container(
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
              padding: const EdgeInsets.symmetric(
                horizontal: TvDimens.safeH,
                vertical: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _topBar(),
                  const SizedBox(height: 14),
                  // ---- HÉRO (aperçu direct) + FAVORIS ----
                  Expanded(
                    flex: 5,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(flex: 3, child: _heroPane()),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: _favoritesPane()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ---- 5 GRANDES TUILES ----
                  SizedBox(height: 104, child: _navTiles()),
                  const SizedBox(height: 16),
                  // ---- DERNIERS FILMS AJOUTÉS ----
                  Expanded(flex: 3, child: _RecentMoviesRail(onPlaySuspend: () {
                    // Un film s'ouvre → l'aperçu héro est libéré aussi.
                    setState(() => _previewLive = false);
                  }, onResume: () {
                    if (mounted) setState(() => _previewLive = true);
                  })),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Barre du haut : logo + raccourcis + horloge ----
  Widget _topBar() {
    return Row(
      children: <Widget>[
        const TvLogo(width: 116),
        const Spacer(),
        _TopIcon(
            icon: Icons.people_alt_rounded,
            tip: 'Compte',
            onSelect: () => _open(const TvProfilesScreen())),
        _TopIcon(
            icon: Icons.swap_horiz_rounded,
            tip: 'Source',
            onSelect: () => _open(const TvSourcesScreen())),
        _TopIcon(
            icon: Icons.grid_view_rounded,
            tip: 'Guide TV',
            onSelect: () => _open(const TvGuideGridScreen())),
        _TopIcon(
            icon: Icons.dashboard_customize_rounded,
            tip: 'Templates',
            onSelect: () => _open(const TvHomeTemplateScreen())),
        _TopIcon(
            icon: Icons.settings_rounded,
            tip: 'Réglages',
            onSelect: () => _open(const TvSettingsScreen())),
        _TopIcon(
            icon: Icons.power_settings_new_rounded,
            tip: 'Quitter',
            onSelect: _confirmExit),
        const SizedBox(width: 10),
        // Widget FEUILLE (patron _Clock de rails) : l'horloge se met à jour
        // toute seule — l'ancien Timer du State racine reconstruisait
        // l'ACCUEIL ENTIER (héro + grille favoris + tuiles, ~200 widgets)
        // une fois par minute pour changer un Text.
        const _LauncherClock(),
      ],
    );
  }

  // ---- Héro : aperçu vidéo de la dernière chaîne + « Regarder maintenant »
  Widget _heroPane() {
    final Channel? ch = _hero;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TvTokens.card,
        borderRadius: BorderRadius.circular(TvDimens.panelRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: ch == null
          ? const Center(child: TvLogo(width: 160))
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // L'aperçu vidéo réutilise TOUTE la mécanique de l'écran En
                // direct (muet, anti-rebond, repli logo, relais 1-connexion).
                // PETITE BOX (Fire TV Stick & co) : pas de vidéo permanente
                // sur l'accueil — le logo de la chaîne suffit, la RAM et le
                // décodeur restent disponibles pour la lecture réelle.
                if (TvMemoryGuard.instance.lowSpec)
                  Center(
                      child: TvChannelLogo(
                          logoUrl: ch.logoUrl,
                          label: ch.name,
                          size: 110,
                          radius: 14))
                else
                  TvLivePreview(
                    channel: ch,
                    enabled: _previewLive,
                    // Chaîne injouable (morte côté fournisseur, photo
                    // terrain) → l'accueil bascule sur le candidat suivant
                    // au lieu de garder un grand cadre sans vie.
                    onUnavailable: _advanceHero,
                  ),
                // Bandeau bas : nom de la chaîne + bouton, sur un voile
                // sombre pour rester lisible par-dessus la vidéo.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 26, 16, 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Colors.transparent, Color(0xCC08080A)],
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        // Badge « MA SOIRÉE » : l'app a DEVINÉ cette chaîne
                        // d'après vos habitudes à cette heure (100 % local).
                        if (_heroFromHabit) ...<Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: TvTokens.gold,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('MA SOIRÉE',
                                style: TvTokens.ui(11,
                                    weight: FontWeight.w800,
                                    color: TvTokens.onGold,
                                    spacing: 1.2)),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(ch.cleanName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TvTokens.ui(TvDimens.title,
                                      weight: FontWeight.w800,
                                      color: TvTokens.text)),
                              // « En ce moment : … » (EPG locale) — UNE
                              // ligne bornée, comme l'exige la règle
                              // anti-pliage (bug photo du même jour).
                              if (_heroNow != null && _heroNow!.isNotEmpty)
                                Text('En ce moment : $_heroNow',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TvTokens.ui(TvDimens.label,
                                        color: TvTokens.muted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        TvFocusBuilder(
                          autofocus: true,
                          scale: TvFocusScale.small,
                          onSelect: _playHero,
                          builder: (BuildContext context, bool focused) {
                            final Color bg =
                                focused ? TvTokens.gold : TvTokens.sel;
                            final Color fg = focused
                                ? TvTokens.onGold
                                : TvTokens.goldBright;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius:
                                    BorderRadius.circular(TvDimens.cardRadius),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(Icons.play_arrow_rounded,
                                      color: fg, size: 22),
                                  const SizedBox(width: 6),
                                  Text('Regarder maintenant',
                                      style: TvTokens.ui(TvDimens.body,
                                          weight: FontWeight.w800, color: fg)),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ---- Coin « Chaînes Favorites » : grille 3 colonnes ----
  Widget _favoritesPane() {
    return _Panel(
      title: 'Chaînes Favorites',
      icon: Icons.star_rounded,
      child: _FavoritesGrid(onPlay: _play),
    );
  }

  // ---- Les 5 grandes tuiles ----
  Widget _navTiles() {
    return Row(
      children: <Widget>[
        Expanded(
            child: _NavTile(
                icon: Icons.live_tv_rounded,
                label: 'En direct',
                // FOCUS GARANTI : si le héro n'existe pas encore (aucune
                // source / playlist en cours d'ingestion), l'autofocus du
                // bouton « Regarder maintenant » n'existe pas non plus — la
                // télécommande serait morte à l'arrivée. Repli ici.
                autofocus: _hero == null,
                onSelect: () => _open(const TvChannelsScreen()))),
        const SizedBox(width: 14),
        Expanded(
            child: _NavTile(
                icon: Icons.movie_rounded,
                label: 'Films',
                onSelect: () => _open(const TvFilmsScreen()))),
        const SizedBox(width: 14),
        Expanded(
            child: _NavTile(
                icon: Icons.video_library_rounded,
                label: 'Séries',
                onSelect: () => _open(const TvSeriesScreen()))),
        const SizedBox(width: 14),
        Expanded(
            child: _NavTile(
                icon: Icons.replay_circle_filled_rounded,
                label: 'Replay',
                onSelect: () => _open(const TvRecordingsScreen()))),
        const SizedBox(width: 14),
        Expanded(
            child: _NavTile(
                icon: Icons.search_rounded,
                label: 'Rechercher',
                onSelect: () => _open(const TvSearchScreen()))),
      ],
    );
  }
}

// =========================================================
//  Briques locales
// =========================================================

/// Panneau SEVEN générique (titre + contenu) — même langage que l'écran
/// « En direct » (carte sombre, hairline, titre uppercase discret).
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TvTokens.card.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(TvDimens.panelRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: TvTokens.gold, size: 16),
              const SizedBox(width: 6),
              Text(title.toUpperCase(),
                  style: TvTokens.ui(12,
                      weight: FontWeight.w700,
                      color: TvTokens.mutedDim,
                      spacing: 1.4)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Grille des favoris (3 colonnes, logo + nom) — se met à jour en direct.
class _FavoritesGrid extends StatefulWidget {
  const _FavoritesGrid({required this.onPlay});
  final Future<void> Function(List<Channel> list, int index) onPlay;

  @override
  State<_FavoritesGrid> createState() => _FavoritesGridState();
}

class _FavoritesGridState extends State<_FavoritesGrid> {
  List<Channel> _favs = <Channel>[];
  StreamSubscription<Set<String>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FavoritesRepository.instance.favoritesStream
        .listen((Set<String> _) => _recompute());
    _recompute();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Jeton anti-course : requêtes SQL concurrentes possibles si deux
  /// événements favoris se suivent — seule la plus récente écrit.
  int _recomputeGen = 0;

  Future<void> _recompute() async {
    final int gen = ++_recomputeGen;
    final Set<String> ids = FavoritesRepository.instance.current;
    if (ids.isEmpty) {
      if (mounted) setState(() => _favs = <Channel>[]);
      return;
    }
    // Requêtes SQL ponctuelles (patron tv_live_screen) au lieu d'une Map
    // id→Channel de TOUT le bouquet reconstruite à chaque toggle ★ (O(N)
    // sur 10-50 k chaînes pour 9 tuiles). L'ordre des favoris est préservé.
    final Map<String, Channel> byId = <String, Channel>{
      for (final Channel c in await PlaylistRepository.instance
          .getChannelsByExternalIds(ids.toList(growable: false)))
        c.id: c,
    };
    final List<Channel> out = <Channel>[
      for (final String id in ids)
        if (byId[id] != null) byId[id]!,
    ];
    if (mounted && gen == _recomputeGen) {
      setState(() => _favs = out.take(9).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_favs.isEmpty) {
      return Center(
        child: Text('Ajoutez des favoris avec ★\ndepuis « En direct »',
            textAlign: TextAlign.center,
            style: TvTokens.ui(TvDimens.caption, color: TvTokens.muted)),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.35,
      ),
      itemCount: _favs.length,
      itemBuilder: (BuildContext c, int i) {
        final Channel ch = _favs[i];
        return TvFocusBuilder(
          scale: TvFocusScale.small,
          onSelect: () => widget.onPlay(_favs, i),
          builder: (BuildContext c, bool f) => Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: f ? TvTokens.sel : TvTokens.tile,
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: f ? TvTokens.gold : TvTokens.hairline),
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ch.hasLogo
                      ? CachedNetworkImage(
                          imageUrl: ch.logoUrl!,
                          fit: BoxFit.contain,
                          // Décodage BORNÉ : un logo de grille fait ~60 px —
                          // décoder le PNG 1000×1000 du panel gaspillait des
                          // Mo de RAM par tuile (anti-fermeture).
                          memCacheWidth: 160,
                          memCacheHeight: 160,
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.live_tv_rounded,
                              color: TvTokens.muted,
                              size: 22),
                        )
                      : const Icon(Icons.live_tv_rounded,
                          color: TvTokens.muted, size: 22),
                ),
                const SizedBox(height: 4),
                Text(ch.cleanName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.ui(11,
                        weight: FontWeight.w600, color: TvTokens.text)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Grande tuile de navigation (En direct, Films, …) — carte SEVEN, focus or.
class _NavTile extends StatelessWidget {
  const _NavTile(
      {required this.icon,
      required this.label,
      required this.onSelect,
      this.autofocus = false});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.medium,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? TvTokens.sel : TvTokens.card,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: focused ? TvTokens.gold : TvTokens.hairline,
                width: focused ? 2 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon,
                  size: 34,
                  color: focused ? TvTokens.goldBright : TvTokens.text),
              const SizedBox(height: 8),
              Text(label,
                  style: TvTokens.ui(TvDimens.body,
                      weight: FontWeight.w700,
                      color: focused ? TvTokens.text : TvTokens.muted)),
            ],
          ),
        );
      },
    );
  }
}

/// Rail « Derniers films ajoutés » : affiches horizontales. Sans VOD (playlist
/// M3U pure), le rail se replie — accueil propre.
class _RecentMoviesRail extends StatefulWidget {
  const _RecentMoviesRail(
      {required this.onPlaySuspend, required this.onResume});
  final VoidCallback onPlaySuspend;
  final VoidCallback onResume;

  @override
  State<_RecentMoviesRail> createState() => _RecentMoviesRailState();
}

class _RecentMoviesRailState extends State<_RecentMoviesRail> {
  List<VodMovie> _movies = const <VodMovie>[];
  bool _loaded = false;

  /// Chargement DIFFÉRÉ (4 s) : au boot, la box digère déjà l'ingestion de
  /// la playlist + l'aperçu héro. Charger le catalogue VOD au même moment
  /// ajoutait un pic mémoire au pire instant (stabilité box faible RAM).
  Timer? _deferred;

  @override
  void initState() {
    super.initState();
    _deferred = Timer(const Duration(seconds: 4), () => unawaited(_load()));
  }

  @override
  void dispose() {
    _deferred?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final List<VodMovie> all = await VodRepository.instance.fetchMovies();
      // « Derniers ajoutés » : id numérique DÉCROISSANT (les panels Xtream
      // numérotent par ordre d'ajout). SÉLECTION DES 14 PLUS RÉCENTS SANS
      // TRIER TOUT LE CATALOGUE : l'ancien tri complet de 50 000 films —
      // avec une regex à CHAQUE comparaison — gelait l'accueil. Ici une
      // seule passe O(n) : on garde les 14 plus grands ids, insertion bornée.
      const int keep = 14;
      final List<VodMovie> top = <VodMovie>[];
      final List<int> keys = <int>[]; // id numérique parallèle à `top`
      void bubbleUp(int i) {
        while (i > 0 && keys[i - 1] < keys[i]) {
          final int tk = keys[i - 1];
          keys[i - 1] = keys[i];
          keys[i] = tk;
          final VodMovie tm = top[i - 1];
          top[i - 1] = top[i];
          top[i] = tm;
          i--;
        }
      }

      for (final VodMovie m in all) {
        final int k = _numericId(m.id);
        if (top.length < keep) {
          top.add(m);
          keys.add(k);
          bubbleUp(top.length - 1);
        } else if (k > keys[keep - 1]) {
          top[keep - 1] = m;
          keys[keep - 1] = k;
          bubbleUp(keep - 1);
        }
      }
      if (mounted) {
        setState(() {
          _movies = top;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true); // pas de VOD → rail replié
    }
  }

  static int _numericId(String id) {
    // Extraction manuelle (pas de RegExp — appelée par film, doit être
    // légère) : 1er groupe de chiffres de l'id « vod-12345 ».
    int start = -1;
    for (int i = 0; i < id.length; i++) {
      final int c = id.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) {
        start = i;
        break;
      }
    }
    if (start < 0) return 0;
    int val = 0;
    for (int i = start; i < id.length; i++) {
      final int c = id.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) break;
      val = val * 10 + (c - 0x30);
      if (val > 2000000000) break; // borne anti-débordement
    }
    return val;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _movies.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('DERNIERS FILMS AJOUTÉS',
            style: TvTokens.ui(12,
                weight: FontWeight.w700,
                color: TvTokens.mutedDim,
                spacing: 1.4)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Marge de construction élargie (audit D20) : traversée D-pad
            // fiable jusqu'au bout du rail sur box lente.
            cacheExtent: 600,
            itemCount: _movies.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (BuildContext c, int i) {
              final VodMovie m = _movies[i];
              // Fraction déjà vue (barre en bas d'affiche) — null si jamais
              // entamé. Lecture O(1) dans le repo (≤ 100 entrées).
              final double? prog =
                  PlaybackPositionRepository.instance.progressFor(m.id);
              return TvFocusBuilder(
                scale: TvFocusScale.small,
                onSelect: () async {
                  widget.onPlaySuspend();
                  await WidgetsBinding.instance.endOfFrame;
                  if (!c.mounted) return;
                  await Navigator.of(c).push(MaterialPageRoute<void>(
                      builder: (_) => TvMovieDetailScreen(movie: m)));
                  widget.onResume();
                },
                builder: (BuildContext c, bool f) => AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: TvTokens.tile,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: f ? TvTokens.gold : TvTokens.hairline,
                          width: f ? 2 : 1),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (m.posterUrl != null && m.posterUrl!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: m.posterUrl!,
                            fit: BoxFit.cover,
                            // Affiche ~110×165 px à l'écran : décodage borné
                            // (les jaquettes TMDB font souvent 2000 px).
                            memCacheWidth: 240,
                            memCacheHeight: 360,
                            errorWidget: (_, __, ___) =>
                                _posterFallback(m.name),
                          )
                        else
                          _posterFallback(m.name),
                        // BARRE DE PROGRESSION (lot accro, effet « envie de
                        // finir ») : fraction déjà vue en bas de l'affiche —
                        // même motif que l'écran Films. Absente si jamais
                        // entamé. `prog` est calculé en tête d'itemBuilder.
                        if (prog != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: SizedBox(
                              height: 5,
                              child: Stack(
                                children: <Widget>[
                                  Container(
                                      color: Colors.black
                                          .withValues(alpha: 0.55)),
                                  FractionallySizedBox(
                                    widthFactor: prog.clamp(0.04, 1.0),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                          gradient: TvTokens.cineGradient),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _posterFallback(String name) => Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(name,
              maxLines: 3,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.ui(11,
                  weight: FontWeight.w600, color: TvTokens.muted)),
        ),
      );
}

/// Petit bouton-icône de la barre du haut (Compte, Réglages, Quitter…).
class _TopIcon extends StatelessWidget {
  const _TopIcon(
      {required this.icon, required this.tip, required this.onSelect});
  final IconData icon;
  final String tip;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: TvFocusBuilder(
        scale: TvFocusScale.small,
        onSelect: onSelect,
        builder: (BuildContext context, bool focused) => Tooltip(
          message: tip,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: focused ? TvTokens.sel : TvTokens.card,
              shape: BoxShape.circle,
              border: Border.all(
                  color: focused ? TvTokens.gold : TvTokens.hairline),
            ),
            child: Icon(icon,
                size: 19,
                color: focused ? TvTokens.goldBright : TvTokens.muted),
          ),
        ),
      ),
    );
  }
}

/// Horloge du coin haut-droit — widget FEUILLE autonome (patron _Clock de
/// tv_rails_home_screen) : son tic ne reconstruit que ce Text.
class _LauncherClock extends StatefulWidget {
  const _LauncherClock();

  @override
  State<_LauncherClock> createState() => _LauncherClockState();
}

class _LauncherClockState extends State<_LauncherClock> {
  late String _clock = _fmt();
  Timer? _timer;

  static String _fmt() => DateFormat.Hm().format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final String now = _fmt();
      if (now != _clock && mounted) setState(() => _clock = now);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_clock,
        style: TvTokens.ui(TvDimens.title,
            weight: FontWeight.w700, color: TvTokens.text));
  }
}
