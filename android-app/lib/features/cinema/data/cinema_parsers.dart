// =========================================================
//  cinema_parsers.dart — Lecture des réponses Xtream (films / séries)
// =========================================================
//  Fonctions PURES (aucun réseau, aucun widget) :
//    • testables unitairement avec de vrais JSON d'exemple ;
//    • appelables dans un ISOLATE (compute) : une liste de 30 000 films pèse
//      plusieurs Mo de JSON, son décodage ne doit JAMAIS geler l'écran.
//
//  Les panels Xtream sont hétérogènes : un même champ arrive en nombre, en
//  texte, vide, ou absent ; `info` peut être une liste vide au lieu d'un
//  objet ; `episodes` peut être un objet {"1": [...]} ou une liste de
//  listes. Chaque lecteur ci-dessous tolère ces variantes.
// =========================================================
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../domain/cinema_language.dart';
import '../domain/cinema_models.dart';

/// Décode du JSON directement depuis les OCTETS (UTF-8 + JSON fusionnés :
/// pas de grosse String intermédiaire en mémoire).
dynamic decodeJsonBytes(Uint8List bytes) =>
    const Utf8Decoder(allowMalformed: true)
        .fuse(const JsonDecoder())
        .convert(bytes);

/// Réponse « liste » : tolère l'enveloppe `{data: [...]}` de certains panels.
List<dynamic> asJsonList(dynamic decoded) {
  if (decoded is List<dynamic>) return decoded;
  if (decoded is Map && decoded['data'] is List) {
    return decoded['data'] as List<dynamic>;
  }
  return const <dynamic>[];
}

/// Catégories : liste de (id, nom).
List<({String id, String name})> parseCategories(dynamic decoded) {
  final List<({String id, String name})> out = <({String id, String name})>[];
  for (final dynamic item in asJsonList(decoded)) {
    if (item is! Map) continue;
    final String id = _str(item['category_id']) ?? '';
    final String name = (_str(item['category_name']) ?? '').trim();
    if (id.isEmpty || name.isEmpty) continue;
    out.add((id: id, name: name));
  }
  return out;
}

/// Travail envoyé à l'isolate de mapping (types envoyables uniquement).
class TitlesJob {
  const TitlesJob({
    required this.payload,
    required this.kind,
    required this.source,
    required this.categoryKeyById,
    this.fallbackCategoryKey = '',
    this.max = 40000,
  });
  final TransferableTypedData payload;
  final CinemaKind kind;
  final CinemaSource source;
  final Map<String, String> categoryKeyById;
  final String fallbackCategoryKey;
  final int max;
}

/// Point d'entrée isolate : octets → [CinemaTitle].
List<CinemaTitle> mapTitlesJob(TitlesJob job) {
  final Uint8List bytes = job.payload.materialize().asUint8List();
  return mapTitles(
    decodeJsonBytes(bytes),
    kind: job.kind,
    source: job.source,
    categoryKeyById: job.categoryKeyById,
    fallbackCategoryKey: job.fallbackCategoryKey,
    max: job.max,
  );
}

/// Liste `get_vod_streams` / `get_series` → vignettes.
List<CinemaTitle> mapTitles(
  dynamic decoded, {
  required CinemaKind kind,
  required CinemaSource source,
  required Map<String, String> categoryKeyById,
  String fallbackCategoryKey = '',
  int max = 40000,
}) {
  final bool movie = kind == CinemaKind.movie;
  final List<CinemaTitle> out = <CinemaTitle>[];
  for (final dynamic item in asJsonList(decoded)) {
    if (out.length >= max) break; // plafond mémoire (box 1 Go)
    if (item is! Map) continue;
    final String remoteId =
        _str(movie ? item['stream_id'] : item['series_id']) ?? '';
    if (remoteId.isEmpty) continue;
    final String rawName = (_str(item['name']) ?? '').trim();
    if (rawName.isEmpty) continue;

    final String catId = _str(item['category_id']) ?? '';
    final String catKey = categoryKeyById[catId] ?? fallbackCategoryKey;

    String ext = (_str(item['container_extension']) ?? 'mp4').trim();
    if (ext.isEmpty) ext = 'mp4';

    final String? year = _year(
      _str(item['year']) ?? _str(item['releaseDate']) ?? _str(item['release_date']),
      rawName,
    );
    out.add(CinemaTitle(
      id: '${source.key}:${movie ? 'm' : 's'}:$remoteId',
      kind: kind,
      sourceKey: source.key,
      remoteId: remoteId,
      name: rawName,
      categoryKey: catKey,
      searchKey: CinemaLanguage.searchKey(rawName),
      posterUrl: _url(movie ? item['stream_icon'] : item['cover']),
      rating: _rating(item['rating'], item['rating_5based']),
      year: year,
      addedAt: _int(movie ? item['added'] : (item['last_modified'] ?? item['added'])),
      containerExt: ext,
      streamUrl: movie ? source.movieUrl(remoteId, ext) : null,
      plot: movie ? null : _text(item['plot']),
    ));
  }
  return out;
}

/// `get_vod_info` → fiche film.
CinemaDetails parseVodInfo(dynamic decoded) {
  if (decoded is! Map) return CinemaDetails.empty;
  final dynamic infoRaw = decoded['info'];
  final Map<dynamic, dynamic> info =
      infoRaw is Map ? infoRaw : const <dynamic, dynamic>{};
  int dur = _int(info['duration_secs']);
  if (dur == 0) dur = _hmsToSeconds(_str(info['duration']));
  return CinemaDetails(
    plot: _text(info['plot']) ?? _text(info['description']),
    cast: _text(info['cast']) ?? _text(info['actors']),
    director: _text(info['director']),
    genre: _text(info['genre']),
    releaseDate: _text(info['releasedate']) ?? _text(info['release_date']),
    durationSec: dur,
    backdropUrl: _firstUrl(info['backdrop_path']),
    posterUrl: _url(info['movie_image']) ?? _url(info['cover_big']),
    rating: _rating(info['rating'], info['rating_5based']),
  );
}

/// `get_series_info` → saisons + épisodes + fiche.
SeriesDetails parseSeriesInfo(
  dynamic decoded, {
  required CinemaSource source,
  required String seriesId,
  String seriesName = '',
}) {
  if (decoded is! Map) {
    return const SeriesDetails(
      details: CinemaDetails.empty,
      seasons: <CinemaSeason>[],
      episodes: <int, List<CinemaEpisode>>{},
    );
  }
  final dynamic infoRaw = decoded['info'];
  final Map<dynamic, dynamic> info =
      infoRaw is Map ? infoRaw : const <dynamic, dynamic>{};
  final int runMinutes = _int(info['episode_run_time']);
  final CinemaDetails details = CinemaDetails(
    plot: _text(info['plot']),
    cast: _text(info['cast']),
    director: _text(info['director']),
    genre: _text(info['genre']),
    releaseDate: _text(info['releaseDate']) ?? _text(info['release_date']),
    durationSec: runMinutes * 60,
    backdropUrl: _firstUrl(info['backdrop_path']),
    posterUrl: _url(info['cover']),
    rating: _rating(info['rating'], info['rating_5based']),
  );

  // ----- Épisodes (objet {"1": [...]} OU liste de listes) -----
  final Map<int, List<CinemaEpisode>> eps = <int, List<CinemaEpisode>>{};
  void addEpisode(dynamic e, int? seasonHint) {
    if (e is! Map) return;
    final String id = _str(e['id']) ?? '';
    if (id.isEmpty) return;
    final int season = _int(e['season']) != 0 ? _int(e['season']) : (seasonHint ?? 1);
    final int number = _int(e['episode_num']);
    String ext = (_str(e['container_extension']) ?? 'mp4').trim();
    if (ext.isEmpty) ext = 'mp4';
    final dynamic epInfoRaw = e['info'];
    final Map<dynamic, dynamic> epInfo =
        epInfoRaw is Map ? epInfoRaw : const <dynamic, dynamic>{};
    int dur = _int(epInfo['duration_secs']);
    if (dur == 0) dur = _hmsToSeconds(_str(epInfo['duration']));
    eps.putIfAbsent(season, () => <CinemaEpisode>[]).add(CinemaEpisode(
          id: '${source.key}:e:$id',
          remoteId: id,
          seriesId: seriesId,
          season: season,
          number: number,
          title: cleanEpisodeTitle(_str(e['title']) ?? '', seriesName),
          streamUrl: source.episodeUrl(id, ext),
          containerExt: ext,
          plot: _text(epInfo['plot']),
          durationSec: dur,
          stillUrl: _url(epInfo['movie_image']),
        ));
  }

  final dynamic epRaw = decoded['episodes'];
  if (epRaw is Map) {
    epRaw.forEach((dynamic k, dynamic list) {
      final int? hint = int.tryParse(k.toString());
      if (list is List) {
        for (final dynamic e in list) {
          addEpisode(e, hint);
        }
      }
    });
  } else if (epRaw is List) {
    for (final dynamic list in epRaw) {
      if (list is List) {
        for (final dynamic e in list) {
          addEpisode(e, null);
        }
      } else {
        addEpisode(list, null);
      }
    }
  }
  for (final List<CinemaEpisode> l in eps.values) {
    l.sort((CinemaEpisode a, CinemaEpisode b) => a.number.compareTo(b.number));
  }

  // ----- Saisons : celles annoncées ET qui ont des épisodes -----
  final Map<int, CinemaSeason> declared = <int, CinemaSeason>{};
  final dynamic seasonsRaw = decoded['seasons'];
  if (seasonsRaw is List) {
    for (final dynamic s in seasonsRaw) {
      if (s is! Map) continue;
      final int n = _int(s['season_number']);
      declared[n] = CinemaSeason(
        number: n,
        name: (_str(s['name']) ?? '').trim(),
        coverUrl: _url(s['cover_big']) ?? _url(s['cover']),
        episodeCount: _int(s['episode_count']),
      );
    }
  }
  final List<int> numbers = eps.keys.toList()
    // Saison 0 (« Spéciaux ») rangée APRÈS les vraies saisons.
    ..sort((int a, int b) => (a == 0 ? 1 << 20 : a).compareTo(b == 0 ? 1 << 20 : b));
  final List<CinemaSeason> seasons = <CinemaSeason>[
    for (final int n in numbers)
      CinemaSeason(
        number: n,
        name: declared[n]?.name ?? '',
        coverUrl: declared[n]?.coverUrl,
        episodeCount: eps[n]!.length,
      ),
  ];
  return SeriesDetails(details: details, seasons: seasons, episodes: eps);
}

/// « Breaking Bad - S01E02 - Cat's in the Bag » → « Cat's in the Bag ».
/// Chaîne vide si le titre ne contient que le nom de série / le code SxxEyy
/// (l'écran affiche alors « Épisode N »).
String cleanEpisodeTitle(String raw, String seriesName) {
  String t = raw.trim();
  if (seriesName.isNotEmpty &&
      t.toLowerCase().startsWith(seriesName.toLowerCase())) {
    t = t.substring(seriesName.length);
  }
  t = t.replaceAll(RegExp(r'\bS\d{1,2}\s*[ .-]?\s*E\d{1,3}\b', caseSensitive: false), ' ');
  t = t.replaceAll(RegExp(r'^[\s\-–—:|.]+|[\s\-–—:|.]+$'), '');
  t = t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return t;
}

// ---------------------------------------------------------
//  Lecteurs tolérants (champ absent / texte / nombre / vide)
// ---------------------------------------------------------

String? _str(dynamic v) {
  if (v == null) return null;
  final String s = v.toString();
  return s.isEmpty ? null : s;
}

String? _text(dynamic v) {
  final String? s = _str(v)?.trim();
  if (s == null || s.isEmpty || s == 'null' || s == 'N/A') return null;
  return s;
}

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString().trim() ?? '') ?? 0;
}

String? _url(dynamic v) {
  final String? s = _str(v)?.trim();
  if (s == null || !(s.startsWith('http://') || s.startsWith('https://'))) {
    return null;
  }
  return s;
}

String? _firstUrl(dynamic v) {
  if (v is List) {
    for (final dynamic x in v) {
      final String? u = _url(x);
      if (u != null) return u;
    }
    return null;
  }
  return _url(v);
}

double? _rating(dynamic ten, dynamic five) {
  double? r = double.tryParse(ten?.toString().trim() ?? '');
  if (r == null || r <= 0) {
    final double? f = double.tryParse(five?.toString().trim() ?? '');
    if (f != null && f > 0) r = f * 2;
  }
  if (r == null || r <= 0) return null;
  return r > 10 ? 10 : r;
}

final RegExp _rxYear = RegExp(r'(?:^|[^0-9])((?:19|20)\d{2})(?:[^0-9]|$)');

String? _year(String? field, String name) {
  for (final String? s in <String?>[field, name]) {
    if (s == null) continue;
    final RegExpMatch? m = _rxYear.firstMatch(s);
    if (m != null) return m.group(1);
  }
  return null;
}

/// « 01:45:30 » / « 105 min » → secondes.
int _hmsToSeconds(String? s) {
  if (s == null) return 0;
  final List<String> parts = s.trim().split(':');
  if (parts.length == 3) {
    return (int.tryParse(parts[0]) ?? 0) * 3600 +
        (int.tryParse(parts[1]) ?? 0) * 60 +
        (int.tryParse(parts[2]) ?? 0);
  }
  if (parts.length == 2) {
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
  final RegExpMatch? m = RegExp(r'(\d+)\s*min').firstMatch(s);
  return m == null ? 0 : int.parse(m.group(1)!) * 60;
}
