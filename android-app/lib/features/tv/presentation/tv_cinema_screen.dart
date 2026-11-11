// =========================================================
//  tv_cinema_screen.dart — Films / Séries (catalogue)
// =========================================================
//  Disposition calquée sur le Direct (même colonne de gauche, mêmes focus) :
//
//   ┌──────────────┬──────────────────────────────────────────────┐
//   │ FILMS        │  Titre focalisé · année · ★ · résumé         │
//   │ 🌐 Langue    ├──────────────────────────────────────────────┤
//   │ 🔍 Rechercher│  ▢ ▢ ▢ ▢ ▢   affiches (grille paresseuse)    │
//   │ ▶ Continuer  │  ▢ ▢ ▢ ▢ ▢                                   │
//   │ ⬇ Téléchargés│                                              │
//   │ ✨ Récents   │                                              │
//   │ Action   212 │                                              │
//   │ …            │                                              │
//   └──────────────┴──────────────────────────────────────────────┘
//
//  • LANGUE : déduite des noms de catégories (cf. CinemaLanguage). Par
//    défaut, la langue de l'app si le catalogue en propose (≥ 3
//    catégories), sinon « Toutes ». Le choix est retenu.
//  • MODE ENFANTS : seules les catégories enfants restent visibles.
//  • ADULTE : espace distinct, autorisation révocable avant ouverture.
//  • OK sur une affiche : fiche du film / page de la série. OK dans
//    « Continuer » : lecture directe à l'endroit quitté.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../remote/domain/remote_typing_hub.dart';
import '../../cinema/data/catalog_cache_policy.dart';
import '../../cinema/data/cinema_repository.dart';
import '../../../core/app/app_platform.dart';
import '../../profiles/data/active_profile.dart';
import '../../cinema/data/watch_progress.dart';
import '../../cinema/domain/cinema_language.dart';
import '../../cinema/domain/cinema_models.dart';
import '../../security/data/parental_controls.dart';
import '../../security/data/adult_access.dart';
import '../../vod/data/download_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';
import '../core/tv_app_tokens.dart';
import 'tv_cinema_common.dart';
import 'tv_cinema_detail_screen.dart';
import 'tv_components.dart';
import 'tv_search_screen.dart';
import 'tv_shell.dart';

class TvCinemaScreen extends StatefulWidget {
  const TvCinemaScreen({super.key, required this.kind, this.adultAccess});
  final CinemaKind kind;
  final AdultAccessGrant? adultAccess;

  @override
  State<TvCinemaScreen> createState() => _TvCinemaScreenState();
}

enum _View { search, continueW, downloads, recent, category }

@immutable
class _Sel {
  const _Sel(this.view, [this.cat]);
  final _View view;
  final CinemaCategory? cat;
  String get key => cat?.key ?? view.name;
}

class _TvCinemaScreenState extends State<TvCinemaScreen> {
  final CinemaRepository _repo = CinemaRepository.instance;

  bool _loadingCats = true;
  bool _refreshingCatalog = false;

  /// Pas de compte Xtream : le message « ajoute ton abonnement ».
  bool _accountsMissing = false;

  /// Compte présent, mais ni cache ni réponse du serveur.
  bool _catalogMissing = false;
  List<CinemaCategory> _cats = const <CinemaCategory>[];

  /// Langue choisie (null = toutes) + langues proposées (par fréquence).
  String? _lang;
  List<String> _langOptions = const <String>[];

  _Sel _sel = const _Sel(_View.continueW);
  Timer? _selDebounce;

  List<CinemaTitle> _titles = const <CinemaTitle>[];
  bool _loadingTitles = false;

  /// La catégorie affichée n'a pas pu être lue (ni cache, ni serveur).
  bool _titlesFailed = false;
  int _loadGen = 0;
  int _initGen = 0;
  late int _classificationRevision = _repo.classificationRevision(widget.kind);

  bool _accessRevoked = false;
  bool _closeScheduled = false;
  bool get _adultOnly => widget.adultAccess != null;
  bool get _accessValid => ParentalControls.instance.contentReady &&
      !_accessRevoked &&
      (!_adultOnly || (widget.adultAccess!.isValid && !_kids));

  // Recherche.
  String _q = '';
  List<CinemaTitle> _results = const <CinemaTitle>[];
  Timer? _searchDebounce;
  late final Widget _keyboard = TvKeyboard(
    onType: _type,
    onBackspace: _backspace,
    onClear: _clearQuery,
  );
  late final bool Function(String text) _remoteTyping = _onRemoteQuery;

  /// Élément focalisé → bandeau du haut (sans reconstruire la grille).
  final ValueNotifier<Object?> _focused = ValueNotifier<Object?>(null);

  StreamSubscription<List<Download>>? _dlSub;
  List<Download> _downloads = const <Download>[];

  bool get _movies => widget.kind == CinemaKind.movie;
  String get _prefKey => 'cinema.lang.${widget.kind.name}';

  @override
  void initState() {
    super.initState();
    BlackBox.instance.breadcrumb('Cinéma : ${widget.kind.name}');
    RemoteTypingHub.instance.register(_remoteTyping);
    WatchProgressRepository.instance.addListener(_onExternal);
    _repo.indexVersion.addListener(_onIndex);
    if (AppPlatform.isZuno) {
      _repo.classificationVersion.addListener(_onClassificationChanged);
    }
    ActiveProfile.instance.scopeListenable.addListener(_onProfileScope);
    ParentalControls.instance.kidsMode.addListener(_onExternal);
    widget.adultAccess?.addListener(_onAccessChanged);
    _dlSub = DownloadsRepository.instance.stream.listen((List<Download> d) {
      if (mounted) setState(() => _downloads = d);
    });
    // Catalogue de plus de 10 min → relu (nouveaux titres du fournisseur).
    if (!_accessValid) {
      _onAccessChanged();
    } else {
      _repo.refreshIfStale();
      unawaited(_init());
    }
  }

  @override
  void dispose() {
    RemoteTypingHub.instance.unregister(_remoteTyping);
    WatchProgressRepository.instance.removeListener(_onExternal);
    _repo.indexVersion.removeListener(_onIndex);
    _repo.classificationVersion.removeListener(_onClassificationChanged);
    ActiveProfile.instance.scopeListenable.removeListener(_onProfileScope);
    ParentalControls.instance.kidsMode.removeListener(_onExternal);
    widget.adultAccess?.removeListener(_onAccessChanged);
    _dlSub?.cancel();
    _selDebounce?.cancel();
    _searchDebounce?.cancel();
    _focused.dispose();
    // Libère l'index (plusieurs Mo) en quittant ; les catégories restent.
    _repo.trim();
    super.dispose();
  }

  void _onExternal() {
    if (!_accessValid) {
      _onAccessChanged();
      return;
    }
    if (mounted) setState(() => _focused.value = null);
  }

  void _onAccessChanged() {
    if (!mounted || _accessValid) return;
    _initGen++;
    _loadGen++;
    _selDebounce?.cancel();
    _searchDebounce?.cancel();
    setState(() {
      _accessRevoked = true;
      _cats = const <CinemaCategory>[];
      _titles = const <CinemaTitle>[];
      _results = const <CinemaTitle>[];
      _focused.value = null;
    });
    if (_closeScheduled) return;
    _closeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive && !route.isFirst) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  void _onProfileScope() {
    if (!mounted) return;
    if (_adultOnly) {
      _onAccessChanged();
      return;
    }
    _initGen++;
    _loadGen++;
    _selDebounce?.cancel();
    _searchDebounce?.cancel();
    setState(() {
      _cats = const <CinemaCategory>[];
      _titles = const <CinemaTitle>[];
      _results = const <CinemaTitle>[];
      _langOptions = const <String>[];
      _lang = null;
      _q = '';
      _focused.value = null;
      _sel = const _Sel(_View.continueW);
      _loadingCats = true;
      _loadingTitles = false;
      _titlesFailed = false;
      _accountsMissing = false;
      _catalogMissing = false;
      _refreshingCatalog = false;
    });
    unawaited(_init());
  }

  void _onIndex() {
    if (!mounted || !_accessValid) return;
    final List<CinemaCategory>? fresh = _repo.peekCategories(widget.kind);
    if (fresh != null && fresh.isNotEmpty) {
      _cats = fresh;
      _catalogMissing = false;
    }
    if (_sel.view == _View.search) _runSearch();
    if (_sel.view == _View.category && _sel.cat != null) {
      unawaited(_loadCategory(_sel.cat!, keepVisible: _titles.isNotEmpty));
    }
    setState(() {});
  }

  void _onClassificationChanged() {
    if (!mounted || !AppPlatform.isZuno) return;
    final revision = _repo.classificationRevision(widget.kind);
    if (revision == _classificationRevision) return;
    _classificationRevision = revision;
    // Une réponse de catégorie antérieure à la publication reste périmée.
    // L'événement index suivant recharge la sélection avec les données neuves.
    _loadGen++;
    setState(() {
      _cats = _repo.peekCategories(widget.kind) ?? const <CinemaCategory>[];
      _titles = const <CinemaTitle>[];
      _results = const <CinemaTitle>[];
      _focused.value = null;
    });
  }

  Future<void> _init() async {
    if (!_accessValid) return;
    final int gen = ++_initGen;
    await WatchProgressRepository.instance.load();
    if (!mounted || !_accessValid || gen != _initGen) return;
    await DownloadsRepository.instance.initialize();
    if (!mounted || !_accessValid || gen != _initGen) return;
    _downloads = DownloadsRepository.instance.current;
    final List<CinemaSource> srcs = await _repo.sources();
    if (!mounted || !_accessValid || gen != _initGen) return;
    if (srcs.isEmpty) {
      if (mounted) {
        setState(() {
          _accountsMissing = true;
          _catalogMissing = false;
          _loadingCats = false;
        });
      }
      return;
    }
    final List<CinemaCategory> cats = await _repo.categories(widget.kind);
    if (!mounted || !_accessValid || gen != _initGen) return;

    // Langues présentes, les plus fréquentes d'abord.
    final Map<String, int> freq = <String, int>{};
    for (final CinemaCategory c in cats) {
      if (c.languageKey != null && c.isAdult == _adultOnly) {
        freq[c.languageKey!] = (freq[c.languageKey!] ?? 0) + 1;
      }
    }
    final List<String> langs = freq.keys.toList()
      ..sort((String a, String b) => freq[b]!.compareTo(freq[a]!));

    // Par défaut : TOUTES les langues (demande du propriétaire 27/09/2026 :
    // « j'ai tout mis, mais ça s'arrête sur la Belgique »). Avant, le filtre
    // se mettait TOUT SEUL sur la langue de la TV → le client croyait voir
    // tout le catalogue alors qu'il n'en voyait qu'une partie. Le filtre ne
    // s'applique plus que si le client l'a CHOISI lui-même (ligne Langue).
    final String? saved = (await SharedPreferences.getInstance()).getString(
      _prefKey,
    );
    String? lang;
    if (saved != null && saved != 'all' && freq.containsKey(saved)) {
      lang = saved;
    } else {
      lang = null;
    }
    if (!mounted || !_accessValid || gen != _initGen) return;
    setState(() {
      _cats = cats;
      _langOptions = langs;
      _lang = lang;
      _loadingCats = false;
      _accountsMissing = false;
      _catalogMissing = cats.isEmpty;
    });
    final List<WatchEntry> cont = _continue;
    final List<CinemaCategory> vis = _visibleCats;
    if (cont.isNotEmpty) {
      _select(const _Sel(_View.continueW));
    } else if (vis.isNotEmpty) {
      _select(_Sel(_View.category, vis.first));
    }
    // Index complet (recherche / récents / compteurs) en arrière-plan, après
    // le 1er affichage pour ne pas lui voler la bande passante.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && gen == _initGen) unawaited(_repo.ensureIndex(widget.kind));
    });
  }

  // ---------------------------------------------------------
  //  Filtres (langue, enfants, adulte)
  // ---------------------------------------------------------

  bool get _kids => ParentalControls.instance.kidsMode.value;

  List<CinemaCategory> get _visibleCats {
    if (!_accessValid) return const <CinemaCategory>[];
    return _cats.where((c) {
      if (c.isAdult != _adultOnly || (_kids && !c.isKids)) return false;
      return _lang == null || c.languageKey == null || c.languageKey == _lang;
    }).toList(growable: false);
  }

  Set<String> get _allowedKeys => <String>{
        for (final c in _visibleCats) c.key,
      };

  bool _titleAllowed(CinemaTitle title) =>
      _accessValid &&
      _sourceAllowed(title.sourceKey) &&
      (_adultOnly ? _repo.isAdultTitle(title) : !_repo.isHiddenTitle(title));

  bool _entryAllowed(WatchEntry entry) =>
      _accessValid &&
      _sourceAllowed(entry.sourceKey) &&
      _repo.adultStatusForWatch(entry) == _adultOnly;

  bool _downloadAllowed(Download download) {
    if (!_accessValid) return false;
    final entry = WatchProgressRepository.instance.get(download.id);
    return (entry == null
            ? _repo.adultStatusForMedia(download.id, download.name)
            : _repo.adultStatusForWatch(entry)) ==
        _adultOnly;
  }

  bool _sourceAllowed(String key) => ActiveProfile.instance.allowsPlaylist(
        int.tryParse(key.startsWith('p') ? key.substring(1) : ''),
      );

  List<WatchEntry> get _continue => WatchProgressRepository.instance
      .continueWatching(episodes: !_movies)
      .where(_entryAllowed)
      .toList(growable: false);

  List<Download> get _myDownloads => _downloads
      .where((Download d) =>
          d.id.contains(_movies ? ':m:' : ':e:') && _downloadAllowed(d))
      .toList(growable: false);

  Future<void> _cycleLanguage() async {
    final List<String?> order = <String?>[null, ..._langOptions];
    final int i = order.indexOf(_lang);
    final String? next = order[(i + 1) % order.length];
    setState(() => _lang = next);
    await (await SharedPreferences.getInstance()).setString(
      _prefKey,
      next ?? 'all',
    );
    if (_sel.view == _View.category && !_visibleCats.contains(_sel.cat)) {
      final List<CinemaCategory> vis = _visibleCats;
      if (vis.isNotEmpty) _select(_Sel(_View.category, vis.first));
    } else if (_sel.view == _View.search) {
      _runSearch();
    }
  }

  // ---------------------------------------------------------
  //  Sélection
  // ---------------------------------------------------------

  void _selectDebounced(_Sel s) {
    _selDebounce?.cancel();
    _selDebounce = Timer(const Duration(milliseconds: 380), () {
      if (mounted && s.key != _sel.key) _select(s);
    });
  }

  Future<void> _select(_Sel s, {bool explicit = false}) async {
    if (!_accessValid) return;
    _selDebounce?.cancel();
    final CinemaCategory? cat = s.cat;
    if (cat != null && !_allowedKeys.contains(cat.key)) return;
    setState(() {
      _sel = s;
      _focused.value = null;
    });
    if (s.view == _View.category && cat != null) {
      await _loadCategory(cat);
    } else if (s.view == _View.search) {
      _runSearch();
    }
  }

  /// Charge les affiches d'une catégorie.
  ///
  /// [keepVisible] : un rafraîchissement est arrivé alors que la grille
  /// est déjà là. On ne la remplace pas par un spinner, et on ne la vide
  /// pas si le serveur échoue.
  Future<void> _loadCategory(
    CinemaCategory cat, {
    bool keepVisible = false,
  }) async {
    final int gen = ++_loadGen;
    if (!keepVisible) {
      setState(() {
        _loadingTitles = true;
        _titlesFailed = false;
        _titles = const <CinemaTitle>[];
      });
    }
    final CinemaTitleLoad load = await _repo.loadTitles(widget.kind, cat);
    if (!mounted || !_accessValid || gen != _loadGen) return;
    setState(() {
      _titles = load.titles.where(_titleAllowed).toList(growable: false);
      _titlesFailed = load.failed && load.titles.isEmpty;
      _loadingTitles = false;
    });
  }

  Future<void> _retryCatalog() async {
    setState(() {
      _loadingCats = true;
      _catalogMissing = false;
    });
    _repo.dropKindMemory(widget.kind);
    _repo.requestRefresh();
    await _init();
  }

  Future<void> _refreshCatalogNow() async {
    if (_refreshingCatalog) return;
    final int scope = _initGen;
    setState(() => _refreshingCatalog = true);
    try {
      final bool done = await _repo.refreshNow(widget.kind);
      if (!mounted || scope != _initGen) return;
      _onIndex();
      await _select(_sel, explicit: true);
      if (!done && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.libraryRefreshIncomplete)),
        );
      }
    } finally {
      if (mounted && scope == _initGen) {
        setState(() => _refreshingCatalog = false);
      }
    }
  }

  Future<void> _retryCategory() async {
    final CinemaCategory? cat = _sel.cat;
    if (cat == null) return;
    final int gen = ++_loadGen;
    setState(() {
      _loadingTitles = true;
      _titlesFailed = false;
    });
    final CinemaTitleLoad load = await _repo.loadTitles(
      widget.kind,
      cat,
      forceNetwork: true,
    );
    if (!mounted || !_accessValid || gen != _loadGen) return;
    setState(() {
      _titles = load.titles.where(_titleAllowed).toList(growable: false);
      _titlesFailed = load.failed && load.titles.isEmpty;
      _loadingTitles = false;
    });
  }

  String? _updatedLabel(BuildContext context) {
    final CatalogAge? age = _repo.catalogAgeAt(widget.kind, DateTime.now());
    if (age == null) return null;
    final String when;
    switch (age.unit) {
      case CatalogAgeUnit.justNow:
        when = context.l10n.tvCinemaAgeJustNow;
      case CatalogAgeUnit.minutes:
        when = context.l10n.tvCinemaAgeMinutes(age.amount);
      case CatalogAgeUnit.hours:
        when = context.l10n.tvCinemaAgeHours(age.amount);
      case CatalogAgeUnit.days:
        when = context.l10n.tvCinemaAgeDays(age.amount);
    }
    return context.l10n.tvCinemaUpdated(when);
  }

  // ---------------------------------------------------------
  //  Recherche
  // ---------------------------------------------------------

  /// Texte du téléphone. On ne le prend QUE si la recherche du
  /// cinéma est affichée : sinon on répond faux, et le texte ne
  /// change pas le catalogue en train d'être parcouru.
  bool _onRemoteQuery(String text) {
    if (!mounted || !_accessValid || _sel.view != _View.search) return false;
    setState(() => _q = text);
    _scheduleSearch();
    return true;
  }

  void _type(String ch) {
    setState(() => _q += ch);
    _scheduleSearch();
  }

  void _backspace() {
    if (_q.isEmpty) return;
    setState(() => _q = _q.substring(0, _q.length - 1));
    _scheduleSearch();
  }

  void _clearQuery() {
    setState(() {
      _q = '';
      _results = const <CinemaTitle>[];
    });
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), _runSearch);
  }

  void _runSearch() {
    if (!_accessValid) return;
    final List<CinemaTitle> r = _q.trim().isEmpty
        ? const <CinemaTitle>[]
        : _repo.search(widget.kind, _q, allowedCats: _allowedKeys, max: 60);
    if (mounted)
      setState(() => _results = r.where(_titleAllowed).toList(growable: false));
  }

  // ---------------------------------------------------------
  //  Actions
  // ---------------------------------------------------------

  void _openTitle(CinemaTitle t) {
    if (!_titleAllowed(t)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvShell(
          applySafeArea: false,
          child: _movies
              ? TvMovieDetailScreen(title: t, adultAccess: widget.adultAccess)
              : TvSeriesScreen(title: t, adultAccess: widget.adultAccess),
        ),
      ),
    );
  }

  Future<void> _playEntry(WatchEntry e) async {
    if (!_entryAllowed(e)) return;
    final int scope = _initGen;
    if (!e.isEpisode || e.seriesId == null) {
      await openVod(context, VodPlayItem.entry(e),
          adultAccess: widget.adultAccess);
      return;
    }
    // Épisode : on charge la série pour pouvoir enchaîner l'épisode suivant.
    final CinemaTitle series = seriesTitleFromEntry(e);
    SeriesDetails? d;
    try {
      d = await _repo.seriesDetails(series).timeout(const Duration(seconds: 8));
    } catch (_) {
      d = null;
    }
    if (!mounted || scope != _initGen || !_entryAllowed(e)) return;
    await openVod(
      context,
      VodPlayItem.entry(e),
      series: d,
      seriesTitle: series,
      adultAccess: widget.adultAccess,
    );
  }

  Future<void> _onDownload(Download d) async {
    if (!_downloadAllowed(d)) return;
    final bool isEp = d.id.contains(':e:');
    final WatchEntry? w = WatchProgressRepository.instance.get(d.id);
    final VodPlayItem item = w != null
        ? VodPlayItem.entry(w)
        : AppPlatform.isZuno ? VodPlayItem.download(d, isAdult: _adultOnly)
        : VodPlayItem(
            id: d.id,
            isEpisode: isEp,
            title: d.name,
            url: d.sourceUrl,
            posterUrl: d.posterUrl,
            isAdult: _adultOnly,
          );
    await showCinemaSheet(
      context,
      title: d.name,
      isAllowed: () => item.isAllowedNow(adultAccess: widget.adultAccess),
      permissionChanges: widget.adultAccess,
      actions: <CinemaSheetAction>[
        if (d.isDone)
          CinemaSheetAction(
            Icons.play_arrow_rounded,
            context.l10n.tvCinemaPlay,
            () => openVod(context, item, adultAccess: widget.adultAccess),
          ),
        if (d.status == DownloadStatus.downloading)
          CinemaSheetAction(
            Icons.pause_rounded,
            context.l10n.tvCinemaPauseDownload,
            () => DownloadsRepository.instance.pause(d.id),
          ),
        if (d.status == DownloadStatus.paused ||
            d.status == DownloadStatus.error)
          CinemaSheetAction(
            Icons.download_rounded,
            context.l10n.tvCinemaResumeDownload,
            () => DownloadsRepository.instance.resume(d.id),
          ),
        CinemaSheetAction(
          Icons.delete_outline_rounded,
          context.l10n.tvCinemaDeleteDownload,
          () => DownloadsRepository.instance.delete(d.id),
        ),
      ],
    );
  }

  // ---------------------------------------------------------
  //  Rendu
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_accessValid) return const SizedBox.shrink();
    if (_loadingCats) return const CinemaLoading();
    if (_accountsMissing) {
      return TvEmptyState(
        icon: _movies ? Icons.movie_rounded : Icons.video_library_rounded,
        title: context.l10n.tvCinemaNoSource,
        subtitle: context.l10n.tvCinemaNoSourceBody,
      );
    }
    if (_catalogMissing) return _unavailable(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: 300, child: _buildRail(context)),
        const SizedBox(width: TvDimens.gutter),
        Expanded(child: _buildMain(context)),
      ],
    );
  }

  Widget _buildRail(BuildContext context) {
    final List<CinemaCategory> vis = _visibleCats;
    final List<WatchEntry> cont = _continue;
    final List<Download> dls = _myDownloads;
    final List<CinemaTitle> recent = _repo.recent(
      widget.kind,
      allowedCats: _allowedKeys,
    );
    final String langLabel = _lang == null
        ? context.l10n.tvCinemaAllLanguages
        : (CinemaLanguage.labelFor(_lang) ?? _lang!);

    final List<Widget> fixed = <Widget>[
      CinemaRailRow(
        icon: Icons.sync_rounded,
        label: _refreshingCatalog
            ? context.l10n.libraryRefreshRunning
            : context.l10n.tvRefresh,
        selected: _refreshingCatalog,
        onSelect: () => unawaited(_refreshCatalogNow()),
      ),
      if (_langOptions.isNotEmpty)
        CinemaRailRow(
          icon: Icons.language_rounded,
          label: context.l10n.tvCinemaLanguage(langLabel),
          selected: false,
          onSelect: () => unawaited(_cycleLanguage()),
        ),
      CinemaRailRow(
        icon: Icons.search_rounded,
        label: context.l10n.tvCinemaSearch,
        selected: _sel.view == _View.search,
        onSelect: () => _select(const _Sel(_View.search), explicit: true),
        onFocused: () => _selectDebounced(const _Sel(_View.search)),
      ),
      if (cont.isNotEmpty)
        CinemaRailRow(
          icon: Icons.play_circle_outline_rounded,
          label: context.l10n.sectionResumeWhereYouLeftOff,
          count: cont.length,
          autofocus: _sel.view == _View.continueW,
          selected: _sel.view == _View.continueW,
          onSelect: () => _select(const _Sel(_View.continueW), explicit: true),
          onFocused: () => _selectDebounced(const _Sel(_View.continueW)),
        ),
      if (dls.isNotEmpty)
        CinemaRailRow(
          icon: Icons.download_done_rounded,
          label: context.l10n.tvCinemaDownloads,
          count: dls.length,
          selected: _sel.view == _View.downloads,
          onSelect: () => _select(const _Sel(_View.downloads), explicit: true),
          onFocused: () => _selectDebounced(const _Sel(_View.downloads)),
        ),
      if (recent.isNotEmpty)
        CinemaRailRow(
          icon: Icons.auto_awesome_rounded,
          label: context.l10n.tvCinemaRecent,
          selected: _sel.view == _View.recent,
          onSelect: () => _select(const _Sel(_View.recent), explicit: true),
          onFocused: () => _selectDebounced(const _Sel(_View.recent)),
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: TvAppTokens.of(context).card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvAppTokens.of(context).lineSoft),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
            child: Text(
              _movies ? context.l10n.tvNavFilms : context.l10n.tvNavSeries,
              style: TvAppTokens.of(context).ui(
                TvDimens.caption,
                weight: FontWeight.w500,
                color: TvAppTokens.of(context).mutedDim,
                spacing: 0.5,
              ),
            ),
          ),
          ...fixed,
          Divider(color: TvAppTokens.of(context).lineSoft, height: 12),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemExtent: 46,
              itemCount: vis.length,
              itemBuilder: (BuildContext context, int i) {
                final CinemaCategory c = vis[i];
                final _Sel s = _Sel(_View.category, c);
                return CinemaRailRow(
                  label: c.name,
                  count: _repo.countFor(widget.kind, c.key),
                  autofocus: cont.isEmpty && i == 0 && _sel.cat == c,
                  selected: _sel.cat?.key == c.key,
                  onSelect: () => _select(s, explicit: true),
                  onFocused: () => _selectDebounced(s),
                );
              },
            ),
          ),
          if (_updatedLabel(context) case final String label)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TvAppTokens.of(
                  context,
                ).ui(TvDimens.caption, color: TvAppTokens.of(context).mutedDim),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMain(BuildContext context) {
    switch (_sel.view) {
      case _View.search:
        return _buildSearch(context);
      case _View.continueW:
        final List<WatchEntry> cont = _continue;
        return _withHero(
          context,
          _grid(
            count: cont.length,
            builder: (int i) {
              final WatchEntry e = cont[i];
              return CinemaPoster(
                title: e.title,
                caption: e.subtitle,
                posterUrl: e.posterUrl,
                progress: e.upNext ? null : e.fraction,
                downloaded: _isDownloaded(e.id),
                onFocused: () => _focused.value = e,
                onSelect: () => unawaited(_playEntry(e)),
              );
            },
          ),
        );
      case _View.downloads:
        final List<Download> dls = _myDownloads;
        return _withHero(
          context,
          _grid(
            count: dls.length,
            builder: (int i) {
              final Download d = dls[i];
              return CinemaPoster(
                title: d.name,
                caption: _downloadCaption(context, d),
                posterUrl: d.posterUrl,
                progress: d.isDone ? null : d.progress,
                downloaded: d.isDone,
                onFocused: () => _focused.value = d,
                onSelect: () => unawaited(_onDownload(d)),
              );
            },
          ),
        );
      case _View.recent:
        return _withHero(
          context,
          _titlesGrid(_repo.recent(widget.kind, allowedCats: _allowedKeys)),
        );
      case _View.category:
        if (_loadingTitles) return _withHero(context, const CinemaLoading());
        if (_titlesFailed && _titles.isEmpty) {
          return _withHero(context, _failedCategory(context));
        }
        if (_titles.isEmpty) {
          return _withHero(
            context,
            Center(
              child: Text(
                context.l10n.tvCinemaEmptyCategory,
                style: TextStyle(
                  fontSize: TvDimens.body,
                  color: TvAppTokens.of(context).mutedDim,
                ),
              ),
            ),
          );
        }
        return _withHero(context, _titlesGrid(_titles));
    }
  }

  Widget _unavailable(BuildContext context) {
    return TvEmptyState(
      icon: _movies ? Icons.movie_rounded : Icons.video_library_rounded,
      title: context.l10n.tvCinemaOfflineTitle,
      subtitle: context.l10n.tvCinemaOfflineBody,
      footer: _retryButton(context, () => unawaited(_retryCatalog())),
    );
  }

  Widget _failedCategory(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            context.l10n.tvCinemaCategoryFailed,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TvDimens.body,
              color: TvAppTokens.of(context).mutedDim,
            ),
          ),
          const SizedBox(height: 18),
          _retryButton(context, () => unawaited(_retryCategory())),
        ],
      ),
    );
  }

  Widget _retryButton(BuildContext context, VoidCallback onSelect) {
    return TvFocusable(
      autofocus: true,
      onSelect: onSelect,
      borderRadius: BorderRadius.circular(TvTokens.rButton),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          color: TvAppTokens.of(context).card,
          borderRadius: BorderRadius.circular(TvTokens.rButton),
          border: Border.all(color: TvAppTokens.of(context).line),
        ),
        child: Text(
          context.l10n.tvCinemaRetry,
          style: TvAppTokens.of(context)
              .ui(TvDimens.body, weight: FontWeight.w600),
        ),
      ),
    );
  }

  bool _isDownloaded(String id) {
    for (final Download d in _downloads) {
      if (d.id == id) return d.isDone;
    }
    return false;
  }

  String _downloadCaption(BuildContext context, Download d) {
    final String pct = (d.progress * 100).round().toString();
    switch (d.status) {
      case DownloadStatus.done:
        return context.l10n.tvCinemaDownloaded;
      case DownloadStatus.downloading:
        return context.l10n.tvCinemaDownloading(pct);
      case DownloadStatus.paused:
        return context.l10n.tvCinemaDownloadPaused(pct);
      case DownloadStatus.error:
        return context.l10n.tvCinemaDownloadError;
    }
  }

  Widget _titlesGrid(List<CinemaTitle> titles) {
    final list = titles.where(_titleAllowed).toList(growable: false);
    return _grid(
      count: list.length,
      builder: (int i) {
        final CinemaTitle t = list[i];
        final WatchEntry? w = _movies
            ? WatchProgressRepository.instance.get(t.id)
            : WatchProgressRepository.instance.latestForSeries(t.id);
        return CinemaPoster(
          title: t.name,
          caption: t.year,
          posterUrl: t.posterUrl,
          progress:
              (w != null && w.isResumable && !w.upNext) ? w.fraction : null,
          downloaded: _movies && _isDownloaded(t.id),
          onFocused: () => _focused.value = t,
          onSelect: () => _openTitle(t),
        );
      },
    );
  }

  /// Grille d'affiches 5 colonnes (hauteur calculée → liste paresseuse).
  Widget _grid({
    required int count,
    required Widget Function(int) builder,
    int columns = 5,
  }) {
    if (count == 0) {
      return Center(
        child: Text(
          context.l10n.tvCinemaEmptyCategory,
          style: TextStyle(
            fontSize: TvDimens.body,
            color: TvAppTokens.of(context).mutedDim,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        const double gapX = 16;
        final double w = (c.maxWidth - gapX * (columns - 1)) / columns;
        final double h = w * 1.5 + 42;
        return GridView.builder(
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          addAutomaticKeepAlives: false,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gapX,
            mainAxisSpacing: 18,
            mainAxisExtent: h,
          ),
          itemCount: count,
          itemBuilder: (BuildContext context, int i) => builder(i),
        );
      },
    );
  }

  Widget _withHero(BuildContext context, Widget body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 150,
          child: ValueListenableBuilder<Object?>(
            valueListenable: _focused,
            builder: (BuildContext context, Object? f, Widget? _) =>
                _Hero(item: f, kind: widget.kind),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildSearch(BuildContext context) {
    final bool indexing = !_repo.indexReady(widget.kind);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: 380, child: _keyboard),
        const SizedBox(width: TvDimens.gutter),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: TvAppTokens.of(context).card,
                  borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                ),
                child: Text(
                  _q.isEmpty ? context.l10n.tvSearchHint : _q,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TvDimens.title,
                    fontWeight: FontWeight.w700,
                    color: _q.isEmpty
                        ? TvAppTokens.of(context).mutedDim
                        : TvAppTokens.of(context).text,
                  ),
                ),
              ),
              if (indexing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.l10n.tvCinemaIndexing,
                    style: TextStyle(
                      fontSize: TvDimens.caption,
                      color: TvAppTokens.of(context).mutedDim,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          _q.trim().isEmpty ? '' : context.l10n.tvNoResult,
                          style: TextStyle(
                            fontSize: TvDimens.body,
                            color: TvAppTokens.of(context).mutedDim,
                          ),
                        ),
                      )
                    : _grid(
                        count: _results.length,
                        columns: 3,
                        builder: (int i) {
                          final CinemaTitle t = _results[i];
                          return CinemaPoster(
                            title: t.name,
                            caption: t.year,
                            posterUrl: t.posterUrl,
                            onSelect: () => _openTitle(t),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reconstruit la « vignette série » d'une entrée Continuer (id `p3:s:123`).
CinemaTitle seriesTitleFromEntry(WatchEntry e) {
  final String sid = e.seriesId ?? '';
  final List<String> parts = sid.split(':');
  return CinemaTitle(
    id: sid,
    kind: CinemaKind.series,
    sourceKey: parts.isNotEmpty ? parts.first : e.sourceKey,
    remoteId: parts.length >= 3 ? parts[2] : '',
    name: e.title,
    categoryKey: '',
    searchKey: CinemaLanguage.searchKey(e.title),
    posterUrl: e.posterUrl,
  );
}

/// Bandeau haut : infos du titre focalisé (résumé chargé à la volée pour
/// un film, après une courte pause du focus).
class _Hero extends StatefulWidget {
  const _Hero({required this.item, required this.kind});
  final Object? item;
  final CinemaKind kind;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  Timer? _t;
  String? _plot;
  String? _plotFor;

  @override
  void didUpdateWidget(covariant _Hero old) {
    super.didUpdateWidget(old);
    if (old.item != widget.item) _schedule();
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _schedule() {
    _t?.cancel();
    final Object? it = widget.item;
    if (it is! CinemaTitle || it.kind != CinemaKind.movie) return;
    if (_plotFor == it.id) return;
    _t = Timer(const Duration(milliseconds: 700), () async {
      final CinemaDetails d = await CinemaRepository.instance.movieDetails(it);
      if (!mounted || widget.item != it) return;
      setState(() {
        _plotFor = it.id;
        _plot = d.plot;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final Object? it = widget.item;
    String title = '';
    final List<String> meta = <String>[];
    String? plot;
    if (it is CinemaTitle) {
      title = it.name;
      if (it.year != null) meta.add(it.year!);
      if (it.rating != null) meta.add('★ ${it.rating!.toStringAsFixed(1)}');
      plot = it.kind == CinemaKind.movie
          ? (_plotFor == it.id ? _plot : null)
          : it.plot;
    } else if (it is WatchEntry) {
      title = it.title;
      if (it.subtitle != null) meta.add(it.subtitle!);
      if (it.durMs > 0 && !it.upNext) {
        meta.add(
          context.l10n.tvCinemaResumeAt(
            formatClock(Duration(milliseconds: it.posMs)),
          ),
        );
      }
    } else if (it is Download) {
      title = it.name;
    }
    if (title.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TvAppTokens.of(context)
              .display(32, color: TvAppTokens.of(context).text),
        ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              meta.join('  ·  '),
              style: TvAppTokens.of(context).ui(
                TvDimens.label,
                weight: FontWeight.w600,
                color: TvAppTokens.of(context).accentBright,
              ),
            ),
          ),
        if (plot != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              plot,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TvAppTokens.of(context)
                  .ui(TvDimens.label, color: TvAppTokens.of(context).muted),
            ),
          ),
      ],
    );
  }
}
