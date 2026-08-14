// ============================================================================
//  TmdbMetaService — métadonnées riches TMDb (Vague 2.3), via NOTRE backend.
//
//  L'app n'appelle JAMAIS TMDb directement : elle passe par le Worker
//  (`GET /api/tmdb/movie?q=&year=&lang=`), qui garde la clé API en SECRET
//  serveur et met en cache 24 h. Tant que le secret `TMDB_API_KEY` n'est
//  pas posé sur le Worker, la route répond { found:false } et l'app
//  n'affiche simplement RIEN de plus — absence gracieuse, zéro régression.
//
//  Usage : COMPLÉMENT du panel. `get_vod_info` du panel reste la source
//  n°1 ; TMDb ne comble que les trous (synopsis vide, casting absent,
//  note manquante) — jamais il n'écrase une donnée existante.
// ============================================================================

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;

class TmdbMeta {
  const TmdbMeta({
    this.rating,
    this.overview,
    this.cast,
    this.genres,
    this.year,
    this.runtimeMin,
    this.posterUrl,
    this.backdropUrl,
  });

  final String? rating; // « 7.8 »
  final String? overview;
  final String? cast; // « A, B, C » (même forme que VodInfo.cast)
  final String? genres; // « Action, Drame »
  final String? year;
  final int? runtimeMin;
  final String? posterUrl;
  final String? backdropUrl;
}

class TmdbMetaService {
  TmdbMetaService._();

  static final TmdbMetaService instance = TmdbMetaService._();

  static const Duration _timeout = Duration(seconds: 8);

  // Cache mémoire de session : une fiche ouverte deux fois ne re-frappe
  // pas le réseau (le Worker cache déjà 24 h côté edge).
  final Map<String, TmdbMeta?> _cache = <String, TmdbMeta?>{};

  /// Cherche le film par TITRE (déjà curé de préférence) et année
  /// éventuelle. Retourne null si inconnu / clé absente / réseau KO.
  Future<TmdbMeta?> fetchMovie(String title, {String? year, String? lang}) async {
    final String q = title.trim();
    if (q.length < 2) return null;
    final String key = '${lang ?? ''}|${year ?? ''}|${q.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key];
    TmdbMeta? meta;
    try {
      final Uri uri = Uri.parse(
          '$kSubscriptionBaseUrl/api/tmdb/movie?q=${Uri.encodeQueryComponent(q)}'
          '${year != null && year.isNotEmpty ? '&year=$year' : ''}'
          '${lang != null && lang.isNotEmpty ? '&lang=$lang' : ''}');
      final http.Response resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode == 200) {
        final dynamic j = jsonDecode(utf8.decode(resp.bodyBytes));
        if (j is Map<String, dynamic> && j['found'] == true) {
          final List<dynamic> castRaw =
              j['cast'] is List ? j['cast'] as List<dynamic> : const <dynamic>[];
          final List<dynamic> genresRaw = j['genres'] is List
              ? j['genres'] as List<dynamic>
              : const <dynamic>[];
          final num? rating = j['rating'] is num ? j['rating'] as num : null;
          meta = TmdbMeta(
            rating: rating != null && rating > 0 ? rating.toString() : null,
            overview: (j['overview']?.toString() ?? '').trim().isEmpty
                ? null
                : j['overview'].toString().trim(),
            cast: castRaw.isEmpty ? null : castRaw.join(', '),
            genres: genresRaw.isEmpty ? null : genresRaw.join(', '),
            year: (j['year']?.toString() ?? '').trim().isEmpty
                ? null
                : j['year'].toString().trim(),
            runtimeMin: j['runtimeMin'] is int ? j['runtimeMin'] as int : null,
            posterUrl: (j['posterUrl']?.toString() ?? '').trim().isEmpty
                ? null
                : j['posterUrl'].toString().trim(),
            backdropUrl: (j['backdropUrl']?.toString() ?? '').trim().isEmpty
                ? null
                : j['backdropUrl'].toString().trim(),
          );
        }
      }
    } catch (_) {
      // Silencieux : la fiche s'affiche sans enrichissement.
    }
    _cache[key] = meta;
    return meta;
  }
}
