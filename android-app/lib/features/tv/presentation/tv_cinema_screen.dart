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
//  • ADULTE : catégories verrouillées, code parental à l'ouverture.
//  • OK sur une affiche : fiche du film / page de la série. OK dans
//    « Continuer » : lecture directe à l'endroit quitté.
// =========================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/blackbox/black_box.dart';
import '../../../core/i18n/l10n_extension.dart';
import '../../cinema/data/cinema_repository.dart';
import '../../cinema/data/watch_progress.dart';
import '../../cinema/domain/cinema_language.dart';
import '../../cinema/domain/cinema_models.dart';
import '../../security/data/parental_controls.dart';
import '../../vod/data/download_repository.dart';
import '../core/tv_dimens.dart';
import '../core/tv_tokens.dart';
import 'tv_cinema_common.dart';
import 'tv_cinema_detail_screen.dart';
import 'tv_components.dart';
import 'tv_parental_screen.dart';
import 'tv_search_screen.dart';
import 'tv_shell.dart';

class TvCinemaScreen extends StatefulWidget {
  const TvCinemaScreen({super.key, required this.kind});
  final CinemaKind kind;

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
  bool _noSource = false;
  List<CinemaCategory> _cats = const <CinemaCategory>[];

  /// Langue choisie (null = toutes) + langues proposées (par fréquence).
  String? _lang;
  List<String> _langOptions = const <String>[];

  _Sel _sel = const _Sel(_View.continueW);
  Timer? _selDebounce;

  List<CinemaTitle> _titles = const <CinemaTitle>[];
  bool _loadingTitles = false;
  int _loadGen = 0;

  bool _adultUnlocked = false;

  // Recherche.
  String _q = '';
  List<CinemaTitle> _results = const <CinemaTitle>[];
  Timer? _searchDebounce;
  late final Widget _keyboard =
      TvKeyboard(onType: _type, onBackspace: _backspace, onClear: _clearQuery);

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
    WatchProgressRepository.instance.addListener(_onExternal);
    _repo.indexVersion.addListener(_onIndex);
    ParentalControls.instance.kidsMode.addListener(_onExternal);
    _dlSub = DownloadsRepository.instance.stream.listen((List<Download> d) {
      if (mounted) setState(() => _downloads = d);
    });
    unawaited(_init());
  }

  @override
  void dispose() {
    WatchProgressRepository.instance.removeListener(_onExternal);
    _repo.indexVersion.removeListener(_onIndex);
    ParentalControls.instance.kidsMode.removeListener(_onExternal);
    _dlSub?.cancel();
    _selDebounce?.cancel();
    _searchDebounce?.cancel();
    _focused.dispose();
    // Libère l'index (plusieurs Mo) en quittant ; les catégories restent.
    _repo.trim();
    super.dispose();
  }

  void _onExternal() {
    if (mounted) setState(() {});
  }

  void _onIndex() {
    if (!mounted) return;
    if (_sel.view == _View.search) _runSearch();
    setState(() {});
  }

  Future<void> _init() async {
    await WatchProgressRepository.instance.load();
    await DownloadsRepository.instance.initialize();
    _downloads = DownloadsRepository.instance.current;
    final List<CinemaSource> srcs = await _repo.sources();
    if (srcs.isEmpty) {
      if (mounted) {
        setState(() {
          _noSource = true;
          _loadingCats = false;
        });
      }
      return;
    }
    final List<CinemaCategory> cats = await _repo.categories(widget.kind);
    if (!mounted) return;

    // Langues présentes, les plus fréquentes d'abord.
    final Map<String, int> freq = <String, int>{};
    for (final CinemaCategory c in cats) {
      if (c.languageKey != null && !c.isAdult) {
        freq[c.languageKey!] = (freq[c.languageKey!] ?? 0) + 1;
      }
    }
    final List<String> langs = freq.keys.toList()
      ..sort((String a, String b) => freq[b]!.compareTo(freq[a]!));

    final String appLang = CinemaLanguage.normalizeCode(Localizations.localeOf(context).languageCode);
    final String? saved = (await SharedPreferences.getInstance()).getString(_prefKey);
    String? lang;
    if (saved == 'all') {
      lang = null;
    } else if (saved != null && freq.containsKey(saved)) {
      lang = saved;
    } else {
      lang = (freq[appLang] ?? 0) >= 3 ? appLang : null;
    }
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _langOptions = langs;
      _lang = lang;
      _loadingCats = false;
      _noSource = cats.isEmpty;
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
      if (mounted) unawaited(_repo.ensureIndex(widget.kind));
    });
  }

  // ---------------------------------------------------------
  //  Filtres (langue, enfants, adulte)
  // ---------------------------------------------------------

  bool get _kids => ParentalControls.instance.kidsMode.value;

  List<CinemaCategory> get _visibleCats {
    final bool kids = _kids;
    final List<CinemaCategory> normal = <CinemaCategory>[];
    final List<CinemaCategory> adult = <CinemaCategory>[];
    for (final CinemaCategory c in _cats) {
      if (kids && !c.isKids) continue;
      if (_lang != null && c.languageKey != _lang) continue;
      (c.isAdult ? adult : normal).add(c);
    }
    return <CinemaCategory>[...normal, if (!kids) ...adult];
  }

  Set<String> get _allowedKeys => <String>{
        for (final CinemaCategory c in _visibleCats)
          if (!c.isAdult || _adultUnlocked) c.key,
      };

  List<WatchEntry> get _continue =>
      WatchProgressRepository.instance.continueWatching(episodes: !_movies);

  List<Download> get _myDownloads => _downloads
      .where((Download d) => d.id.contains(_movies ? ':m:' : ':e:'))
      .toList(growable: false);

  Future<void> _cycleLanguage() async {
    final List<String?> order = <String?>[null, ..._langOptions];
    final int i = order.indexOf(_lang);
    final String? next = order[(i + 1) % order.length];
    setState(() => _lang = next);
    await (await SharedPreferences.getInstance()).setString(_prefKey, next ?? 'all');
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
    _selDebounce?.cancel();
    final CinemaCategory? cat = s.cat;
    if (cat != null && cat.isAdult && !_adultUnlocked) {
      // Catégorie adulte : jamais sur simple focus, code parental sur OK.
      if (!explicit) return;
      final bool ok = await askParentalPin(context);
      if (!ok || !mounted) return;
      setState(() => _adultUnlocked = true);
    }
    setState(() {
      _sel = s;
      _focused.value = null;
    });
    if (s.view == _View.category && cat != null) {
      final int gen = ++_loadGen;
      setState(() {
        _loadingTitles = true;
        _titles = const <CinemaTitle>[];
      });
      final List<CinemaTitle> t = await _repo.titles(widget.kind, cat);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _titles = t;
        _loadingTitles = false;
      });
    } else if (s.view == _View.search) {
      _runSearch();
    }
  }

  // ---------------------------------------------------------
  //  Recherche
  // ---------------------------------------------------------

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
    final List<CinemaTitle> r = _q.trim().isEmpty
        ? const <CinemaTitle>[]
        : _repo.search(widget.kind, _q, allowedCats: _allowedKeys, max: 60);
    if (mounted) setState(() => _results = r);
  }

  // ---------------------------------------------------------
  //  Actions
  // ---------------------------------------------------------

  void _openTitle(CinemaTitle t) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TvShell(
        applySafeArea: false,
        child: _movies ? TvMovieDetailScreen(title: t) : TvSeriesScreen(title: t),
      ),
    ));
  }

  Future<void> _playEntry(WatchEntry e) async {
    if (!e.isEpisode || e.seriesId == null) {
      await openVod(context, VodPlayItem.entry(e));
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
    if (!mounted) return;
    await openVod(context, VodPlayItem.entry(e), series: d, seriesTitle: series);
  }

  Future<void> _onDownload(Download d) async {
    final bool isEp = d.id.contains(':e:');
    final WatchEntry? w = WatchProgressRepository.instance.get(d.id);
    final VodPlayItem item = w != null
        ? VodPlayItem.entry(w)
        : VodPlayItem(
            id: d.id,
            isEpisode: isEp,
            title: d.name,
            url: d.sourceUrl,
            posterUrl: d.posterUrl,
          );
    await showCinemaSheet(context, title: d.name, actions: <CinemaSheetAction>[
      if (d.isDone)
        CinemaSheetAction(Icons.play_arrow_rounded, context.l10n.tvCinemaPlay,
            () => openVod(context, item)),
      if (d.status == DownloadStatus.downloading)
        CinemaSheetAction(Icons.pause_rounded, context.l10n.tvCinemaPauseDownload,
            () => DownloadsRepository.instance.pause(d.id)),
      if (d.status == DownloadStatus.paused || d.status == DownloadStatus.error)
        CinemaSheetAction(Icons.download_rounded, context.l10n.tvCinemaResumeDownload,
            () => DownloadsRepository.instance.resume(d.id)),
      CinemaSheetAction(Icons.delete_outline_rounded, context.l10n.tvCinemaDeleteDownload,
          () => DownloadsRepository.instance.delete(d.id)),
    ]);
  }

  // ---------------------------------------------------------
  //  Rendu
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loadingCats) return const CinemaLoading();
    if (_noSource) {
      return TvEmptyState(
        icon: _movies ? Icons.movie_rounded : Icons.video_library_rounded,
        title: context.l10n.tvCinemaNoSource,
        subtitle: context.l10n.tvCinemaNoSourceBody,
      );
    }
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
    final List<CinemaTitle> recent = _repo.recent(widget.kind, allowedCats: _allowedKeys);
    final String langLabel = _lang == null
        ? context.l10n.tvCinemaAllLanguages
        : (CinemaLanguage.labelFor(_lang) ?? _lang!);

    final List<Widget> fixed = <Widget>[
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
          label: context.l10n.tvCinemaContinue,
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
        color: TvTokens.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(TvTokens.rCard),
        border: Border.all(color: TvTokens.lineSoft),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
            child: Text(
              (_movies ? context.l10n.tvNavFilms : context.l10n.tvNavSeries).toUpperCase(),
              style: TvTokens.ui(12, weight: FontWeight.w700, color: TvTokens.mutedDim, spacing: 2),
            ),
          ),
          ...fixed,
          const Divider(color: TvTokens.lineSoft, height: 12),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemExtent: 46,
              itemCount: vis.length,
              itemBuilder: (BuildContext context, int i) {
                final CinemaCategory c = vis[i];
                final _Sel s = _Sel(_View.category, c);
                final bool locked = c.isAdult && !_adultUnlocked;
                return CinemaRailRow(
                  icon: locked ? Icons.lock_rounded : null,
                  label: c.name,
                  count: locked ? null : _repo.countFor(widget.kind, c.key),
                  autofocus: cont.isEmpty && i == 0 && _sel.cat == c,
                  selected: _sel.cat?.key == c.key,
                  onSelect: () => _select(s, explicit: true),
                  onFocused: locked ? null : () => _selectDebounced(s),
                );
              },
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
        return _withHero(context, _titlesGrid(_repo.recent(widget.kind, allowedCats: _allowedKeys)));
      case _View.category:
        if (_loadingTitles) return _withHero(context, const CinemaLoading());
        if (_titles.isEmpty) {
          return _withHero(
            context,
            Center(
              child: Text(context.l10n.tvCinemaEmptyCategory,
                  style: const TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim)),
            ),
          );
        }
        return _withHero(context, _titlesGrid(_titles));
    }
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

  Widget _titlesGrid(List<CinemaTitle> list) => _grid(
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
            progress: (w != null && w.isResumable && !w.upNext) ? w.fraction : null,
            downloaded: _movies && _isDownloaded(t.id),
            onFocused: () => _focused.value = t,
            onSelect: () => _openTitle(t),
          );
        },
      );

  /// Grille d'affiches 5 colonnes (hauteur calculée → liste paresseuse).
  Widget _grid({required int count, required Widget Function(int) builder, int columns = 5}) {
    if (count == 0) {
      return Center(
        child: Text(context.l10n.tvCinemaEmptyCategory,
            style: const TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim)),
      );
    }
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
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
    });
  }

  Widget _withHero(BuildContext context, Widget body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 150,
          child: ValueListenableBuilder<Object?>(
            valueListenable: _focused,
            builder: (BuildContext context, Object? f, Widget? _) => _Hero(item: f, kind: widget.kind),
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: TvTokens.card,
                  borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                ),
                child: Text(
                  _q.isEmpty ? context.l10n.tvSearchHint : _q,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TvDimens.title,
                    fontWeight: FontWeight.w700,
                    color: _q.isEmpty ? TvTokens.mutedDim : TvTokens.text,
                  ),
                ),
              ),
              if (indexing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(context.l10n.tvCinemaIndexing,
                      style: const TextStyle(fontSize: TvDimens.caption, color: TvTokens.mutedDim)),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(_q.trim().isEmpty ? '' : context.l10n.tvNoResult,
                            style: const TextStyle(fontSize: TvDimens.body, color: TvTokens.mutedDim)),
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
      plot = it.kind == CinemaKind.movie ? (_plotFor == it.id ? _plot : null) : it.plot;
    } else if (it is WatchEntry) {
      title = it.title;
      if (it.subtitle != null) meta.add(it.subtitle!);
      if (it.durMs > 0 && !it.upNext) {
        meta.add(context.l10n.tvCinemaResumeAt(formatClock(Duration(milliseconds: it.posMs))));
      }
    } else if (it is Download) {
      title = it.name;
    }
    if (title.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TvTokens.display(32, color: TvTokens.text)),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(meta.join('  ·  '),
                style: TvTokens.ui(TvDimens.label, weight: FontWeight.w600, color: TvTokens.accentBright)),
          ),
        if (plot != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(plot,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TvTokens.ui(TvDimens.label, color: TvTokens.muted)),
          ),
      ],
    );
  }
}
