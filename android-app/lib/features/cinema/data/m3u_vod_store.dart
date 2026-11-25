// =========================================================
//  m3u_vod_store.dart — Films et séries d'un M3U, rangés comme un « faux Xtream »
// =========================================================
//  POURQUOI : tout le module Cinéma (catégories fusionnées, index de
//  recherche, catalogue sur disque, fiches séries) sait lire les réponses de
//  l'API Xtream (`get_vod_categories`, `get_vod_streams`, `get_series`…).
//  Plutôt que de le réécrire, on FABRIQUE ces mêmes réponses à partir du M3U :
//
//    M3U (fichier ou lien)  →  lecteur ligne à ligne  →  dossier de fichiers
//    JSON « au format Xtream »  →  lus tels quels par le module Cinéma.
//
//  Contenu du dossier (un par source) :
//    movie_categories.json / series_categories.json   liste des catégories
//    movies_<cat>.json    films d'UNE catégorie       (get_vod_streams)
//    series_<cat>.json    séries d'UNE catégorie      (get_series)
//    episodes.pack        une fiche par série, bout à bout (get_series_info)
//    episodes.idx.json    série → [début, longueur] dans episodes.pack
//    urls.tsv             film → adresse de lecture (voir plus bas)
//    meta.json            version, date, signature de la source, compteurs
//
//  Les catégories sont CELLES DU M3U (`group-title`) : « toutes les
//  catégories du M3U ». Aucun nom n'est inventé.
//
//  Les adresses de lecture contiennent les identifiants du client : elles ne
//  vont JAMAIS dans le catalogue partagé (zuno_catalog, testé « sans mot de
//  passe ni URL »). Elles restent ici, dans ce dossier privé de l'application,
//  au même niveau de confidentialité que la base des chaînes.
//
//  Écriture : dans un ISOLATE (le M3U d'un gros fournisseur fait 30 à 100 Mo).
//  Lecture : octets bruts, décodés plus loin par les isolates du module.
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/cinema_language.dart';
import '../domain/m3u_vod_classifier.dart';
import 'm3u_vod_scanner.dart';

/// Change quand le format des fichiers change : un dossier d'une autre
/// version est reconstruit au lieu d'être mal lu.
const int kM3uVodStoreVersion = 1;

/// Plafonds anti-mémoire (box 1 Go). Au-delà, on garde le début du M3U et on
/// le dit dans la boîte noire (`truncated`).
const int kM3uVodMaxMovies = 80000;
const int kM3uVodMaxEpisodes = 200000;

/// Empreinte courte et stable d'un texte : deux calculs FNV-1a de 32 bits
/// (graines différentes) mis bout à bout. Sert d'identifiant de film /
/// épisode / série quand l'adresse n'en porte pas.
String m3uVodHash(String text) {
  int a = 0x811c9dc5;
  int b = 0x9747b28c;
  for (final int unit in text.codeUnits) {
    a = ((a ^ unit) * 0x01000193) & 0xFFFFFFFF;
    b = ((b ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return a.toRadixString(36) + b.toRadixString(36);
}

final RegExp _rxXtreamId = RegExp(r'/(?:movie|series)/[^/]+/[^/]+/(\d+)\.[A-Za-z0-9]{1,5}$');

/// Identifiant d'un film / épisode : le NUMÉRO du fournisseur quand l'adresse
/// est de type Xtream (`…/movie/user/pass/12345.mkv` → « 12345 » : le même
/// numéro que l'API, donc l'historique « Reprendre » survit à un changement de
/// mot de passe), sinon une empreinte de l'adresse (préfixe « h »).
String m3uVodIdForUrl(String url) {
  final RegExpMatch? m =
      _rxXtreamId.firstMatch(M3uVodClassifier.pathOf(url));
  if (m != null) return m.group(1)!;
  return 'h${m3uVodHash(url)}';
}

/// Un identifiant qui N'EST PAS un numéro de fournisseur : catégories
/// `mg1`/`sg1`, séries `q…`, films/épisodes `h…`. Sert à aiguiller un appel
/// vers le M3U plutôt que vers l'API (voir FallbackCinemaApi).
bool m3uVodIsOwnId(String? id) =>
    id != null && id.isNotEmpty && !RegExp(r'^\d+$').hasMatch(id);

// ---------------------------------------------------------
//  Adresses de lecture des films (mémoire, remplie au démarrage)
// ---------------------------------------------------------

/// `CinemaSource.movieUrl` demande l'adresse d'un film SANS attendre :
/// l'index est donc gardé en mémoire (film → adresse), par source.
abstract final class M3uUrlBook {
  static final Map<String, Map<String, String>> _books =
      <String, Map<String, String>>{};

  static void install(String sourceKey, Map<String, String> urls) {
    _books[sourceKey] = urls;
  }

  static void remove(String sourceKey) => _books.remove(sourceKey);

  static bool has(String sourceKey) => _books.containsKey(sourceKey);

  static String? lookup(String sourceKey, String id) => _books[sourceKey]?[id];

  @pragma('vm:prefer-inline')
  static int sizeOf(String sourceKey) => _books[sourceKey]?.length ?? 0;

  static void clearAll() => _books.clear();
}

// ---------------------------------------------------------
//  Fabrication (dans un isolate)
// ---------------------------------------------------------

class _Cat {
  _Cat(this.id, this.name);
  final String id;
  final String name;
  int count = 0;
}

class _Movie {
  _Movie(this.id, this.name, this.ext, this.url, this.logo, this.order);
  final String id;
  final String name;
  final String ext;
  final String url;
  final String? logo;
  final int order;
}

class _Ep {
  _Ep(this.id, this.number, this.name, this.ext, this.url, this.order);
  final String id;
  final int number;
  final String name;
  final String ext;
  final String url;
  final int order;
}

class _Series {
  _Series(this.id, this.name, this.catId, this.logo, this.order);
  final String id;
  final String name;
  final String catId;

  /// Affiche : celle du premier épisode qui en a une.
  String? logo;
  final int order;
  final Map<int, List<_Ep>> seasons = <int, List<_Ep>>{};
}

/// Résultat d'une fabrication.
class M3uVodSummary {
  const M3uVodSummary({
    this.movies = 0,
    this.series = 0,
    this.episodes = 0,
    this.movieCategories = 0,
    this.seriesCategories = 0,
    this.urlsSeen = 0,
    this.truncated = false,
    this.error,
  });

  final int movies;
  final int series;
  final int episodes;
  final int movieCategories;
  final int seriesCategories;

  /// Adresses lues dans le M3U, directs compris.
  final int urlsSeen;

  /// Un plafond a coupé la lecture.
  final bool truncated;

  /// Message lisible si la fabrication a échoué.
  final String? error;

  bool get ok => error == null;
  bool get isEmpty => movies == 0 && episodes == 0;
}

/// Range les entrées d'un M3U : catégories, films, séries (épisodes groupés).
class M3uVodBuilder {
  M3uVodBuilder({
    this.maxMovies = kM3uVodMaxMovies,
    this.maxEpisodes = kM3uVodMaxEpisodes,
  });

  final int maxMovies;
  final int maxEpisodes;

  final Map<String, _Cat> _movieCats = <String, _Cat>{};
  final Map<String, _Cat> _seriesCats = <String, _Cat>{};
  final Map<String, List<_Movie>> _movies = <String, List<_Movie>>{};
  final Map<String, _Series> _series = <String, _Series>{};
  final Set<String> _seenMovie = <String>{};
  final Set<String> _seenEpisode = <String>{};
  int _movieCount = 0;
  int _episodeCount = 0;
  int _order = 0;

  /// Les deux plafonds sont atteints : inutile de lire la suite du M3U.
  bool get full => _movieCount >= maxMovies && _episodeCount >= maxEpisodes;
  bool truncated = false;

  static String _categoryName(String raw) {
    final String t = raw.trim();
    return t.isEmpty ? 'Autres' : t;
  }

  /// Dernière catégorie vue, par type : un M3U range ses lignes par
  /// catégorie, on évite de renormaliser le même texte 100 000 fois.
  final Map<String, String> _lastRaw = <String, String>{};
  final Map<String, _Cat> _lastCat = <String, _Cat>{};

  _Cat _cat(Map<String, _Cat> cats, String prefix, String raw) {
    final _Cat? last = _lastCat[prefix];
    if (last != null && _lastRaw[prefix] == raw) return last;
    final String name = _categoryName(raw);
    final String key = CinemaLanguage.searchKey(name);
    final _Cat found = cats.putIfAbsent(
        key, () => _Cat('$prefix${cats.length + 1}', name));
    _lastRaw[prefix] = raw;
    _lastCat[prefix] = found;
    return found;
  }

  void add(M3uVodEntry e) {
    _order++;
    if (e.kind == M3uVodKind.movie) {
      if (_movieCount >= maxMovies) {
        truncated = true;
        return;
      }
      final _Cat cat = _cat(_movieCats, 'mg', e.category);
      final String id = m3uVodIdForUrl(e.url);
      if (!_seenMovie.add('${cat.id}|$id')) return;
      cat.count++;
      _movieCount++;
      _movies
          .putIfAbsent(cat.id, () => <_Movie>[])
          .add(_Movie(id, e.name, e.ext, e.url, e.logo, _order));
      return;
    }
    if (_episodeCount >= maxEpisodes) {
      truncated = true;
      return;
    }
    final _Cat cat = _cat(_seriesCats, 'sg', e.category);
    final String seriesKey =
        '${cat.id}|${CinemaLanguage.searchKey(e.series)}';
    final String epId = m3uVodIdForUrl(e.url);
    if (!_seenEpisode.add('$seriesKey|$epId')) return;
    _Series? s = _series[seriesKey];
    if (s == null) {
      s = _Series('q${m3uVodHash(seriesKey)}', e.series, cat.id, e.logo, _order);
      _series[seriesKey] = s;
      cat.count++;
    }
    _episodeCount++;
    s.logo ??= e.logo;
    s.seasons
        .putIfAbsent(e.season, () => <_Ep>[])
        .add(_Ep(epId, e.episode, e.name, e.ext, e.url, _order));
  }

  /// Écrit le dossier. À appeler UNE fois, dans l'isolate.
  M3uVodSummary write(
    Directory dir, {
    required String signature,
    required int builtAtMs,
    int urlsSeen = 0,
  }) {
    dir.createSync(recursive: true);
    String path(String name) => '${dir.path}${Platform.pathSeparator}$name';

    // ---- Films ----
    final List<Map<String, Object?>> movieCats = <Map<String, Object?>>[];
    for (final _Cat c in _movieCats.values) {
      if (c.count == 0) continue;
      movieCats.add(<String, Object?>{
        'category_id': c.id,
        'category_name': c.name,
      });
      final List<_Movie> list = _movies[c.id] ?? const <_Movie>[];
      File(path('movies_${c.id}.json')).writeAsStringSync(jsonEncode(<Object>[
        for (final _Movie m in list)
          <String, Object?>{
            'stream_id': m.id,
            'name': m.name,
            'stream_icon': m.logo ?? '',
            'container_extension': m.ext,
            'category_id': c.id,
            // Le M3U n'a pas de date : l'ordre du fichier fait foi (les
            // ajouts récents sont en général à la fin). Sert à « Récemment
            // ajoutés », jamais affiché comme une date.
            'added': '${m.order}',
            'zuno_url': m.url,
          },
      ]));
    }
    File(path('movie_categories.json')).writeAsStringSync(jsonEncode(movieCats));

    // Adresses des films, une par ligne : « identifiant<TAB>adresse ».
    final StringBuffer book = StringBuffer();
    final Set<String> booked = <String>{};
    for (final List<_Movie> list in _movies.values) {
      for (final _Movie m in list) {
        if (!booked.add(m.id)) continue;
        book
          ..write(m.id)
          ..write('\t')
          ..write(m.url.replaceAll(RegExp(r'[\t\r\n]'), ''))
          ..write('\n');
      }
    }
    File(path('urls.tsv')).writeAsStringSync(book.toString());

    // ---- Séries ----
    final Map<String, List<_Series>> byCat = <String, List<_Series>>{};
    for (final _Series s in _series.values) {
      byCat.putIfAbsent(s.catId, () => <_Series>[]).add(s);
    }
    final List<Map<String, Object?>> seriesCats = <Map<String, Object?>>[];
    for (final _Cat c in _seriesCats.values) {
      if (c.count == 0) continue;
      seriesCats.add(<String, Object?>{
        'category_id': c.id,
        'category_name': c.name,
      });
      File(path('series_${c.id}.json')).writeAsStringSync(jsonEncode(<Object>[
        for (final _Series s in byCat[c.id] ?? const <_Series>[])
          <String, Object?>{
            'series_id': s.id,
            'name': s.name,
            'cover': s.logo ?? '',
            'category_id': c.id,
            'last_modified': '${s.order}',
          },
      ]));
    }
    File(path('series_categories.json')).writeAsStringSync(jsonEncode(seriesCats));

    // Fiche de chaque série (saisons, épisodes), bout à bout dans UN fichier.
    final Map<String, List<int>> index = <String, List<int>>{};
    final RandomAccessFile pack =
        File(path('episodes.pack')).openSync(mode: FileMode.write);
    try {
      int offset = 0;
      for (final _Series s in _series.values) {
        final Map<String, Object?> episodes = <String, Object?>{};
        final List<int> numbers = s.seasons.keys.toList()..sort();
        for (final int season in numbers) {
          final List<_Ep> eps = s.seasons[season]!;
          // Sans numéro dans le nom (0) : l'ordre du M3U donne le numéro.
          eps.sort((_Ep a, _Ep b) {
            final int byNumber = a.number.compareTo(b.number);
            return byNumber != 0 ? byNumber : a.order.compareTo(b.order);
          });
          int running = 0;
          episodes['$season'] = <Object>[
            for (final _Ep e in eps)
              <String, Object?>{
                'id': e.id,
                'episode_num': e.number > 0 ? e.number : ++running,
                'title': e.name,
                'container_extension': e.ext,
                'season': season,
                'zuno_url': e.url,
              },
          ];
        }
        final Uint8List doc = Uint8List.fromList(utf8.encode(jsonEncode(
          <String, Object?>{
            'info': <String, Object?>{'name': s.name, 'cover': s.logo ?? ''},
            'episodes': episodes,
          },
        )));
        pack.writeFromSync(doc);
        index[s.id] = <int>[offset, doc.length];
        offset += doc.length;
      }
    } finally {
      pack.closeSync();
    }
    File(path('episodes.idx.json')).writeAsStringSync(jsonEncode(index));

    final M3uVodSummary summary = M3uVodSummary(
      movies: _movieCount,
      series: _series.length,
      episodes: _episodeCount,
      movieCategories: movieCats.length,
      seriesCategories: seriesCats.length,
      urlsSeen: urlsSeen,
      truncated: truncated,
    );
    File(path('meta.json')).writeAsStringSync(jsonEncode(<String, Object?>{
      'v': kM3uVodStoreVersion,
      'builtAt': builtAtMs,
      'sig': signature,
      'movies': summary.movies,
      'series': summary.series,
      'episodes': summary.episodes,
      'movieCats': summary.movieCategories,
      'seriesCats': summary.seriesCategories,
      'urls': urlsSeen,
      'truncated': truncated,
    }));
    return summary;
  }
}

/// Travail envoyé à l'isolate : lire [m3uPath], écrire le dossier [outPath].
class M3uVodBuildJob {
  const M3uVodBuildJob({
    required this.m3uPath,
    required this.outPath,
    required this.signature,
    this.maxMovies = kM3uVodMaxMovies,
    this.maxEpisodes = kM3uVodMaxEpisodes,
  });

  final String m3uPath;
  final String outPath;
  final String signature;
  final int maxMovies;
  final int maxEpisodes;
}

/// Point d'entrée de l'isolate (fonction de plus haut niveau, pour `compute`).
/// Écrit dans « <dossier>.tmp » puis remplace le dossier d'un coup : une
/// coupure en route ne laisse jamais un dossier à moitié écrit.
Future<M3uVodSummary> buildM3uVodStore(M3uVodBuildJob job) async {
  final Directory out = Directory(job.outPath);
  final Directory tmp = Directory('${job.outPath}.tmp');
  try {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    final M3uVodBuilder builder =
        M3uVodBuilder(maxMovies: job.maxMovies, maxEpisodes: job.maxEpisodes);
    final M3uVodScanner scanner = M3uVodScanner(onEntry: builder.add);
    final Stream<String> lines = File(job.m3uPath)
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    await for (final String line in lines) {
      scanner.feed(line);
      if (builder.full) {
        builder.truncated = true;
        break;
      }
    }
    final M3uVodSummary summary = builder.write(
      tmp,
      signature: job.signature,
      builtAtMs: DateTime.now().millisecondsSinceEpoch,
      urlsSeen: scanner.urls,
    );
    if (out.existsSync()) out.deleteSync(recursive: true);
    tmp.renameSync(out.path);
    return summary;
  } catch (e) {
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
    return M3uVodSummary(error: e.toString());
  }
}

// ---------------------------------------------------------
//  Lecture (fil principal : octets bruts, pas de décodage)
// ---------------------------------------------------------

/// En-tête du dossier.
class M3uVodMeta {
  const M3uVodMeta({
    required this.builtAtMs,
    required this.signature,
    required this.movies,
    required this.series,
    required this.episodes,
    required this.truncated,
  });

  final int builtAtMs;
  final String signature;
  final int movies;
  final int series;
  final int episodes;
  final bool truncated;

  Duration age(DateTime now) =>
      now.difference(DateTime.fromMillisecondsSinceEpoch(builtAtMs));
}

class M3uVodStore {
  M3uVodStore(this.dir);
  final Directory dir;

  Map<String, List<int>>? _index;

  static final RegExp _rxSafeId = RegExp(r'^[A-Za-z0-9_]{1,40}$');

  File _file(String name) =>
      File('${dir.path}${Platform.pathSeparator}$name');

  /// Dossier absent, d'une autre version ou illisible : `null`.
  Future<M3uVodMeta?> readMeta() async {
    try {
      final File f = _file('meta.json');
      if (!await f.exists()) return null;
      final Object? raw = jsonDecode(await f.readAsString());
      if (raw is! Map || raw['v'] != kM3uVodStoreVersion) return null;
      return M3uVodMeta(
        builtAtMs: (raw['builtAt'] as num?)?.toInt() ?? 0,
        signature: raw['sig']?.toString() ?? '',
        movies: (raw['movies'] as num?)?.toInt() ?? 0,
        series: (raw['series'] as num?)?.toInt() ?? 0,
        episodes: (raw['episodes'] as num?)?.toInt() ?? 0,
        truncated: raw['truncated'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _bytes(String name) async {
    try {
      final File f = _file(name);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Catégories (réponse de `get_vod_categories` / `get_series_categories`).
  Future<Uint8List?> categories({required bool movies}) =>
      _bytes(movies ? 'movie_categories.json' : 'series_categories.json');

  /// Titres d'UNE catégorie (réponse de `get_vod_streams&category_id=` /
  /// `get_series&category_id=`). Identifiant inconnu ou suspect : `null`.
  Future<Uint8List?> titles({required bool movies, required String categoryId}) {
    if (!_rxSafeId.hasMatch(categoryId)) return Future<Uint8List?>.value(null);
    return _bytes('${movies ? 'movies' : 'series'}_$categoryId.json');
  }

  /// Fiche d'une série (réponse de `get_series_info&series_id=`).
  Future<Uint8List?> seriesInfo(String seriesId) async {
    if (!_rxSafeId.hasMatch(seriesId)) return null;
    try {
      Map<String, List<int>>? index = _index;
      if (index == null) {
        final Uint8List? raw = await _bytes('episodes.idx.json');
        if (raw == null) return null;
        final Object? decoded = jsonDecode(utf8.decode(raw));
        if (decoded is! Map) return null;
        index = <String, List<int>>{
          for (final MapEntry<dynamic, dynamic> e in decoded.entries)
            if (e.value is List && (e.value as List).length == 2)
              e.key.toString(): <int>[
                (e.value as List)[0] as int,
                (e.value as List)[1] as int,
              ],
        };
        _index = index;
      }
      final List<int>? at = index[seriesId];
      if (at == null) return null;
      final RandomAccessFile f = await _file('episodes.pack').open();
      try {
        await f.setPosition(at[0]);
        return await f.read(at[1]);
      } finally {
        await f.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Film → adresse, lu par tranches pour ne pas figer l'écran.
  Future<Map<String, String>> readUrlBook() async {
    final Map<String, String> out = <String, String>{};
    try {
      final File f = _file('urls.tsv');
      if (!await f.exists()) return out;
      final List<String> lines = const LineSplitter().convert(await f.readAsString());
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        final int tab = line.indexOf('\t');
        if (tab > 0) out[line.substring(0, tab)] = line.substring(tab + 1);
        if (i % 4000 == 3999) await Future<void>.delayed(Duration.zero);
      }
    } catch (_) {
      // Livre illisible : les films s'afficheront sans adresse (non lisibles)
      // jusqu'à la prochaine reconstruction.
    }
    return out;
  }
}
