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

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../vod/data/playback_position_repository.dart';
import '../../vod/data/recent_vod_repository.dart';
import '../../vod/data/vod_repository.dart';
import '../../vod/data/vod_watchlist_repository.dart';
import '../../vod/domain/vod_info.dart';
import '../../vod/domain/vod_movie.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
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
  bool _loading = true;
  List<VodMovie> _all = const <VodMovie>[];
  List<String> _cats = const <String>[];
  Map<String, List<VodMovie>> _byCat = const <String, List<VodMovie>>{};
  List<VodMovie> _recent = const <VodMovie>[];
  List<VodMovie> _watchlist = const <VodMovie>[];
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
    _load();
  }

  @override
  void dispose() {
    PlaybackPositionRepository.instance.removeListener(_onPositionsChanged);
    VodRepository.instance.removeListener(_onCatalogRefreshed);
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
      final VodMovie hero = _recent.isNotEmpty ? _recent.first : _all.first;
      unawaited(_ensureHeroInfo(hero));
    }
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
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
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
        .push(MaterialPageRoute<void>(
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
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
    final VodMovie hero = _recent.isNotEmpty ? _recent.first : _all.first;
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

    // Rangées, dans l'ordre façon Netflix : Continuer à regarder (si non
    // vide), puis Ma Liste, puis Derniers vus, puis une rangée par catégorie.
    // On les assemble en une liste ordonnée → pas d'arithmétique d'index
    // fragile. `resume: true` = la rangée lance via _playResume (et n'a pas
    // de « Ma Liste » au long-press : une entrée peut être un épisode).
    final List<({String title, List<VodMovie> movies, bool resume})> rails =
        <({String title, List<VodMovie> movies, bool resume})>[
      if (resumeMovies.isNotEmpty)
        (
          title: context.l10n.tvRailContinueWatching,
          movies: resumeMovies,
          resume: true
        ),
      if (_watchlist.isNotEmpty)
        (title: context.l10n.tvMyList, movies: _watchlist, resume: false),
      if (_recent.isNotEmpty)
        (title: context.l10n.tvRailRecent, movies: _recent, resume: false),
      for (final String cat in _cats)
        (title: cat, movies: _byCat[cat] ?? const <VodMovie>[], resume: false),
    ];

    return ListView.builder(
      // La VEDETTE occupe l'index 0, les rangées suivent → tout est lazy.
      addAutomaticKeepAlives: false,
      itemCount: 1 + rails.length,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return _HeroBanner(
            movie: hero,
            autofocus: true,
            backdropUrl: heroBackdrop,
            plot: heroPlot,
            inList: _inList.contains(hero.id),
            onPlay: () => _play(<VodMovie>[hero], 0),
            onToggleList: () => _toggleList(hero),
          );
        }
        final ({String title, List<VodMovie> movies, bool resume}) rail =
            rails[i - 1];
        return _Rail(
          title: rail.title,
          movies: rail.movies,
          inList: _inList,
          progress: progress,
          // OK sur une affiche → FICHE détail. EXCEPTION Netflix : la rangée
          // « Continuer à regarder » relance DIRECTEMENT la lecture (le but
          // de cette rangée est de reprendre en un seul OK).
          onPlay: (int j) => rail.resume
              ? _playResume(resume[j])
              : _openDetail(rail.movies[j]),
          onToggleList: (int j) {
            if (!rail.resume) _toggleList(rail.movies[j]);
          },
        );
      },
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
    this.backdropUrl,
    this.plot,
    this.autofocus = false,
  });

  final VodMovie movie;
  final VoidCallback onPlay;
  final bool inList;
  final VoidCallback onToggleList;

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
        if (movie.category.trim().isNotEmpty) movie.category.trim(),
      ].join('   ·   ');

  /// Rangée de boutons (Regarder / Ma Liste / Télécharger) — partagée par les
  /// deux rendus pour garder un comportement de focus identique.
  Widget _actions(BuildContext context) => Row(
        children: <Widget>[
          _HeroButton(
            icon: Icons.play_arrow_rounded,
            label: context.l10n.tvWatch,
            autofocus: autofocus,
            primary: true,
            onSelect: onPlay,
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
      height: 340,
      margin: const EdgeInsets.only(bottom: 22),
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
                        movie.name,
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
      height: 210,
      margin: const EdgeInsets.only(bottom: 22),
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
                    movie.name,
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
            ? TvTokens.gold
            : (primary ? TvTokens.badgeBg : TvTokens.card);
        final Color fg = focused
            ? const Color(0xFF1A1206)
            : (primary ? TvTokens.goldBright : TvTokens.text);
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(
                color: primary ? TvTokens.gold : TvTokens.lineSoft),
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
    final Widget fallback = Container(
      color: TvTokens.tile,
      child: Center(
        child: Icon(Icons.movie_rounded, size: 44, color: TvTokens.mutedDim),
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
    required this.progress,
    required this.onPlay,
    required this.onToggleList,
  });

  final String title;
  final List<VodMovie> movies;
  final Set<String> inList;

  /// Fraction déjà vue par id de contenu (reprise de lecture) : dessine la
  /// petite barre dorée sous l'affiche. Absent de la map = rien à afficher.
  final Map<String, double> progress;
  final void Function(int index) onPlay;
  final void Function(int index) onToggleList;

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
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
            height: 218,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              addAutomaticKeepAlives: false,
              itemExtent: 142,
              itemCount: movies.length,
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _PosterCard(
                  movie: movies[i],
                  inList: inList.contains(movies[i].id),
                  progress: progress[movies[i].id],
                  onPlay: () => onPlay(i),
                  onToggleList: () => onToggleList(i),
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
    this.progress,
  });
  final VodMovie movie;
  final bool inList;
  final VoidCallback onPlay;
  final VoidCallback onToggleList;

  /// Fraction déjà vue (0..1) — null = pas de reprise en cours pour ce film.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      scale: TvFocusScale.small,
      baseColor: TvTokens.card,
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
                                    gradient: TvTokens.ctaGradient),
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
                          color: TvTokens.gold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded,
                            size: 15, color: Color(0xFF1A1206)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              movie.name,
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
    final Widget fallback = Container(
      color: TvTokens.tile,
      child: Center(
        child: Icon(Icons.movie_rounded, size: 30, color: TvTokens.mutedDim),
      ),
    );
    final String? url = movie.posterUrl;
    if (url == null || url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 300,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}
