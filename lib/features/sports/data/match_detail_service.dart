// =========================================================
//  match_detail_service.dart — Va chercher la fiche d'un match
// =========================================================
//  Une requête vers le Worker (/api/sports/event/:id), qui mutualise les
//  quatre appels amont et garde un cache de 60 s. Ici : un petit cache
//  mémoire du même ordre, pour qu'un aller-retour entre deux onglets ne
//  refasse pas la requête, et un branchement remplaçable pour les tests.
//  Best-effort : sans réseau, `null` — l'écran dit « pas de données ».
// =========================================================
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../domain/match_detail.dart';

class MatchDetailService {
  MatchDetailService._();
  static final MatchDetailService instance = MatchDetailService._();

  static const Duration _ttl = Duration(seconds: 45);
  static const Duration _timeout = Duration(seconds: 10);

  final Map<String, ({DateTime at, MatchDetail detail})> _cache =
      <String, ({DateTime at, MatchDetail detail})>{};

  @visibleForTesting
  Future<Map<String, dynamic>?> Function(String id)? debugFetch;

  MatchDetail? cached(String id) => _cache[id]?.detail;

  Future<MatchDetail?> load(String id, {bool force = false}) async {
    if (id.isEmpty) return null;
    final ({DateTime at, MatchDetail detail})? c = _cache[id];
    if (!force && c != null && DateTime.now().difference(c.at) < _ttl) {
      return c.detail;
    }
    try {
      final Map<String, dynamic>? j = await _fetch(id);
      if (j == null) return c?.detail;
      final MatchDetail d = MatchDetail.fromJson(j);
      _cache[id] = (at: DateTime.now(), detail: d);
      return d;
    } catch (e) {
      if (kDebugMode) debugPrint('[Fiche] chargement KO: $e');
      return c?.detail;
    }
  }

  Future<Map<String, dynamic>?> _fetch(String id) async {
    final Future<Map<String, dynamic>?> Function(String)? o = debugFetch;
    if (o != null) return o(id);
    final http.Response r = await http
        .get(
          Uri.parse('$kSubscriptionBaseUrl/api/sports/event/'
              '${Uri.encodeComponent(id)}'),
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(_timeout);
    if (r.statusCode != 200) return null;
    final Object? decoded = jsonDecode(utf8.decode(r.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  @visibleForTesting
  void debugReset() => _cache.clear();
}
