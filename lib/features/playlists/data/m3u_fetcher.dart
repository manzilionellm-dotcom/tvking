// =========================================================
//  m3u_fetcher.dart — Téléchargement robuste de playlists
// =========================================================
//  Le `http.Response.body` standard décode TOUT en UTF-8.
//  Problème : ~30 % des serveurs IPTV servent du Latin-1 /
//  Windows-1252 (vieux backends PHP en Europe). Résultat sur
//  ces playlists : body vide ou caractères pétés (é → Ã©), le
//  parser ne trouve aucune chaîne → "playlist vide".
//
//  Ce helper :
//    1. Pose un User-Agent neutre (certains serveurs rejettent
//       le UA Dart par défaut)
//    2. Suit les redirects (jusqu'à 5)
//    3. Lit en bytes bruts puis tente UTF-8 → fallback Latin-1
//       (Latin-1 ne plante JAMAIS, juste mojibake si vraiment UTF-8)
//    4. Strip le BOM UTF-8 si présent
//    5. Timeout généreux (90 sec) pour les grosses playlists
// =========================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

abstract final class M3uFetcher {
  /// User-Agent qu'on présente aux serveurs M3U. Certains rejettent
  /// "Dart/3.x.x" ou "okhttp" — un UA "navigateur-like" est le plus
  /// permissif. Garder TV-friendly pour les serveurs paranoïaques
  /// qui filtrent par device.
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; SM-S938B) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36 7MOTION/1.0';

  static const Duration _timeout = Duration(seconds: 90);

  /// Télécharge l'URL fournie et renvoie le body décodé en String,
  /// prêt à passer à `M3uParser.parse(body, ...)`.
  ///
  /// Lance une [Exception] si HTTP != 200 ou si le download échoue.
  static Future<String> fetch(
    String url, {
    http.Client? httpClient,
  }) async {
    final http.Client client = httpClient ?? http.Client();
    final bool owns = httpClient == null;

    try {
      final http.Response resp = await client.get(
        Uri.parse(url),
        headers: <String, String>{
          'User-Agent': _userAgent,
          'Accept': '*/*',
          'Accept-Encoding': 'gzip, deflate',
        },
      ).timeout(_timeout);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode} sur $url');
      }

      return _decodeBody(resp);
    } finally {
      if (owns) client.close();
    }
  }

  /// Décodage UTF-8 → Latin-1 fallback + BOM strip.
  /// On travaille sur `bodyBytes` (jamais `body`) pour avoir le
  /// contrôle total de l'encoding.
  static String _decodeBody(http.Response resp) {
    final List<int> bytes = resp.bodyBytes;
    if (bytes.isEmpty) return '';

    // Strip BOM UTF-8 (EF BB BF) si présent
    final List<int> stripped =
        (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            ? bytes.sublist(3)
            : bytes;

    // Tente UTF-8 strict — c'est le format légal de M3U_PLUS.
    try {
      return utf8.decode(stripped, allowMalformed: false);
    } catch (_) {
      // Pas du UTF-8 valide → c'est probablement Latin-1 / Windows-1252.
      // Latin-1 ne lève jamais d'exception : chaque byte = un char.
      if (kDebugMode) {
        debugPrint(
          '[M3uFetcher] UTF-8 invalide, fallback Latin-1 pour $resp.bodyBytes.length bytes',
        );
      }
      return latin1.decode(stripped);
    }
  }
}
