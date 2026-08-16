// =========================================================
//  tv_films_screen.dart — Films (VOD) 10-foot, présentation « Netflix »
// =========================================================
//  Onglet FILMS refondu façon Netflix :
//    • en HAUT : une grande AFFICHE VEDETTE (le dernier film vu, sinon le
//      premier du catalogue) avec titre, année/note et bouton ▶ Regarder ;
//    • en dessous : des RANGÉES HORIZONTALES défilables au D-pad —
//      d'abord « Derniers vus » (mémoire locale), puis une rangée PAR
//      catégorie du catalogue.
//
//  PERF (box RAM limitée) : tout est PARESSEUX. La liste verticale des
//  rangées est un ListView.builder (seules les rangées visibles existent),
//  et chaque rangée est un ListView.builder horizontal (seules les affiches
//  visibles sont construites). Les affiches passent par CachedNetworkImage
//  avec memCacheWidth (déjà la règle dans l'app). Le catalogue vient de
//  VodRepository (cache mémoire PLAFONNÉ selon la RAM — inchangé).
//
//  Données : VodRepository.fetchMovies(). S'il n'y a pas de VOD → message.
//  Zéro contact avec le lecteur vidéo (on pousse TvPlayerScreen comme avant).
//
//  NAVIGATION (façon Netflix) : OK sur une AFFICHE ouvre la FICHE DÉTAIL
//  (tv_movie_detail_screen — synopsis, casting, backdrop) et la lecture se
//  lance depuis la fiche. Deux exceptions voulues : la rangée « Continuer à
//  regarder » reprend DIRECTEMENT la lecture (un seul OK), et le bouton
//  ▶ Regarder de la vedette lance aussi direct (c'est un bouton de lecture
//  explicite, pas une vignette).
// =========================================================
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/curation/title_curator.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../vod/data/playback_position_repository.dart';
import '../../vod/data/recent_vod_repository.dart';
import '../../vod/data/vod_novelty_service.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/data/vod_taste.dart';
import '../../vod/data/vod_watchlist_repository.dart';
import '../../vod/domain/vod_info.dart';
import '../../vod/domain/vod_movie.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_poster_prefetch.dart';
import '../core/tv_cine_route.dart';
import '../core/tv_tokens.dart';
import '../core/vod_titles.dart';
import '../data/cine_perf.dart';
import '../data/greeting_repository.dart';
import '../../vod/data/vod_download_service.dart';
import 'tv_components.dart';
import 'tv_movie_detail_screen.dart';
import 'tv_player_screen.dart';

class TvFilmsScreen extends StatefulWidget {
  const TvFilmsScreen({super.key});

  @override
  State<TvFilmsScreen> createState() => _TvFilmsScreenState();
}

class _TvFilmsScreenState extends State<TvFilmsScreen> {
  // ----- MÉMOIRE D'ÉTAT ENTRE ONGLETS (zéro jank au retour) -----
  //  L'accueil classique RECONSTRUIT l'onglet à chaque sélection du menu
  //  (pas d'IndexedStack — voulu : une box 1 Go ne garde pas 4 onglets
  //  vivants). Ces statiques survivent à la reconstruction :
  //   - _bucket  : offsets de scroll (vertical + chaque rangée) via
  //     PageStorage — on retrouve la page EXACTEMENT où on l'a laissée ;
  //   - _focusRail/_focusIndex : dernière affiche focusée → ré-autofocus
  //     au retour (mémoire du focus par rangée, pattern Netflix).
  static final PageStorageBucket _bucket = PageStorageBucket();
  static String? _focusRail;
  static int _focusIndex = 0;

  bool _loading = true;
  List<VodMovie> _all = const <VodMovie>[];
  List<String> _cats = const <String>[];
  Map<String, List<VodMovie>> _byCat = const <String, List<VodMovie>>{};
  List<VodMovie> _recent = const <VodMovie>[];
  List<VodMovie> _watchlist = const <VodMovie>[];
  // Ids des films NOUVEAUX (apparus dans le catalogue depuis la dernière
  // visite) → rangée « Nouveautés » + pastille NOUVEAU sur les affiches.
  Set<String> _newIds = <String>{};
  // Ids présents dans « Ma Liste » (repère rapide pour l'affichage du ✓).
  Set<String> _inList = <String>{};

  // Fiche du film VEDETTE, chargée en tâche de fond après le catalogue :
  // sert le BACKDROP (image paysage) et le synopsis du bandeau cinéma
  // plein cadre. `_heroInfoId` mémorise POUR QUEL film cette fiche a été
  // demandée → si la vedette change (nouveau « dernier vu ») on ignore une
  // réponse périmée et on recharge. Absent / sans backdrop → repli sur le
  // bandeau classique (affiche à droite), aucune régression.
  VodInfo? _heroInfo;
  String? _heroInfoId;

  @override
  void initState() {
    super.initState();
    // Budget « premier rendu utile < 400 ms » : chrono démarré ICI, arrêté
    // à la première frame AFFICHÉE avec des données (cf. build).
    CinePerf.start(CinePerf.homeFirstRender);
    // La rangée « Continuer à regarder » et les barres de progression sous
    // les affiches se rafraîchissent TOUTES SEULES quand une position change
    // (sauvegarde périodique du lecteur, sortie de lecture) — sans ça, la
    // barre resterait figée jusqu'au prochain rechargement du catalogue.
    PlaybackPositionRepository.instance.addListener(_onPositionsChanged);
    // RAFRAÎCHISSEMENT SILENCIEUX (façon Netflix) : l'écran s'ouvre
    // instantanément sur le cache disque ; quand le catalogue frais arrive
    // du réseau (stale-while-revalidate du VodRepository), on regroupe et on
    // met à jour SANS spinner ni à-coup.
    VodRepository.instance.addListener(_onCatalogRefreshed);
    // La rangée « Téléchargés » apparaît/disparaît au rythme des
    // téléchargements terminés (fin de fichier, suppression auto d'un
    // épisode vu par les téléchargements intelligents…).
    VodDownloadService.instance.addListener(_onPositionsChanged);
    _load();
  }

  @override
  void dispose() {
    // Écran quitté avant le premier rendu utile → mesure abandonnée
    // (une durée d'interruption ne veut rien dire).
    CinePerf.cancel(CinePerf.homeFirstRender);
    PlaybackPositionRepository.instance.removeListener(_onPositionsChanged);
    VodRepository.instance.removeListener(_onCatalogRefreshed);
    VodDownloadService.instance.removeListener(_onPositionsChanged);
    super.dispose();
  }

  void _onCatalogRefreshed() {
    // Le repo a déjà le catalogue frais en mémoire : _load() y répond
    // instantanément (aucun réseau) et ne fait que regrouper + setState.
    if (mounted) _load(silent: true);
  }

  void _onPositionsChanged() {
    // Les données (entries/progress) sont lues directement dans build().
    if (mounted) setState(() {});
  }

  Future<void> _load({bool force = false, bool silent = false}) async {
    // Libellé du rayon « Autres » capturé AVANT les await (contexte sûr).
    final String othersLabel = context.l10n.tvOthers;
    // [silent] = mise à jour en arrière-plan : on NE remontre PAS le
    // squelette — l'écran actuel reste affiché jusqu'au setState final.
    if (mounted && !silent) setState(() => _loading = true);
    final List<VodMovie> movies =
        await VodRepository.instance.fetchMovies(forceRefresh: force);
    await RecentVodRepository.instance.load();
    await VodWatchlistRepository.instance.load();
    // Positions de reprise (« Continuer à regarder ») : chargées une seule
    // fois — le vrai load() est branché au démarrage, ceci est un filet.
    await PlaybackPositionRepository.instance.ensureLoaded();
    if (!mounted) return;
    // Groupement UNE fois par catégorie (ordre d'apparition). Les listes
    // référencent les mêmes objets VodMovie → pas de duplication mémoire.
    final List<String> cats = <String>[];
    final Map<String, List<VodMovie>> byCat = <String, List<VodMovie>>{};
    for (final VodMovie m in movies) {
      final String c =
          m.category.trim().isEmpty ? othersLabel : m.category.trim();
      final List<VodMovie>? existing = byCat[c];
      if (existing == null) {
        cats.add(c);
        byCat[c] = <VodMovie>[m];
      } else {
        existing.add(m);
      }
    }
    // NOUVEAUTÉS : réconcilie les ids du catalogue avec l'historique de
    // nouveauté (apparitions). Best-effort, en arrière-plan — l'accueil ne
    // l'attend pas ; le setState final le rafraîchit dès que c'est prêt.
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    unawaited(VodNoveltyService.instance
        .reconcileMovies(movies.map((VodMovie m) => m.id), nowMs: nowMs)
        .then((Set<String> fresh) {
      if (mounted) setState(() => _newIds = fresh);
    }));
    setState(() {
      _all = movies;
      _cats = cats;
      _byCat = byCat;
      _recent = RecentVodRepository.instance.items;
      _watchlist = VodWatchlistRepository.instance.items;
      _inList = _watchlist.map((VodMovie m) => m.id).toSet();
      _loading = false;
    });
    // Catalogue prêt → on demande en tâche de fond le BACKDROP du film
    // vedette (même règle que la fiche : appel get_vod_info mis en cache
    // LRU). Le bandeau s'ouvre tout de suite en repli, puis passe en mode
    // cinéma plein cadre dès que l'image de fond arrive — sans à-coup.
    if (_all.isNotEmpty) {
      final VodMovie hero = _pickHero();
      unawaited(_ensureHeroInfo(hero));
    }
  }


  /// VEDETTE façon billboard Netflix (recherche 2026-07-17, guidelines
  /// Android TV « featured carousel ») : le grand visuel du haut est un
  /// contenu CURÉ — il doit TOUJOURS avoir une image. On garde la
  /// priorité « dernier vu », mais on saute les entrées sans jaquette
  /// (sources pauvres en métadonnées) : plus jamais un trou noir avec
  /// trois boutons qui flottent. Si vraiment RIEN n'a d'image, le rendu
  /// de repli du bandeau (dégradé + grand titre) prend le relais.
  /// Salutation selon l'heure + météo si déjà en cache (« Bonsoir · 21°
  /// Paris »). Zéro appel réseau : on lit seulement ce qui est là.
  String _greeting(BuildContext context) {
    final int h = DateTime.now().hour;
    final String hello = h >= 18 || h < 5
        ? (h < 5 ? context.l10n.tvGreetNight : context.l10n.tvGreetEvening)
        : context.l10n.tvGreetMorning;
    final Greeting? g = GreetingRepository.instance.current;
    if (g == null) return hello;
    final String temp = g.tempC == null ? '' : '${g.tempC!.round()}°';
    final String meteo = <String>[
      if (g.emoji.isNotEmpty || temp.isNotEmpty) '${g.emoji} $temp'.trim(),
      if (g.city.isNotEmpty) g.city,
    ].join(' · ');
    return meteo.isEmpty ? hello : '$hello · $meteo';
  }

  /// Minutes restantes d'une reprise (null si pas de reprise pour cet id, ou
  /// durée inconnue). Sert au bouton « Reprendre · 23 min » du héros.
  int? _remainingMinutes(String id) {
    final PlaybackPosition? e =
        PlaybackPositionRepository.instance.entryFor(id);
    if (e == null || e.durationMs <= 0) return null;
    final int remMs = e.durationMs - e.positionMs;
    if (remMs <= 60000) return null; // ~fini → « Regarder » classique
    return (remMs / 60000).ceil();
  }

  /// « SURPRENDS-MOI » : lance instantanément un film choisi pour le client.
  /// Priorité à une reprise en cours (on reprend là où il en était) ; sinon
  /// tirage pondéré par ses catégories préférées. Zéro écran de choix.
  void _surpriseMe() {
    // 1) Une reprise en cours ? On relance la plus récente (envie n°1).
    final List<PlaybackPosition> resume =
        PlaybackPositionRepository.instance.entries;
    if (resume.isNotEmpty) {
      _playResume(resume.first);
      return;
    }
    // 2) Sinon, tirage pondéré par le goût. Aléa 0..1 dérivé de l'horloge
    //    (varie à chaque appui, aucun Random importé).
    if (_all.isEmpty) return;
    final Map<String, double> aff = VodTaste.affinity(
        recent: _recent, watchlist: _watchlist);
    final double rng =
        (DateTime.now().microsecondsSinceEpoch % 100000) / 100000.0;
    final int idx =
        VodTaste.surpriseIndex(_all, affinity: aff, rngUnit: rng);
    if (idx >= 0) _play(<VodMovie>[_all[idx]], 0);
  }

  VodMovie _pickHero() {
    bool hasArt(VodMovie m) => (m.posterUrl ?? '').isNotEmpty;
    for (final VodMovie m in _recent) {
      if (hasArt(m)) return m;
    }
    for (final VodMovie m in _all) {
      if (hasArt(m)) return m;
    }
    return _recent.isNotEmpty ? _recent.first : _all.first;
  }

  /// Charge (une fois) la fiche du film vedette pour son backdrop paysage.
  /// Idempotent : deux _load() rapprochés sur le même héros ne relancent
  /// pas l'appel. Protège contre les réponses périmées si la vedette change.
  Future<void> _ensureHeroInfo(VodMovie hero) async {
    if (_heroInfoId == hero.id) return; // déjà chargé / en cours pour ce film
    _heroInfoId = hero.id;
    final VodInfo? info = await VodRepository.instance.fetchInfo(hero.id);
    if (!mounted || _heroInfoId != hero.id) return; // vedette changée entre-temps
    setState(() => _heroInfo = info);
  }

  /// Ajoute/retire [m] de « Ma Liste » (par profil) et rafraîchit l'affichage.
  Future<void> _toggleList(VodMovie m) async {
    await VodWatchlistRepository.instance.toggle(m);
    if (!mounted) return;
    setState(() {
      _watchlist = VodWatchlistRepository.instance.items;
      _inList = _watchlist.map((VodMovie e) => e.id).toSet();
    });
  }

  /// Adapte un film en Channel pour le lecteur (ExoPlayer lit l'URL du fichier).
  Channel _asChannel(VodMovie m) {
    // HORS-LIGNE : si le film est déjà téléchargé, on lit le FICHIER LOCAL
    // (file://) au lieu du flux réseau → lecture sans connexion (avion, train)
    // et démarrage instantané. Le lecteur natif gère nativement file:// (cf.
    // NativeVideoView.kt). Sinon, flux réseau habituel (comportement inchangé).
    final String? local = VodDownloadService.instance.localFile(m.id);
    final String url =
        (local != null) ? File(local).uri.toString() : m.streamUrl;
    return Channel(
      id: m.id,
      name: m.name,
      category: m.category,
      streamUrl: url,
      isLive: false,
      logoUrl: m.posterUrl,
    );
  }

  /// Lance la lecture de [list] à partir de [index], et mémorise le film dans
  /// « Derniers vus ». Au retour du lecteur, on rafraîchit la rangée.
  void _play(List<VodMovie> list, int index) {
    RecentVodRepository.instance.add(list[index]);
    final List<Channel> channels =
        list.map(_asChannel).toList(growable: false);
    // Budget « Regarder → première frame < 2,5 s » : chrono depuis L'APPUI.
    CinePerf.start(CinePerf.playToFirstFrame);
    Navigator.of(context)
        .push(TvCineRoute<void>(
          builder: (_) => TvPlayerScreen(channels: channels, startIndex: index),
        ))
        .then((_) {
      if (mounted) {
        setState(() => _recent = RecentVodRepository.instance.items);
      }
    });
  }

  /// OK sur une vignette de film → FICHE DÉTAIL (façon Netflix) : synopsis,
  /// casting, backdrop, et c'est LÀ que la lecture se lance. Au retour, on
  /// rafraîchit « Derniers vus » ET « Ma Liste » (les deux peuvent avoir
  /// changé depuis la fiche : lecture lancée, toggle Ma Liste).
  void _openDetail(VodMovie m) {
    Navigator.of(context)
        .push(TvCineRoute<void>(
          builder: (_) => TvMovieDetailScreen(movie: m),
        ))
        .then((_) {
      if (!mounted) return;
      setState(() {
        _recent = RecentVodRepository.instance.items;
        _watchlist = VodWatchlistRepository.instance.items;
        _inList = _watchlist.map((VodMovie e) => e.id).toSet();
      });
    });
  }

  /// Lance un contenu de la rangée « Continuer à regarder ». Le SEEK vers la
  /// position sauvegardée est fait par le LECTEUR lui-même (il consulte
  /// PlaybackPositionRepository à l'ouverture) — ici on ne fait que lancer.
  void _playResume(PlaybackPosition e) {
    // Film encore au catalogue → chemin normal (_play) : on profite du
    // fichier local éventuel (hors-ligne) et de la mémoire « Derniers vus ».
    for (final VodMovie m in _all) {
      if (m.id == e.key) {
        _play(<VodMovie>[m], 0);
        return;
      }
    }
    // Épisode de série (ou film disparu du catalogue) : lecture directe
    // depuis les métadonnées mémorisées avec la position — pas besoin de
    // re-télécharger la fiche série pour reprendre son épisode.
    final Channel c = Channel(
      id: e.key,
      name: e.name,
      category: '',
      streamUrl: e.streamUrl,
      isLive: false,
      logoUrl: e.posterUrl,
    );
    CinePerf.start(CinePerf.playToFirstFrame);
    Navigator.of(context).push(
      TvCineRoute<void>(
        builder: (_) =>
            TvPlayerScreen(channels: <Channel>[c], startIndex: 0),
      ),
    );
  }

  /// Adapte une entrée de reprise en VodMovie D'AFFICHAGE (vignette de la
  /// rangée « Continuer à regarder ») — jamais persisté tel quel.
  static VodMovie _entryAsMovie(PlaybackPosition e) => VodMovie(
        id: e.key,
        name: e.name,
        category: '',
        streamUrl: e.streamUrl,
        containerExt: 'mp4',
        posterUrl: e.posterUrl,
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // Squelette « respirant » : la structure de la page (vedette +
      // rangées) apparaît tout de suite — perception de fluidité premium.
      return const TvSkeletonRails(withHero: true, rails: 2);
    }
    if (_all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.movie_outlined, size: 52, color: TvTokens.mutedDim),
            const SizedBox(height: 14),
            Text(context.l10n.tvNavFilms,
                style: TvTokens.display(26, color: TvTokens.text)),
            const SizedBox(height: 8),
            Text(context.l10n.tvFilmsEmpty,
                textAlign: TextAlign.center,
                style: TvTokens.ui(15, color: TvTokens.mutedDim)),
          ],
        ),
      );
    }

    // Film mis en avant : le dernier vu, sinon le premier du catalogue.
    final VodMovie hero = _pickHero();
    // Backdrop + synopsis du bandeau cinéma : uniquement si la fiche chargée
    // correspond BIEN au héros courant (sinon on afficherait l'image d'un
    // autre film le temps que la bonne fiche arrive).
    final bool heroInfoReady = _heroInfoId == hero.id;
    final String? heroBackdrop = heroInfoReady ? _heroInfo?.backdropUrl : null;
    final String? heroPlot = heroInfoReady ? _heroInfo?.plot : null;

    // Reprises en cours (« Continuer à regarder ») : lues directement dans le
    // repo (≤ 100 entrées triées, O(1)) — films ET épisodes de séries.
    final List<PlaybackPosition> resume =
        PlaybackPositionRepository.instance.entries;
    final List<VodMovie> resumeMovies =
        resume.map(_entryAsMovie).toList(growable: false);
    // Fraction déjà vue par contenu → petite barre dorée sous l'affiche,
    // sur TOUTES les rangées (un film entamé se repère aussi dans sa
    // catégorie, comme sur Netflix). Map minuscule (≤ 100 entrées).
    final Map<String, double> progress = <String, double>{
      for (final PlaybackPosition e in resume) e.key: e.progress,
    };

    // SCORE « X % POUR VOUS » : affinité de catégorie bâtie sur l'historique
    // (derniers vus + Ma Liste). Calculée UNE fois ici, lue par chaque
    // affiche. Vide si pas d'historique → aucun score affiché (honnête).
    final Map<String, double> affinity = VodTaste.affinity(
        recent: _recent, watchlist: _watchlist);
    final double maxAffinity = affinity.isEmpty
        ? 0
        : affinity.values.reduce((double a, double b) => a > b ? a : b);

    // Rangées, dans l'ordre façon Netflix : Continuer à regarder (si non
    // vide), puis Ma Liste, puis Derniers vus, puis une rangée par catégorie.
    // On les assemble en une liste ordonnée → pas d'arithmétique d'index
    // fragile. `resume: true` = la rangée lance via _playResume (et n'a pas
    // de « Ma Liste » au long-press : une entrée peut être un épisode).
    // Rangée « Téléchargés » : contenus PRÊTS hors-ligne (films + épisodes),
    // synthétisés en VodMovie pour réutiliser les affiches telles quelles.
    // L'URL reste la distante : le lecteur substitue le fichier local tout
    // seul (localFile) → OK = lecture INSTANTANÉE, zéro réseau.
    final List<VodMovie> dlMovies = <VodMovie>[
      for (final VodDownload d in VodDownloadService.instance.all)
        if (d.isComplete)
          VodMovie(
            id: d.id,
            name: d.name,
            category: d.isEpisode ? d.groupName : d.category,
            streamUrl: d.streamUrl,
            containerExt: '',
            posterUrl: d.posterUrl,
            year: d.year,
            rating: d.rating,
          ),
    ];

    // NOUVEAUTÉS : films apparus dans le catalogue depuis la dernière visite
    // (raison n°1 de rouvrir l'app — recherche rétention). Ordre catalogue,
    // borné pour rester léger.
    final List<VodMovie> newMovies = _newIds.isEmpty
        ? const <VodMovie>[]
        : <VodMovie>[
            for (final VodMovie m in _all)
              if (_newIds.contains(m.id)) m,
          ].take(24).toList(growable: false);

    // « PARCE QUE VOUS AVEZ REGARDÉ … » : rang de reco personnalisé, le
    // cœur addictif de Netflix. On prend le DERNIER film vu et on propose
    // d'autres titres de sa catégorie (hors ce qu'il a déjà vu). 100 % local.
    List<VodMovie> becauseMovies = const <VodMovie>[];
    String becauseTitle = '';
    if (_recent.isNotEmpty) {
      final VodMovie seed = _recent.first;
      final String cat = seed.category.trim();
      if (cat.isNotEmpty) {
        final Set<String> seen = _recent.map((VodMovie m) => m.id).toSet();
        becauseMovies = <VodMovie>[
          for (final VodMovie m in (_byCat[cat] ?? const <VodMovie>[]))
            if (!seen.contains(m.id)) m,
        ].take(24).toList(growable: false);
        becauseTitle = context.l10n.tvRailBecause(VodTitles.clean(seed.name));
      }
    }

    final List<({String title, List<VodMovie> movies, bool resume, bool dl})>
        rails =
        <({String title, List<VodMovie> movies, bool resume, bool dl})>[
      if (resumeMovies.isNotEmpty)
        (
          title: context.l10n.tvRailContinueWatching,
          movies: resumeMovies,
          resume: true,
          dl: false
        ),
      if (newMovies.isNotEmpty)
        (
          title: context.l10n.tvRailNew,
          movies: newMovies,
          resume: false,
          dl: false
        ),
      if (becauseMovies.isNotEmpty)
        (
          title: becauseTitle,
          movies: becauseMovies,
          resume: false,
          dl: false
        ),
      if (dlMovies.isNotEmpty)
        (
          title: context.l10n.tvDlRail,
          movies: dlMovies,
          resume: false,
          dl: true
        ),
      if (_watchlist.isNotEmpty)
        (
          title: context.l10n.tvMyList,
          movies: _watchlist,
          resume: false,
          dl: false
        ),
      if (_recent.isNotEmpty)
        (
          title: context.l10n.tvRailRecent,
          movies: _recent,
          resume: false,
          dl: false
        ),
      for (final String cat in _cats)
        (
          title: TitleCurator.curateCategory(cat),
          movies: _byCat[cat] ?? const <VodMovie>[],
          resume: false,
          dl: false
        ),
    ];

    // Budget « premier rendu utile < 400 ms » : première frame AFFICHÉE avec
    // des données → on arrête le chrono (post-frame = frame réellement rendue).
    if (CinePerf.isRunning(CinePerf.homeFirstRender)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CinePerf.end(CinePerf.homeFirstRender,
            detail: '${_all.length} films, ${rails.length} rangées');
      });
    }

    // Mémoire du focus par rangée : si une affiche était focusée avant la
    // reconstruction de l'onglet, c'est ELLE qui reprend l'autofocus (pas le
    // héros). Index clampé — le catalogue a pu changer entre-temps.
    final int memRail = rails.indexWhere(
        (({String title, List<VodMovie> movies, bool resume, bool dl}) r) =>
            r.title == _focusRail);

    return PageStorage(
      // Bucket STATIQUE : les offsets de scroll survivent à la reconstruction
      // de l'onglet (retour sur Cinéma = page exactement où on l'a laissée).
      bucket: _bucket,
      child: ListView.builder(
        key: const PageStorageKey<String>('films-vertical'),
        // La VEDETTE occupe l'index 0, les rangées suivent → tout est lazy.
        addAutomaticKeepAlives: false,
        itemCount: 1 + rails.length,
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return _HeroBanner(
              movie: hero,
              autofocus: memRail < 0,
              backdropUrl: heroBackdrop,
              plot: heroPlot,
              inList: _inList.contains(hero.id),
              resumeRemaining: _remainingMinutes(hero.id),
              greeting: _greeting(context),
              onPlay: () => _play(<VodMovie>[hero], 0),
              onToggleList: () => _toggleList(hero),
              onSurprise: _surpriseMe,
            );
          }
          final ({String title, List<VodMovie> movies, bool resume, bool dl})
              rail = rails[i - 1];
          return _Rail(
            railKey: PageStorageKey<String>('films-rail-${rail.title}'),
            title: rail.title,
            movies: rail.movies,
            inList: _inList,
            newIds: _newIds,
            affinity: affinity,
            maxAffinity: maxAffinity,
            progress: progress,
            // Ré-autofocus de l'affiche mémorisée (mémoire du focus par rangée).
            autofocusIndex: (i - 1) == memRail
                ? _focusIndex.clamp(0, rail.movies.length - 1)
                : null,
            // Mémorise l'affiche focusée ET pré-charge les jaquettes de la
            // RANGÉE SUIVANTE pendant qu'on navigue celle-ci (zéro carte grise
            // quand le focus descend — le pattern Netflix).
            onCardFocus: (int j) {
              _focusRail = rail.title;
              _focusIndex = j;
              final int next = i; // rails[i - 1] focusée → suivante = rails[i]
              if (next < rails.length) {
                TvPosterPrefetch.prefetchRow(
                  context,
                  <String?>[
                    for (final VodMovie m in rails[next].movies) m.posterUrl,
                  ],
                );
              }
            },
            // OK sur une affiche → FICHE détail. EXCEPTIONS Netflix : les
            // rangées « Continuer à regarder » et « Téléchargés » lancent
            // DIRECTEMENT la lecture (reprendre / lire hors-ligne en un OK).
            onPlay: (int j) => rail.resume
                ? _playResume(resume[j])
                : rail.dl
                    ? _play(<VodMovie>[rail.movies[j]], 0)
                    : _openDetail(rail.movies[j]),
            onToggleList: (int j) {
              // « Ma Liste » n'a pas de sens sur reprise/téléchargements
              // (entrées synthétiques, potentiellement des épisodes).
              if (!rail.resume && !rail.dl) _toggleList(rail.movies[j]);
            },
          );
        },
      ),
    );
  }
}

/// Grande affiche vedette (haut de page) : visuel + titre + méta + ▶ Regarder.
///
/// Deux rendus, choisis automatiquement :
///  • CINÉMA (façon Netflix) quand un backdrop paysage est disponible :
///    image plein cadre, voile sombre, titre + synopsis + boutons posés
///    en bas à gauche.
///  • CLASSIQUE en repli (pas de backdrop : source pauvre en métadonnées,
///    fiche pas encore arrivée…) : affiche à droite sur dégradé, comme avant.
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.movie,
    required this.onPlay,
    required this.inList,
    required this.onToggleList,
    required this.onSurprise,
    this.greeting,
    this.resumeRemaining,
    this.backdropUrl,
    this.plot,
    this.autofocus = false,
  });

  /// Salutation selon l'heure (« Bonsoir · 21° Paris ») posée en HAUT du
  /// bandeau — surimpression, donc zéro espace vertical en plus.
  final String? greeting;

  final VodMovie movie;
  final VoidCallback onPlay;
  final bool inList;
  final VoidCallback onToggleList;

  /// « Surprends-moi » : lance instantanément un film choisi pour le client.
  final VoidCallback onSurprise;

  /// Minutes restantes si la vedette est une REPRISE (le bouton devient
  /// « Reprendre · 23 min ») — null = film neuf (bouton « Regarder »).
  final int? resumeRemaining;

  /// Image de fond paysage (get_vod_info). `null` → rendu classique.
  final String? backdropUrl;

  /// Synopsis court affiché sous le titre dans le rendu cinéma (facultatif).
  final String? plot;
  final bool autofocus;

  /// Métadonnées compactes (année · note · catégorie) — communes aux 2 rendus.
  String get _meta => <String>[
        if (movie.year != null && movie.year!.isNotEmpty) movie.year!,
        if (movie.rating != null && movie.rating!.isNotEmpty)
          '★ ${movie.rating}',
        // CATÉGORIE CURÉE (photo client : « NETFLIX MOVIES ⁴▯ 3840▯▯▯▯ »
        // — la catégorie BRUTE du fournisseur s'affichait telle quelle,
        // carrés rayés compris, alors que le reste de l'app la nettoie.
        if (_prettyCategory.isNotEmpty) _prettyCategory,
      ].join('   ·   ');

  String get _prettyCategory =>
      TitleCurator.curateCategory(movie.category.trim()).trim();

  /// Rangée de boutons (Regarder / Ma Liste / Télécharger) — partagée par les
  /// deux rendus pour garder un comportement de focus identique.
  Widget _actions(BuildContext context) => Row(
        children: <Widget>[
          _HeroButton(
            icon: resumeRemaining != null
                ? Icons.play_arrow_rounded
                : Icons.play_arrow_rounded,
            // REPRISE PRÉCISE (premium) : « Reprendre · 23 min » au lieu d'un
            // simple « Regarder » quand la vedette est un film entamé.
            label: resumeRemaining != null
                ? context.l10n.tvResumeMinutes(resumeRemaining!)
                : context.l10n.tvWatch,
            autofocus: autofocus,
            primary: true,
            onSelect: onPlay,
          ),
          const SizedBox(width: 12),
          // « Surprends-moi » : un film choisi pour toi, lancé tout de suite.
          _HeroButton(
            icon: Icons.casino_rounded,
            label: context.l10n.tvSurprise,
            primary: false,
            onSelect: onSurprise,
          ),
          const SizedBox(width: 12),
          // « Ma Liste » : ajoute/retire le film vedette (par profil).
          _HeroButton(
            icon: inList ? Icons.check_rounded : Icons.add_rounded,
            label: inList ? context.l10n.tvInMyList : context.l10n.tvMyList,
            primary: false,
            onSelect: onToggleList,
          ),
          const SizedBox(width: 12),
          // « Télécharger » : garde le film pour le regarder hors-ligne.
          _HeroDownloadButton(movie: movie),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final bool cinematic = backdropUrl != null && backdropUrl!.isNotEmpty;
    return cinematic ? _buildCinematic(context) : _buildClassic(context);
  }

  // ----- Rendu CINÉMA : backdrop plein cadre + voile + contenu en bas -----
  Widget _buildCinematic(BuildContext context) {
    final String meta = _meta;
    return Container(
      // DENSITÉ « VIP » (terrain 2026-07-17) : le héros ne doit PLUS manger
      // la moitié de l'écran (un grand vide sombre + il fallait descendre
      // pour voir le cinéma). On le borne à ~38 % de la hauteur réelle du
      // canevas (≈ 274 px sur 720) → dès l'ouverture on voit le héros ET
      // deux rangées de films ensemble, sans toucher aux commandes.
      height: (MediaQuery.of(context).size.height * 0.38).clamp(230.0, 300.0),
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Fond : image paysage du film, plein cadre.
          CachedNetworkImage(
            imageUrl: backdropUrl!,
            fit: BoxFit.cover,
            // 1000 px : net sur une TV 1080p sans faire exploser la mémoire
            // image (un seul backdrop à la fois → coût négligeable).
            memCacheWidth: 1000,
            fadeInDuration: const Duration(milliseconds: 220),
            placeholder: (_, __) => const ColoredBox(color: TvTokens.card),
            errorWidget: (_, __, ___) => const ColoredBox(color: TvTokens.card),
          ),
          // Voile de GAUCHE : garantit la lisibilité du texte quel que soit
          // le backdrop (un film clair ne noierait pas le titre).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Color(0xF008080A),
                  Color(0x6608080A),
                  Color(0x00000000),
                ],
                stops: <double>[0.0, 0.5, 0.85],
              ),
            ),
          ),
          // Voile du BAS : ancre les boutons et fond le bandeau dans la page.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: <Color>[Color(0xE608080A), Color(0x00000000)],
                stops: <double>[0.0, 0.6],
              ),
            ),
          ),
          // Salutation selon l'heure, en haut à gauche (surimpression).
          if (greeting != null && greeting!.isNotEmpty)
            Positioned(
              top: 16,
              left: 30,
              child: Text(
                greeting!,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: TvTokens.text,
                    shadows: <Shadow>[
                      Shadow(blurRadius: 8, color: Color(0xCC000000)),
                    ]),
              ),
            ),
          // Contenu : titre + méta + synopsis + boutons, en bas à gauche.
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                ConstrainedBox(
                  // On borne la largeur du texte : il ne recouvre pas le
                  // visuel côté droit (le sujet du film reste visible).
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        VodTitles.clean(movie.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.display(32, color: TvTokens.text),
                      ),
                      if (meta.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TvTokens.ui(14, color: TvTokens.muted)),
                      ],
                      if (plot != null && plot!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(plot!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TvTokens.ui(14, color: TvTokens.muted)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _actions(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----- Rendu CLASSIQUE (repli) : affiche à droite sur dégradé -----
  Widget _buildClassic(BuildContext context) {
    final String meta = _meta;
    return Container(
      height: (MediaQuery.of(context).size.height * 0.30).clamp(180.0, 230.0),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TvDimens.cardRadius),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[TvTokens.sel, TvTokens.card],
        ),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: <Widget>[
          // ----- Infos + bouton -----
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    VodTitles.clean(movie.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.display(28, color: TvTokens.text),
                  ),
                  if (meta.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.ui(14, color: TvTokens.muted)),
                  ],
                  const SizedBox(height: 18),
                  _actions(context),
                ],
              ),
            ),
          ),
          // ----- Visuel (affiche à droite, plein cadre) -----
          SizedBox(
            width: 340,
            child: _HeroPoster(url: movie.posterUrl),
          ),
        ],
      ),
    );
  }
}

/// Bouton d'action de la vedette (▶ Regarder / + Ma Liste), focusable.
/// Bouton « Télécharger » de la vedette : écoute VodDownloadService pour
/// afficher l'état en direct (Télécharger → % → ✓ Téléchargé). OK :
/// démarre / met en pause / (si terminé) ne refait rien.
class _HeroDownloadButton extends StatelessWidget {
  const _HeroDownloadButton({required this.movie});
  final VodMovie movie;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VodDownloadService.instance,
      builder: (BuildContext context, _) {
        final VodDownload? d = VodDownloadService.instance.byId(movie.id);
        IconData icon = Icons.download_rounded;
        String label = context.l10n.tvDownload;
        VoidCallback onSelect =
            () => VodDownloadService.instance.downloadMovie(movie);
        if (d != null) {
          switch (d.status) {
            case VodDownloadStatus.done:
              icon = Icons.download_done_rounded;
              label = context.l10n.tvDownloaded;
              onSelect = () {};
            case VodDownloadStatus.downloading:
              icon = Icons.pause_rounded;
              label = context.l10n.tvPercent((d.progress * 100).round());
              onSelect = () => VodDownloadService.instance.pause(movie.id);
            case VodDownloadStatus.paused:
            case VodDownloadStatus.error:
            case VodDownloadStatus.queued:
            case VodDownloadStatus.noSpace:
              icon = Icons.download_rounded;
              label = context.l10n.tvResume;
              onSelect = () => VodDownloadService.instance.resume(movie.id);
          }
        }
        return _HeroButton(
          icon: icon,
          label: label,
          primary: false,
          onSelect: onSelect,
        );
      },
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.primary = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.small,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused
            ? TvTokens.ember
            : (primary ? TvTokens.emberBadgeBg : TvTokens.card);
        final Color fg = focused
            ? const Color(0xFF1A1206)
            : (primary ? TvTokens.emberBright : TvTokens.text);
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: primary ? TvTokens.ember : TvTokens.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: fg)),
            ],
          ),
        );
      },
    );
  }
}

class _HeroPoster extends StatelessWidget {
  const _HeroPoster({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    // Repli sans affiche : panneau décoratif dans le langage du thème
    // (braise sombre → obsidienne) — le bandeau garde une présence
    // visuelle, jamais un bloc gris mort à droite du titre.
    final Widget fallback = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[TvTokens.emberDeep, TvTokens.sel],
        ),
      ),
      child: Center(
        child: Icon(Icons.theaters_rounded,
            size: 44, color: TvTokens.emberBright),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      memCacheWidth: 480,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

/// Une RANGÉE horizontale d'affiches (titre + liste paresseuse), façon Netflix.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.title,
    required this.movies,
    required this.inList,
    required this.newIds,
    required this.affinity,
    required this.maxAffinity,
    required this.progress,
    required this.onPlay,
    required this.onToggleList,
    this.railKey,
    this.autofocusIndex,
    this.onCardFocus,
  });

  final String title;
  final List<VodMovie> movies;
  final Set<String> inList;

  /// Ids des films NOUVEAUX → pastille « NOUVEAU » en coin d'affiche.
  final Set<String> newIds;

  /// Affinité de catégorie (goût) + maximum, pour le score « X % pour vous ».
  final Map<String, double> affinity;
  final double maxAffinity;

  /// Fraction déjà vue par id de contenu (reprise de lecture) : dessine la
  /// petite barre dorée sous l'affiche. Absent de la map = rien à afficher.
  final Map<String, double> progress;
  final void Function(int index) onPlay;
  final void Function(int index) onToggleList;

  /// Clé PageStorage : l'offset de scroll horizontal de la rangée survit à
  /// la reconstruction de l'onglet (avec le bucket statique de l'écran).
  final PageStorageKey<String>? railKey;

  /// Affiche qui reprend l'autofocus au retour sur l'onglet (mémoire du
  /// focus par rangée) — null = aucune.
  final int? autofocusIndex;

  /// Notifie le focus d'une affiche (mémoire + pré-chargement rangée suivante).
  final void Function(int index)? onCardFocus;

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();
    return Padding(
      // Rangées resserrées (densité VIP) : moins d'air entre elles → on voit
      // plus de cinéma d'un coup, sans que ça paraisse tassé.
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TvTokens.ui(13,
                  weight: FontWeight.w700,
                  color: TvTokens.mutedDim,
                  spacing: 1.6),
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView.builder(
              key: railKey,
              scrollDirection: Axis.horizontal,
              addAutomaticKeepAlives: false,
              itemExtent: 132,
              itemCount: movies.length,
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                // RepaintBoundary : l'animation de focus (zoom/halo) d'une
                // affiche ne fait repeindre QU'ELLE, jamais toute la rangée
                // (économie GPU sensible sur box modeste, rangées longues).
                child: RepaintBoundary(
                  child: _PosterCard(
                    movie: movies[i],
                    inList: inList.contains(movies[i].id),
                    isNew: newIds.contains(movies[i].id),
                    matchPercent: VodTaste.matchPercent(movies[i],
                        affinity: affinity, maxAffinity: maxAffinity),
                    progress: progress[movies[i].id],
                    autofocus: i == autofocusIndex,
                    onFocus:
                        onCardFocus == null ? null : () => onCardFocus!(i),
                    onPlay: () => onPlay(i),
                    onToggleList: () => onToggleList(i),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Affiche d'un film (poster 2:3) + titre, focusable. OK = fiche détail
/// (sauf rangée « Continuer à regarder » : OK = reprise directe).
class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.movie,
    required this.inList,
    required this.onPlay,
    required this.onToggleList,
    this.isNew = false,
    this.matchPercent,
    this.progress,
    this.autofocus = false,
    this.onFocus,
  });
  final VodMovie movie;
  final bool inList;

  /// Film récemment apparu au catalogue → pastille « NOUVEAU » (coin haut
  /// gauche, opposée au ✓ « Ma Liste »).
  final bool isNew;

  /// Score « X % pour vous » (goût) — null = rien d'honnête à afficher.
  final int? matchPercent;
  final VoidCallback onPlay;
  final VoidCallback onToggleList;

  /// Fraction déjà vue (0..1) — null = pas de reprise en cours pour ce film.
  final double? progress;

  /// Reprend le focus au retour sur l'onglet (mémoire du focus par rangée).
  final bool autofocus;

  /// Notifie la prise de focus (mémoire + pré-chargement rangée suivante).
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
      autofocus: autofocus,
      onFocusChange: onFocus == null
          ? null
          : (bool focused) {
              if (focused) onFocus!();
            },
      onSelect: onPlay,
      // Appui LONG sur OK = ajouter/retirer de « Ma Liste » (façon Netflix).
      onLongPress: onToggleList,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _poster(),
                  // Barre de progression de REPRISE (façon Netflix) : filet
                  // doré en bas de l'affiche = fraction déjà vue. Même
                  // pattern Stack + FractionallySizedBox que la barre du
                  // lecteur (tv_player_screen) — zéro widget animé, zéro
                  // coût quand `progress` est null (rien n'est construit).
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        height: 5,
                        child: Stack(
                          children: <Widget>[
                            // Fond sombre : la barre se lit sur toute affiche.
                            Container(
                                color: Colors.black.withValues(alpha: 0.55)),
                            FractionallySizedBox(
                              // Jamais < 4 % : une reprise à 2 min d'un film
                              // de 3 h doit rester VISIBLE (repère « entamé »).
                              widthFactor: progress!.clamp(0.04, 1.0),
                              child: Container(
                                decoration: const BoxDecoration(
                                    gradient: TvTokens.cineGradient),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Pastille ✓ quand le film est dans « Ma Liste ».
                  if (inList)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: TvTokens.ember,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded,
                            size: 15, color: Color(0xFF1A1206)),
                      ),
                    ),
                  // Pastille « NOUVEAU » (coin haut gauche) — film apparu
                  // récemment dans le catalogue de la source.
                  if (isNew)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: TvTokens.cineGradient,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          context.l10n.tvBadgeNew,
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                              color: TvTokens.onEmber),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Score « X % pour vous » (goût) — discret, en ember, seulement
          // quand l'app a de quoi le dire honnêtement.
          if (matchPercent != null)
            Text(
              context.l10n.tvMatchPercent(matchPercent!),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: TvTokens.emberBright),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              // Titre CURÉ (TitleCurator) : « EN | Barney's G… » → « Barney's
              // Great Adventure ». L'id et la recherche gardent le nom brut.
              VodTitles.clean(movie.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: TvDimens.caption,
                  fontWeight: FontWeight.w600,
                  color: TvTokens.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _poster() {
    // REPLI OFFICIEL (guidelines Android TV « immersive list » : image
    // manquante → couleur de fond du thème + TEXTE LISIBLE) : une affiche
    // absente devient une carte sombre avec le TITRE écrit dessus — comme
    // Netflix quand l'artwork manque. Fini la tuile grise anonyme.
    final Widget fallback = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[TvTokens.sel, TvTokens.tile],
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.movie_rounded, size: 22, color: TvTokens.mutedDim),
          const SizedBox(height: 8),
          Text(
            VodTitles.clean(movie.name),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: TvDimens.caption,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: TvTokens.text),
          ),
        ],
      ),
    );
    final String? url = movie.posterUrl;
    if (url == null || url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 300,
      // Fade court uniforme (150 ms, comme les tuiles des rails) — le
      // défaut (500 ms) traînait. Revue images V1.
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}
