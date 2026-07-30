// =========================================================
//  tv_launcher_home_screen.dart — Accueil « salon » (structure IBO, robe SEVEN)
// =========================================================
//  STRUCTURE demandée par le client (référence : accueil IBO Player Pro) :
//    • en haut à gauche  : APERÇU VIDÉO EN DIRECT de la dernière chaîne
//      regardée + bouton « Regarder maintenant » ;
//    • en haut à droite  : grille « Chaînes Favorites » (accès direct) ;
//    • au centre         : 5 grandes tuiles — En direct, Films, Séries,
//      Replay, Rechercher ;
//    • en bas            : rail « Derniers films ajoutés » + rangée
//      « Reprendre » (dernières chaînes regardées — repliée sans historique).
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

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../channels/data/watch_history_repository.dart';
import '../../channels/domain/channel.dart';
import '../../playlists/data/favorites_repository.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../security/data/parental_controls.dart';
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
import 'tv_screensaver.dart';
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

  /// Tuile de navigation à RE-FOCUSER au retour d'un écran poussé (BACK).
  /// Sans ça, revenir d'un contenu (En direct, Films…) pouvait laisser le
  /// focus filer ailleurs (autofocus du bouton héro) au lieu de la tuile
  /// qu'on avait quittée. Même mécanisme déterministe que tv_live_screen /
  /// tv_channels_screen (`restoreFocusId`) : on désigne la tuile, elle reprend
  /// le focus en post-frame, puis on libère le drapeau.
  String? _restoreFocusId;

  void _clearRestore() {
    if (_restoreFocusId != null) setState(() => _restoreFocusId = null);
  }

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

  /// Jeton anti-course (même patron que _FavoritesGrid) : deux événements
  /// playlist/zapping rapprochés lancent deux _recomputeHero async — sans
  /// jeton, le PLUS LENT (parti sur l'ANCIENNE liste de chaînes, avant un
  /// changement de source) pouvait écraser le résultat frais et laisser en
  /// héro une chaîne d'une source supprimée (aperçu/lecture morts).
  int _heroGen = 0;

  Map<String, Channel> _byId(List<Channel> all) {
    if (!identical(all, _byIdSource)) {
      _byIdSource = all;
      _byIdCache = <String, Channel>{for (final Channel c in all) c.id: c};
    }
    return _byIdCache!;
  }

  Future<void> _recomputeHero() async {
    final int gen = ++_heroGen;
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    if (all.isEmpty) {
      if (mounted) setState(() => _hero = null);
      return;
    }
    final Map<String, Channel> byId = _byId(all);
    Channel? hero;
    bool habit = false;
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
      if (_slotId != null) {
        hero = byId[_slotId];
        habit = hero != null;
      }
    } catch (_) {
      // historique indisponible → replis classiques ci-dessous
    }
    if (hero == null) {
      for (final String id in RecentlyWatchedRepository.instance.current) {
        hero = byId[id];
        if (hero != null) break;
      }
    }
    if (hero == null) {
      for (final String id in FavoritesRepository.instance.current) {
        hero = byId[id];
        if (hero != null) break;
      }
    }
    hero ??= all.first;
    // Seule la passe la plus RÉCENTE écrit (cf. _heroGen ci-dessus).
    if (gen != _heroGen) return;
    if (mounted && (_hero?.id != hero.id || _heroFromHabit != habit)) {
      setState(() {
        _hero = hero;
        _heroFromHabit = habit;
      });
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
  Future<void> _open(Widget screen, {String? restoreId}) async {
    setState(() => _previewLive = false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    // Material TRANSPARENT : certains écrans poussés (Cinéma, modèles
    // d'accueil…) n'ont pas de Scaffold à eux — sans Material ancêtre,
    // leurs textes partent en secours Flutter (jaune souligné, monospace).
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            Material(type: MaterialType.transparency, child: screen)));
    if (!mounted) return;
    // RETOUR (BACK) : on ré-arme l'aperçu et, si l'appel désigne une tuile de
    // navigation, on la RE-FOCUSE (BACK revient sur la tuile quittée).
    setState(() {
      _previewLive = true;
      if (restoreId != null) _restoreFocusId = restoreId;
    });
  }

  /// Lecture plein écran : l'aperçu héro est LIBÉRÉ d'abord (l'accueil reste
  /// monté sous la route poussée — sans ça, 2 flux resteraient ouverts).
  Future<void> _play(List<Channel> list, int index,
      {bool restoreFocus = true}) async {
    // Id de la chaîne lancée → au RETOUR (BACK), on re-focuse SA carte
    // (favori / « Reprendre ») au lieu de laisser le focus filer sur le
    // premier élément. Corrige « BACK repart en haut ». Le héro, lui, est
    // l'élément par défaut : il se ré-autofocuse tout seul (restoreFocus:false
    // → _restoreFocusId reste null → autofocus héro actif).
    final String? restoreId = restoreFocus &&
            index >= 0 &&
            index < list.length
        ? list[index].id
        : null;
    setState(() => _previewLive = false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TvPlayerScreen(channels: list, startIndex: index),
    ));
    if (!mounted) return;
    setState(() {
      _previewLive = true;
      if (restoreId != null) _restoreFocusId = restoreId;
    });
  }

  void _playHero() {
    final Channel? ch = _hero;
    if (ch == null) return;
    final List<Channel> all = PlaylistRepository.instance.currentChannels;
    final int idx = all.indexWhere((Channel c) => c.id == ch.id);
    // Héro = élément par défaut → pas de restauration ciblée : au retour, le
    // bouton héro reprend naturellement le focus (autofocus conditionnel).
    _play(all, idx < 0 ? 0 : idx, restoreFocus: false);
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
      // ÉCRAN DE VEILLE anti burn-in (parité accueil Classique) : ce
      // template garde un APERÇU VIDÉO permanent — sans veilleur, une box
      // laissée 10 min sur l'accueil marquait la dalle OLED. Le watcher ne
      // s'arme que quand l'accueil est la route visible (garde-fou interne).
      child: TvScreensaverWatcher(
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
                  // ---- REPRENDRE (récemment regardé) ----
                  // Hauteur INTRINSÈQUE (pas d'Expanded) : la rangée se
                  // replie ENTIÈREMENT sans historique — aucun trou. La
                  // lecture passe par _play (aperçu héro suspendu d'abord :
                  // jamais 2 flux).
                  _ResumeRail(
                      onPlay: _play,
                      restoreFocusId: _restoreFocusId,
                      onRestored: _clearRestore),
                ],
              ),
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
                  TvLivePreview(channel: ch, enabled: _previewLive),
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
                          child: Text(ch.cleanName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TvTokens.ui(TvDimens.title,
                                  weight: FontWeight.w800,
                                  color: TvTokens.text)),
                        ),
                        const SizedBox(width: 12),
                        TvFocusBuilder(
                          // Ne prend le focus au démarrage QUE s'il n'y a pas
                          // de position à restaurer. Au RETOUR d'une chaîne,
                          // _restoreFocusId est posé → ce bouton ne rafle plus
                          // le focus (« BACK repart en haut » corrigé).
                          autofocus: _restoreFocusId == null,
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
      child: _FavoritesGrid(
          onPlay: _play,
          restoreFocusId: _restoreFocusId,
          onRestored: _clearRestore),
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
                // Identité stable → re-focus au retour (BACK).
                restoreId: 'live',
                restoreFocusId: _restoreFocusId,
                onRestored: _clearRestore,
                onSelect: () =>
                    _open(const TvChannelsScreen(), restoreId: 'live'))),
        const SizedBox(width: 14),
        Expanded(
            child: _NavTile(
                icon: Icons.movie_rounded,
                label: 'Films',
                restoreId: 'films',
                restoreFocusId: _restoreFocusId,
                onRestored: _clearRestore,
                onSelect: () =>
                    _open(const TvFilmsScreen(), restoreId: 'films'))),
        const SizedBox(width: 14),
        Expanded(
            child: _NavTile(
                icon: Icons.video_library_rounded,
                label: 'Séries',
                restoreId: 'series',
                restoreFocusId: _restoreFocusId,
                onRestored: _clearRestore,
                onSelect: () =>
                    _open(const TvSeriesScreen(), restoreId: 'series'))),
        const SizedBox(width: 14),
        Expanded(
            child: _NavTile(
                icon: Icons.replay_circle_filled_rounded,
                label: 'Replay',
                restoreId: 'replay',
                restoreFocusId: _restoreFocusId,
                onRestored: _clearRestore,
                onSelect: () =>
                    _open(const TvRecordingsScreen(), restoreId: 'replay'))),
        const SizedBox(width: 14),
        Expanded(
            child: _NavTile(
                icon: Icons.search_rounded,
                label: 'Rechercher',
                restoreId: 'search',
                restoreFocusId: _restoreFocusId,
                onRestored: _clearRestore,
                onSelect: () =>
                    _open(const TvSearchScreen(), restoreId: 'search'))),
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
  const _FavoritesGrid(
      {required this.onPlay, this.restoreFocusId, this.onRestored});
  final Future<void> Function(List<Channel> list, int index) onPlay;

  /// Chaîne à re-focuser au retour (BACK) : sa carte reprend le focus.
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  @override
  State<_FavoritesGrid> createState() => _FavoritesGridState();
}

class _FavoritesGridState extends State<_FavoritesGrid> {
  List<Channel> _favs = <Channel>[];
  StreamSubscription<Set<String>>? _sub;
  StreamSubscription<List<Channel>>? _chanSub;

  @override
  void initState() {
    super.initState();
    _sub = FavoritesRepository.instance.favoritesStream
        .listen((Set<String> _) => _recompute());
    // La grille dépend AUSSI de la PLAYLIST (requête SQL sur `channels`) :
    // au boot elle se calcule souvent AVANT la fin de l'ingestion (0 ligne
    // en base → grille vide) et un changement de source n'émettait rien ici
    // → favoris invisibles/périmés jusqu'au redémarrage. Même double écoute
    // (favoris + chaînes) que l'écran « En direct » (tv_live_screen).
    _chanSub = PlaylistRepository.instance.channelsStream
        .listen((List<Channel> _) => _recompute());
    _recompute();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _chanSub?.cancel();
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
        return _PlayFocusCard(
          key: ValueKey<String>('fav-${ch.id}'),
          restoreFocus: ch.id == widget.restoreFocusId,
          onRestored: widget.onRestored,
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
                          // Placeholder = même icône que l'erreur (taille
                          // fixe → zéro saut) + fade court : le logo se
                          // fond en douceur au lieu de « pop ». Revue V1.
                          fadeInDuration: const Duration(milliseconds: 150),
                          placeholder: (_, __) => const Icon(
                              Icons.live_tv_rounded,
                              color: TvTokens.muted,
                              size: 22),
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

/// Carte qui LIT une chaîne (favori / « Reprendre ») et sait REPRENDRE le
/// focus au retour (BACK), comme _NavTile pour les tuiles de navigation.
/// Sans FocusNode propre, impossible de re-focuser la bonne carte : c'est ce
/// qui manquait au Lanceur (« BACK repartait en haut »).
class _PlayFocusCard extends StatefulWidget {
  const _PlayFocusCard({
    super.key,
    required this.builder,
    required this.onSelect,
    this.scale = TvFocusScale.small,
    this.restoreFocus = false,
    this.onRestored,
  });
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback onSelect;
  final TvFocusScale scale;

  /// true = cette carte est la chaîne quittée → elle reprend le focus.
  final bool restoreFocus;
  final VoidCallback? onRestored;

  @override
  State<_PlayFocusCard> createState() => _PlayFocusCardState();
}

class _PlayFocusCardState extends State<_PlayFocusCard> {
  final FocusNode _node = FocusNode(debugLabel: 'play-focus-card');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RESTAURATION au retour (BACK) : si on est la chaîne quittée, on reprend
    // le focus en post-frame puis on libère le drapeau. Déterministe → survit
    // à l'autofocus du bouton héro (désarmé tant qu'une restauration est due).
    if (widget.restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.restoreFocus) return;
        _node.requestFocus();
        widget.onRestored?.call();
      });
    }
    return TvFocusBuilder(
      focusNode: _node,
      scale: widget.scale,
      onSelect: widget.onSelect,
      builder: widget.builder,
    );
  }
}

/// Grande tuile de navigation (En direct, Films, …) — carte SEVEN, focus or.
class _NavTile extends StatefulWidget {
  const _NavTile(
      {required this.icon,
      required this.label,
      required this.onSelect,
      this.autofocus = false,
      this.restoreId,
      this.restoreFocusId,
      this.onRestored});
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  /// Identité STABLE de cette tuile (ex. 'live') : sert à la RE-FOCUSER au
  /// retour d'un écran poussé (BACK), via restoreFocusId.
  final String? restoreId;

  /// Tuile désignée par l'accueil pour reprendre le focus au retour (BACK).
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  /// FocusNode PROPRE : nécessaire pour rendre le focus à la tuile au retour.
  final FocusNode _node = FocusNode(debugLabel: 'nav-tile');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RESTAURATION DU FOCUS au retour d'un écran (BACK) : si l'accueil nous
    // DÉSIGNE (restoreFocusId == notre restoreId), on reprend le focus en
    // post-frame puis on libère le drapeau. Déterministe → survit à
    // l'autofocus du bouton héro qui, sinon, pouvait capter le focus.
    if (widget.restoreId != null &&
        widget.restoreFocusId != null &&
        widget.restoreFocusId == widget.restoreId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.restoreFocusId == widget.restoreId) {
          _node.requestFocus();
          widget.onRestored?.call();
        }
      });
    }
    return TvFocusBuilder(
      focusNode: _node,
      autofocus: widget.autofocus,
      scale: TvFocusScale.medium,
      onSelect: widget.onSelect,
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
              Icon(widget.icon,
                  size: 34,
                  color: focused ? TvTokens.goldBright : TvTokens.text),
              const SizedBox(height: 8),
              Text(widget.label,
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
    // Le catalogue VOD est un ChangeNotifier (stale-while-revalidate) : le
    // rafraîchissement réseau silencieux et l'invalidation M3U (changement
    // de source) notifient APRÈS notre chargement unique — sans écoute, le
    // rail restait vide (1er boot, catalogue arrivé du réseau ensuite) ou
    // périmé (ancienne source) jusqu'au redémarrage. Le _load de relance
    // répond depuis la mémoire du dépôt : aucun re-réseau.
    VodRepository.instance.addListener(_onCatalogChanged);
  }

  void _onCatalogChanged() {
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    _deferred?.cancel();
    VodRepository.instance.removeListener(_onCatalogChanged);
    super.dispose();
  }

  /// Jeton anti-course (patron _FavoritesGrid) : timer différé + notification
  /// catalogue peuvent se chevaucher — seule la passe la plus récente écrit.
  int _loadGen = 0;

  Future<void> _load() async {
    if (!mounted) return;
    final int gen = ++_loadGen;
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
      if (mounted && gen == _loadGen) {
        setState(() {
          _movies = top;
          _loaded = true;
        });
      }
    } catch (_) {
      // pas de VOD → rail replié
      if (mounted && gen == _loadGen) setState(() => _loaded = true);
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
            itemCount: _movies.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (BuildContext c, int i) {
              final VodMovie m = _movies[i];
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
                    child: (m.posterUrl != null && m.posterUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: m.posterUrl!,
                            fit: BoxFit.cover,
                            // Affiche ~110×165 px à l'écran : décodage borné
                            // (les jaquettes TMDB font souvent 2000 px).
                            memCacheWidth: 240,
                            memCacheHeight: 360,
                            // Placeholder = même repli (titre) que l'erreur,
                            // même taille → zéro saut ; fade court. Revue V1.
                            fadeInDuration:
                                const Duration(milliseconds: 150),
                            placeholder: (_, __) => _posterFallback(m.name),
                            errorWidget: (_, __, ___) =>
                                _posterFallback(m.name),
                          )
                        : _posterFallback(m.name),
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

/// Rangée « Reprendre » : les dernières chaînes regardées, comme la rangée
/// « Reprendre » de l'écran En direct (tv_live_screen). MÊME source et MÊMES
/// règles : RecentlyWatchedRepository (IDs, plus récent d'abord), résolution
/// par external_id (requête BORNÉE, jamais de scan du bouquet), filtre Mode
/// Enfants, 8 cartes max. OK = lecture de la liste « récents » à l'index de
/// la carte (mêmes paramètres que le rail du Direct), via _play de l'écran
/// (l'aperçu héro est suspendu d'abord). Repliée ENTIÈREMENT quand vide.
class _ResumeRail extends StatefulWidget {
  const _ResumeRail(
      {required this.onPlay, this.restoreFocusId, this.onRestored});
  final Future<void> Function(List<Channel> list, int index) onPlay;

  /// Chaîne à re-focuser au retour (BACK) : sa carte reprend le focus.
  final String? restoreFocusId;
  final VoidCallback? onRestored;

  @override
  State<_ResumeRail> createState() => _ResumeRailState();
}

class _ResumeRailState extends State<_ResumeRail> {
  List<Channel> _recent = const <Channel>[];
  StreamSubscription<List<String>>? _sub;
  StreamSubscription<List<Channel>>? _chanSub;

  /// Même borne que la rangée « Reprendre » du Direct (~8 dernières chaînes).
  static const int _kMax = 8;

  /// Jeton anti-course (patron _FavoritesGrid) : deux événements rapprochés
  /// (zapping + playlist) lancent deux _recompute — seule la passe la plus
  /// récente écrit.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    // Historique en direct : chaque chaîne ouverte remonte en tête du rail.
    _sub = RecentlyWatchedRepository.instance.stream
        .listen((List<String> _) => _recompute());
    // Même DOUBLE écoute que _FavoritesGrid : la résolution id→Channel
    // dépend de la PLAYLIST (requête SQL sur `channels`) — au boot comme au
    // changement de source, c'est ce flux qui rend le rail affichable/frais.
    _chanSub = PlaylistRepository.instance.channelsStream
        .listen((List<Channel> _) => _recompute());
    // Mode Enfants : re-filtrage immédiat quand le parent (dés)active.
    ParentalControls.instance.kidsMode.addListener(_recompute);
    _recompute();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _chanSub?.cancel();
    ParentalControls.instance.kidsMode.removeListener(_recompute);
    super.dispose();
  }

  Future<void> _recompute() async {
    final int gen = ++_gen;
    final List<String> ids = RecentlyWatchedRepository.instance.current;
    if (ids.isEmpty) {
      if (mounted) setState(() => _recent = const <Channel>[]);
      return;
    }
    // Résolution BORNÉE par external_id (patron tv_live_screen), puis remise
    // dans l'ordre HISTORIQUE (le plus récent d'abord), pas l'ordre playlist.
    final Map<String, Channel> byId = <String, Channel>{
      for (final Channel c in await PlaylistRepository.instance
          .getChannelsByExternalIds(ids))
        c.id: c,
    };
    final bool kids = ParentalControls.instance.kidsMode.value;
    final List<Channel> out = <Channel>[];
    for (final String id in ids) {
      final Channel? c = byId[id];
      if (c == null) continue; // chaîne disparue de la source → carte omise
      if (kids && c.genre == ChannelGenre.adult) continue;
      out.add(c);
      if (out.length == _kMax) break;
    }
    if (mounted && gen == _gen) setState(() => _recent = out);
  }

  @override
  Widget build(BuildContext context) {
    // Repliée ENTIÈREMENT quand vide : ni titre orphelin, ni trou (le
    // SizedBox.shrink ne réserve aucune hauteur dans la colonne).
    if (_recent.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Même clé l10n que la rangée « Reprendre » du Direct, même style
          // de titre que « DERNIERS FILMS AJOUTÉS » juste au-dessus.
          Text(context.l10n.resumeEyebrow,
              style: TvTokens.ui(12,
                  weight: FontWeight.w700,
                  color: TvTokens.mutedDim,
                  spacing: 1.4)),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (BuildContext c, int i) {
                final Channel ch = _recent[i];
                return _PlayFocusCard(
                  key: ValueKey<String>('resume-${ch.id}'),
                  restoreFocus: ch.id == widget.restoreFocusId,
                  onRestored: widget.onRestored,
                  // OK = lecture : liste « récents » + index, comme le rail
                  // du Direct (_openPlayerWith(recentList, i)).
                  onSelect: () => widget.onPlay(_recent, i),
                  builder: (BuildContext c, bool f) => Container(
                    width: 210,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    // Même langage que les tuiles favorites du Lanceur
                    // (fond tile, hairline, focus sel + liseré or).
                    decoration: BoxDecoration(
                      color: f ? TvTokens.sel : TvTokens.tile,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: f ? TvTokens.gold : TvTokens.hairline),
                    ),
                    child: Row(
                      children: <Widget>[
                        // TvChannelLogo : décodage borné + monogramme de
                        // repli intégrés (jamais de carte vide).
                        TvChannelLogo(
                            logoUrl: ch.logoUrl,
                            label: ch.cleanName,
                            size: 44,
                            radius: 8),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(ch.cleanName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TvTokens.ui(12,
                                  weight: FontWeight.w600,
                                  color: TvTokens.text)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
