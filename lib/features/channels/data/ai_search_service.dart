// =========================================================
//  ai_search_service.dart — Recherche en langage naturel (IA)
// =========================================================
//  « Trouve-moi un film d'action pour ce soir » → l'IA convertit la
//  phrase en FILTRE structuré, que l'app applique LOCALEMENT à son
//  catalogue.
//
//  Pourquoi ce découpage :
//    - L'IA ne reçoit jamais le catalogue (trop gros, et privé) — juste
//      la phrase. Elle renvoie un petit JSON {keywords, type, genres,
//      title_contains, language}. C'est rapide et peu coûteux.
//    - L'appel passe par NOTRE Worker (/api/ai/search), qui détient la
//      clé Anthropic en secret. L'app n'embarque aucune clé.
//    - Tant que la clé n'est pas configurée côté serveur, l'endpoint
//      répond 503 et `search()` renvoie null (l'app retombe sur la
//      recherche classique).
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../subscription/data/subscription_backend.dart';
import '../domain/channel.dart';

/// Filtre de recherche produit par l'IA. Immuable.
@immutable
class AiSearchFilter {
  const AiSearchFilter({
    required this.keywords,
    required this.type,
    required this.genres,
    required this.titleContains,
    required this.language,
  });

  final List<String> keywords;

  /// 'live' | 'movie' | 'series' | 'any'
  final String type;
  final List<String> genres;
  final String titleContains;
  final String language;

  factory AiSearchFilter.fromJson(Map<String, Object?> json) {
    List<String> strList(Object? v) => (v is List)
        ? v.whereType<String>().map((String s) => s.trim()).toList()
        : const <String>[];
    return AiSearchFilter(
      keywords: strList(json['keywords']),
      type: (json['type'] as String?)?.trim() ?? 'any',
      genres: strList(json['genres']),
      titleContains: (json['title_contains'] as String?)?.trim() ?? '',
      language: (json['language'] as String?)?.trim() ?? '',
    );
  }

  /// Tous les termes textuels à chercher dans le nom/catégorie d'une chaîne.
  List<String> get _terms {
    final List<String> t = <String>[
      ...keywords,
      ...genres,
      if (titleContains.isNotEmpty) titleContains,
      if (language.isNotEmpty) language,
    ];
    return t
        .map(_norm)
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  /// `true` si la chaîne correspond au filtre.
  bool matches(Channel c) {
    // 1) Contrainte de type (direct vs VOD).
    switch (type) {
      case 'live':
        if (!c.isLive) return false;
        break;
      case 'movie':
      case 'series':
        if (c.isLive) return false;
        break;
      default:
        break; // 'any' → pas de contrainte
    }
    // 2) Termes textuels. Si aucun terme (requête de type pur, ex.
    //    « montre-moi le direct »), on garde tout ce qui a passé le type.
    final List<String> terms = _terms;
    if (terms.isEmpty) return true;
    final String hay = _norm('${c.name} ${c.category}');
    for (final String term in terms) {
      if (hay.contains(term)) return true;
    }
    return false;
  }

  static String _norm(String s) {
    final String lower = s.toLowerCase();
    const Map<String, String> map = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    final StringBuffer b = StringBuffer();
    for (final int rune in lower.runes) {
      final String ch = String.fromCharCode(rune);
      b.write(map[ch] ?? ch);
    }
    return b.toString();
  }
}

abstract final class AiSearchService {
  /// Convertit `query` en filtre via le Worker. `null` si indisponible
  /// (IA non configurée, réseau, erreur) → l'app retombe sur la recherche
  /// classique.
  static Future<AiSearchFilter?> search(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return null;
    try {
      final http.Response resp = await http
          .post(
            Uri.parse('$kSubscriptionBaseUrl/api/ai/search'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, String>{'query': q}),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('[AiSearch] HTTP ${resp.statusCode}');
        return null;
      }
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final Object? filter = body['filter'];
      if (filter is! Map) return null;
      return AiSearchFilter.fromJson(Map<String, Object?>.from(filter));
    } catch (e) {
      if (kDebugMode) debugPrint('[AiSearch] error: $e');
      return null;
    }
  }
}
