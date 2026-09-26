// =========================================================
//  cinema_repository.dart — Films & Séries (tous les comptes Xtream)
// =========================================================
//  Principe « fluide sur une box 1 Go » (le même que le Direct) :
//
//  1. CATÉGORIES d'abord (quelques Ko) : l'écran s'affiche tout de suite.
//  2. Chaque catégorie est chargée À LA DEMANDE (`&category_id=`), décodée
//     et convertie dans un ISOLATE, puis gardée en cache (LRU de 30
//     catégories) : ouvrir « Action » ne télécharge QUE l'Action.
//  3. En arrière-plan, un INDEX complet (recherche, « Récemment ajoutés »,
//     compteurs) est construit : liste entière si elle tient sous
//     [kCinemaSingleShotBytes], sinon catégorie par catégorie. Un seul type
//     indexé à la fois (films OU séries) pour borner la mémoire.
//  4. Plusieurs comptes : les catégories de même nom sont FUSIONNÉES et un
//     titre présent sur deux comptes n'apparaît qu'une fois.
//
//  Toutes les erreurs réseau d'un compte sont journalisées (boîte noire) et
//  n'empêchent jamais les autres comptes de s'afficher.
// =========================================================
import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../../core/blackbox/black_box.dart';
import '../../channels/domain/channel_genre.dart';
import '../../playlists/data/playlist_repository.dart';
import '../../playlists/data/xtream_client.dart';
import '../../playlists/domain/playlist.dart';
import '../domain/cinema_language.dart';
import '../domain/cinema_models.dart';
import 'cinema_parsers.dart';

/// Au-delà, la liste complète n'est PAS téléchargée d'un bloc (index construit
/// catégorie par catégorie). Même logique que l'import des chaînes.
const int kCinemaSingleShotBytes = 12 * 1024 * 1024;

/// Plafond de titres gardés dans l'index (mémoire bornée).
const int kCinemaIndexMax = 40000;

class CinemaRepository {
  CinemaRepository._();
  static final CinemaRepository instance = CinemaRepository._();

  // ---------------- État ----------------
  String _sourcesSig = '';
  List<CinemaSource> _sources = const <CinemaSource>[];
  final Map<String, XtreamClient> _clients = <String, XtreamClient>{};

  final Map<CinemaKind, List<CinemaCategory>> _cats =
      <CinemaKind, List<CinemaCategory>>{};

  /// kind → sourceKey → id catégorie serveur → clé fusionnée.
  final Map<CinemaKind, Map<String, Map<String, String>>> _catKeys =
      <CinemaKind, Map<String, Map<String, String>>>{};

  /// Cache LRU des catégories chargées (`kind|catKey`).
  final LinkedHashMap<String, List<CinemaTitle>> _titles =
      LinkedHashMap<String, List<CinemaTitle>>();
  static const int _kTitleCacheMax = 30;

  /// Index complet d'UN type (films ou séries).
  CinemaKind? _indexKind;

  /// Génération de l'index : une construction dépassée (écran quitté puis
  /// rouvert) s'arrête d'elle-même et ne publie plus rien.
  int _indexGen = 0;
  List<CinemaTitle> _index = const <CinemaTitle>[];
  bool _indexDone = false;
  Future<void>? _indexing;
  Map<String, int> _indexCounts = const <String, int>{};
  List<CinemaTitle>? _recent;

  /// Incrémenté quand l'index grandit / se termine → l'écran se met à jour
  /// (recherche, compteurs, « Récemment ajoutés »).
  final ValueNotifier<int> indexVersion = ValueNotifier<int>(0);

  final LinkedHashMap<String, CinemaDetails> _details =
      LinkedHashMap<String, CinemaDetails>();
  final LinkedHashMap<String, SeriesDetails> _series =
      LinkedHashMap<String, SeriesDetails>();

  // ---------------- Comptes ----------------

  /// Comptes Xtream du client. Si la liste change (compte ajouté / retiré /
  /// poussé par le panel), tous les caches sont vidés.
  Future<List<CinemaSource>> sources() async {
    final List<Playlist> all = await PlaylistRepository.instance.getAllPlaylists();
    final List<CinemaSource> out = <CinemaSource>[];
    for (final Playlist p in all) {
      if (p.type != PlaylistType.xtream) continue;
      final String server = (p.xtreamServer ?? '').trim();
      final String user = (p.xtreamUsername ?? '').trim();
      if (server.isEmpty || user.isEmpty || p.id == null) continue;
      out.add(CinemaSource(
        key: 'p${p.id}',
        playlistId: p.id!,
        server: server.endsWith('/') ? server.substring(0, server.length - 1) : server,
        username: user,
        password: p.xtreamPassword ?? '',
      ));
    }
    final String sig = out.map((CinemaSource s) => '${s.key}@${s.server}/${s.username}').join(',');
    if (sig != _sourcesSig) {
      clear();
      _sourcesSig = sig;
      _sources = out;
    }
    return _sources;
  }

  CinemaSource? sourceByKey(String key) {
    for (final CinemaSource s in _sources) {
      if (s.key == key) return s;
    }
    return null;
  }

  XtreamClient _client(CinemaSource s) => _clients.putIfAbsent(
        s.key,
        () => XtreamClient(
          serverUrl: s.server,
          username: s.username,
          password: s.password,
          timeout: const Duration(seconds: 25),
        ),
      );

  // ---------------- Catégories ----------------

  /// Catégories fusionnées de tous les comptes (ordre du 1er compte).
  Future<List<CinemaCategory>> categories(CinemaKind kind) async {
    final List<CinemaSource> srcs = await sources();
    final List<CinemaCategory>? cached = _cats[kind];
    if (cached != null) return cached;

    final String action =
        kind == CinemaKind.movie ? 'get_vod_categories' : 'get_series_categories';
    final List<List<({String id, String name})>> perSource =
        await Future.wait(<Future<List<({String id, String name})>>>[
      for (final CinemaSource s in srcs)
        () async {
          try {
            final Uint8List? b = await _client(s).fetchActionBytes(action);
            if (b == null) return const <({String id, String name})>[];
            return parseCategories(decodeJsonBytes(b));
          } catch (e) {
            BlackBox.instance.warn('CINEMA', '${s.key} $action : $e');
            return const <({String id, String name})>[];
          }
        }(),
    ]);

    final LinkedHashMap<String, _CatBuilder> merged =
        LinkedHashMap<String, _CatBuilder>();
    final Map<String, Map<String, String>> keys = <String, Map<String, String>>{};
    for (int i = 0; i < srcs.length; i++) {
      final CinemaSource s = srcs[i];
      final Map<String, String> byId = keys.putIfAbsent(s.key, () => <String, String>{});
      for (final ({String id, String name}) c in perSource[i]) {
        final String pretty = ChannelClassifier.prettifyCategory(c.name);
        final String key = CinemaLanguage.searchKey(pretty);
        byId[c.id] = key;
        merged.putIfAbsent(key, () => _CatBuilder(pretty)).parts.add(CategoryRef(s.key, c.id));
      }
    }
    final List<CinemaCategory> out = <CinemaCategory>[
      for (final MapEntry<String, _CatBuilder> e in merged.entries)
        CinemaCategory(
          key: e.key,
          name: e.value.name,
          parts: List<CategoryRef>.unmodifiable(e.value.parts),
          languageKey: CinemaLanguage.detect(e.value.name),
          isAdult: isAdultCategory(e.value.name),
          isKids: isKidsCategory(e.value.name),
        ),
    ];
    _cats[kind] = out;
    _catKeys[kind] = keys;
    BlackBox.instance.info('CINEMA', '${kind.name} : ${out.length} catégories (${srcs.length} compte(s))');
    return out;
  }

  // ---------------- Titres d'une catégorie ----------------

  /// Titres d'une catégorie (cache LRU ; depuis l'index s'il est prêt).
  Future<List<CinemaTitle>> titles(CinemaKind kind, CinemaCategory cat) async {
    final String ck = '${kind.name}|${cat.key}';
    final List<CinemaTitle>? hit = _titles.remove(ck);
    if (hit != null) {
      _titles[ck] = hit; // remis en fin = « récemment utilisé »
      return hit;
    }
    List<CinemaTitle> out;
    if (_indexKind == kind && _indexDone) {
      out = _index.where((CinemaTitle t) => t.categoryKey == cat.key).toList(growable: false);
    } else {
      final String action = kind == CinemaKind.movie ? 'get_vod_streams' : 'get_series';
      final List<CinemaTitle> all = <CinemaTitle>[];
      for (final CategoryRef part in cat.parts) {
        final CinemaSource? s = sourceByKey(part.sourceKey);
        if (s == null) continue;
        try {
          final Uint8List? b = await _client(s).fetchActionBytes(
            action,
            extra: <String, String>{'category_id': part.categoryId},
          );
          if (b == null) continue;
          all.addAll(await _mapInIsolate(b, kind, s, cat.key));
        } catch (e) {
          BlackBox.instance.warn('CINEMA', '${s.key} « ${cat.name} » : $e');
        }
      }
      out = _dedupe(all);
    }
    _titles[ck] = out;
    while (_titles.length > _kTitleCacheMax) {
      _titles.remove(_titles.keys.first);
    }
    return out;
  }

  Future<List<CinemaTitle>> _mapInIsolate(
      Uint8List bytes, CinemaKind kind, CinemaSource s, String fallbackKey,
      {int max = kCinemaIndexMax}) {
    return compute(
      mapTitlesJob,
      TitlesJob(
        payload: TransferableTypedData.fromList(<Uint8List>[bytes]),
        kind: kind,
        source: s,
        categoryKeyById: _catKeys[kind]?[s.key] ?? const <String, String>{},
        fallbackCategoryKey: fallbackKey,
        max: max,
      ),
    );
  }

  /// Un même titre sur plusieurs comptes → une seule vignette.
  static List<CinemaTitle> _dedupe(List<CinemaTitle> all) {
    final Set<String> seen = <String>{};
    final List<CinemaTitle> out = <CinemaTitle>[];
    for (final CinemaTitle t in all) {
      if (seen.add('${t.searchKey}|${t.year ?? ''}')) out.add(t);
    }
    return out;
  }

  // ---------------- Index (recherche, récents, compteurs) ----------------

  bool indexReady(CinemaKind kind) => _indexKind == kind && _indexDone;

  /// Lance (une fois) la construction de l'index de [kind] en arrière-plan.
  Future<void> ensureIndex(CinemaKind kind) {
    if (_indexKind == kind && _indexing != null) return _indexing!;
    // Un seul type indexé à la fois : on libère l'autre.
    _indexKind = kind;
    _index = const <CinemaTitle>[];
    _indexDone = false;
    _indexCounts = const <String, int>{};
    _recent = null;
    final Future<void> f = _buildIndex(kind, ++_indexGen);
    _indexing = f;
    return f;
  }

  Future<void> _buildIndex(CinemaKind kind, int gen) async {
    bool stale() => gen != _indexGen || _indexKind != kind;
    final List<CinemaCategory> cats = await categories(kind);
    final String action = kind == CinemaKind.movie ? 'get_vod_streams' : 'get_series';
    final List<CinemaTitle> acc = <CinemaTitle>[];
    final Set<String> seen = <String>{};
    void add(List<CinemaTitle> list) {
      for (final CinemaTitle t in list) {
        if (acc.length >= kCinemaIndexMax) return;
        if (seen.add('${t.searchKey}|${t.year ?? ''}')) acc.add(t);
      }
    }

    void publish() {
      if (stale()) return;
      _index = List<CinemaTitle>.unmodifiable(acc);
      _recent = null;
      indexVersion.value++;
    }

    final Stopwatch sw = Stopwatch()..start();
    for (final CinemaSource s in _sources) {
      if (stale() || acc.length >= kCinemaIndexMax) break;
      try {
        final Uint8List? whole =
            await _client(s).fetchActionBytes(action, softMax: kCinemaSingleShotBytes);
        if (whole != null) {
          add(await _mapInIsolate(whole, kind, s, '',
              max: kCinemaIndexMax - acc.length));
          publish();
          continue;
        }
        // Trop gros pour un bloc : catégorie par catégorie (léger, progressif).
        int n = 0;
        for (final CinemaCategory c in cats) {
          if (stale() || acc.length >= kCinemaIndexMax) break;
          for (final CategoryRef part in c.parts) {
            if (part.sourceKey != s.key) continue;
            try {
              final Uint8List? b = await _client(s).fetchActionBytes(
                action,
                extra: <String, String>{'category_id': part.categoryId},
              );
              if (b != null) add(await _mapInIsolate(b, kind, s, c.key));
            } catch (e) {
              BlackBox.instance.warn('CINEMA', 'index « ${c.name} » : $e');
            }
          }
          if (++n % 8 == 0) publish();
        }
        publish();
      } catch (e) {
        BlackBox.instance.warn('CINEMA', 'index ${s.key} : $e');
      }
    }
    if (stale()) return;
    final Map<String, int> counts = <String, int>{};
    for (final CinemaTitle t in acc) {
      counts[t.categoryKey] = (counts[t.categoryKey] ?? 0) + 1;
    }
    _indexCounts = counts;
    _indexDone = true;
    publish();
    BlackBox.instance.info('CINEMA',
        'index ${kind.name} : ${acc.length} titres en ${sw.elapsedMilliseconds} ms');
  }

  /// Nombre de titres d'une catégorie (null tant que l'index n'est pas fini).
  int? countFor(CinemaKind kind, String catKey) =>
      indexReady(kind) ? (_indexCounts[catKey] ?? 0) : null;

  /// « Récemment ajoutés » (depuis l'index, du plus récent au plus ancien).
  List<CinemaTitle> recent(CinemaKind kind, {Set<String>? allowedCats, int max = 80}) {
    if (_indexKind != kind || _index.isEmpty) return const <CinemaTitle>[];
    final List<CinemaTitle> sorted = _recent ??= (List<CinemaTitle>.of(
        _index.where((CinemaTitle t) => t.addedAt > 0))
      ..sort((CinemaTitle a, CinemaTitle b) => b.addedAt.compareTo(a.addedAt)));
    final Iterable<CinemaTitle> it = allowedCats == null
        ? sorted
        : sorted.where((CinemaTitle t) => allowedCats.contains(t.categoryKey));
    return it.take(max).toList(growable: false);
  }

  /// Recherche (tous les mots de la requête doivent être dans le nom).
  List<CinemaTitle> search(CinemaKind kind, String query,
      {Set<String>? allowedCats, int max = 80}) {
    final List<String> words = CinemaLanguage.searchKey(query)
        .split(' ')
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const <CinemaTitle>[];
    Iterable<CinemaTitle> pool = _indexKind == kind ? _index : const <CinemaTitle>[];
    if (pool.isEmpty) {
      // Index pas encore là : on cherche dans les catégories déjà ouvertes.
      pool = <CinemaTitle>[
        for (final MapEntry<String, List<CinemaTitle>> e in _titles.entries)
          if (e.key.startsWith('${kind.name}|')) ...e.value,
      ];
    }
    final List<CinemaTitle> out = <CinemaTitle>[];
    for (final CinemaTitle t in pool) {
      if (allowedCats != null && !allowedCats.contains(t.categoryKey)) continue;
      bool ok = true;
      for (final String w in words) {
        if (!t.searchKey.contains(w)) {
          ok = false;
          break;
        }
      }
      if (ok) {
        out.add(t);
        if (out.length >= max) break;
      }
    }
    return out;
  }

  // ---------------- Fiches détaillées ----------------

  Future<CinemaDetails> movieDetails(CinemaTitle t) async {
    final CinemaDetails? hit = _details[t.id];
    if (hit != null) return hit;
    final CinemaSource? s = sourceByKey(t.sourceKey);
    if (s == null) return CinemaDetails.empty;
    try {
      final Uint8List? b = await _client(s).fetchActionBytes(
        'get_vod_info',
        extra: <String, String>{'vod_id': t.remoteId},
      );
      final CinemaDetails d =
          b == null ? CinemaDetails.empty : parseVodInfo(decodeJsonBytes(b));
      _details[t.id] = d;
      while (_details.length > 200) {
        _details.remove(_details.keys.first);
      }
      return d;
    } catch (e) {
      BlackBox.instance.warn('CINEMA', 'fiche film ${t.id} : $e');
      return CinemaDetails.empty;
    }
  }

  Future<SeriesDetails?> seriesDetails(CinemaTitle t) async {
    final SeriesDetails? hit = _series[t.id];
    if (hit != null) return hit;
    final CinemaSource? s = sourceByKey(t.sourceKey) ??
        (await sources()).where((CinemaSource x) => x.key == t.sourceKey).firstOrNull;
    if (s == null) return null;
    try {
      final Uint8List? b = await _client(s).fetchActionBytes(
        'get_series_info',
        extra: <String, String>{'series_id': t.remoteId},
      );
      if (b == null) return null;
      final SeriesDetails d = await compute(
        _seriesInIsolate,
        (
          payload: TransferableTypedData.fromList(<Uint8List>[b]),
          source: s,
          seriesId: t.id,
          name: t.name,
        ),
      );
      _series[t.id] = d;
      while (_series.length > 20) {
        _series.remove(_series.keys.first);
      }
      return d;
    } catch (e) {
      BlackBox.instance.warn('CINEMA', 'fiche série ${t.id} : $e');
      return null;
    }
  }

  /// Vide tout (comptes changés, ou libération mémoire).
  void clear() {
    for (final XtreamClient c in _clients.values) {
      c.dispose();
    }
    _clients.clear();
    _cats.clear();
    _catKeys.clear();
    _titles.clear();
    _details.clear();
    _series.clear();
    _indexKind = null;
    _indexGen++;
    _index = const <CinemaTitle>[];
    _indexDone = false;
    _indexing = null;
    _indexCounts = const <String, int>{};
    _recent = null;
    indexVersion.value++;
  }

  /// Libère la mémoire lourde en quittant le Cinéma (l'index sera rebâti à
  /// la prochaine ouverture ; les catégories restent pour un retour rapide).
  void trim() {
    _titles.clear();
    _indexKind = null;
    _indexGen++;
    _index = const <CinemaTitle>[];
    _indexDone = false;
    _indexing = null;
    _indexCounts = const <String, int>{};
    _recent = null;
  }
}

class _CatBuilder {
  _CatBuilder(this.name);
  final String name;
  final List<CategoryRef> parts = <CategoryRef>[];
}

/// Point d'entrée isolate pour `get_series_info` (réponse parfois lourde :
/// des centaines d'épisodes avec leurs résumés).
SeriesDetails _seriesInIsolate(
    ({TransferableTypedData payload, CinemaSource source, String seriesId, String name}) job) {
  return parseSeriesInfo(
    decodeJsonBytes(job.payload.materialize().asUint8List()),
    source: job.source,
    seriesId: job.seriesId,
    seriesName: job.name,
  );
}

// ---------------------------------------------------------
//  Classement « adulte » / « enfants » d'une catégorie
// ---------------------------------------------------------

/// Mots propres aux catalogues VOD enfants (en plus de ceux du Direct).
const List<String> _kKidsVodWords = <String>[
  'kids', 'enfant', 'jeunesse', 'animation', 'anime', 'dessin anime',
  'dessins animes', 'cartoon', 'famille', 'family', 'disney', 'pixar',
  'dreamworks', 'infantil', 'kinder', 'bambini', 'cocuk', 'детск',
  '儿童', '动画', '動畫', 'أطفال', 'كرتون', 'बच्चों',
];

bool isAdultCategory(String name) =>
    ChannelClassifier.classifyGenre('', name) == ChannelGenre.adult;

bool isKidsCategory(String name) {
  if (isAdultCategory(name)) return false;
  if (ChannelClassifier.classifyGenre('', name) == ChannelGenre.kids) return true;
  final String k = CinemaLanguage.searchKey(name);
  for (final String w in _kKidsVodWords) {
    if (k.contains(w)) return true;
  }
  return false;
}
