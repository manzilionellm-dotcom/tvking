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
//    1. ESSAIE PLUSIEURS SIGNATURES DE LECTEUR (User-Agent) — voir plus
//       bas. Beaucoup de serveurs IPTV ne livrent la playlist QU'aux UA
//       de lecteurs qu'ils reconnaissent (VLC, IBO/ExoPlayer, Smarters,
//       TiviMate, Kodi…) et bloquent les autres avec une page web, une
//       réponse vide ou un code maison (ex. « HTTP 884 »). Plutôt que
//       d'exiger de l'utilisateur qu'il devine, on les essaie en
//       cascade jusqu'à obtenir une vraie playlist.
//    2. Suit les redirects (jusqu'à 5, géré par dart:io)
//    3. Lit en bytes bruts puis tente UTF-8 → fallback Latin-1
//       (Latin-1 ne plante JAMAIS, juste mojibake si vraiment UTF-8)
//    4. Strip le BOM UTF-8 si présent
//    5. Timeout généreux (90 sec) pour les grosses playlists
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../player/data/player_settings.dart';

abstract final class M3uFetcher {
  /// UA « navigateur » historique, gardé comme DERNIER recours dans la
  /// rotation. Certains serveurs préfèrent au contraire une signature
  /// navigateur — d'où sa présence dans la liste.
  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; SM-S938B) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36 7MOTION/1.0';

  static const Duration _timeout = Duration(seconds: 90);

  /// Construit la liste ORDONNÉE des signatures (User-Agent) à essayer,
  /// sans doublon. Ordre : d'abord la signature CONFIGURÉE par
  /// l'utilisateur (c'est elle qui débloque sa source en général), puis
  /// tous les présets de lecteurs connus (VLC, ExoPlayer/IBO, OkHttp,
  /// Smarters, TiviMate, Kodi, Lavf…), enfin notre UA navigateur.
  static List<String> _candidateUserAgents(String? preferred) {
    final List<String> list = <String>[];
    void add(String? ua) {
      if (ua == null) return;
      final String v = ua.trim();
      if (v.isEmpty || list.contains(v)) return;
      list.add(v);
    }

    add(preferred);
    add(PlayerSettings.instance.userAgent);
    for (final String v in PlayerSettings.userAgentPresets.values) {
      add(v);
    }
    add(_browserUserAgent);
    return list;
  }

  /// Télécharge l'URL fournie et renvoie le body décodé en String,
  /// prêt à passer à `M3uParser.parse(body, ...)`.
  ///
  /// Essaie successivement plusieurs signatures de lecteur (cf.
  /// [_candidateUserAgents]) ; renvoie le PREMIER corps qui ressemble à
  /// une vraie playlist. Si AUCUNE signature ne marche, lève une
  /// [Exception] avec un message explicite (dernière erreur rencontrée).
  ///
  /// [preferredUserAgent] : signature à tenter en premier (sinon on prend
  /// celle configurée dans les réglages lecteur).
  static Future<String> fetch(
    String url, {
    http.Client? httpClient,
    String? preferredUserAgent,
  }) async {
    final http.Client client = httpClient ?? http.Client();
    final bool owns = httpClient == null;

    try {
      final List<String> userAgents = _candidateUserAgents(preferredUserAgent);
      // Mémorise la dernière erreur la plus parlante pour le message final.
      Object? lastError;

      for (int i = 0; i < userAgents.length; i++) {
        final String ua = userAgents[i];
        try {
          final http.Response resp = await client.get(
            Uri.parse(url),
            headers: <String, String>{
              'User-Agent': ua,
              'Accept': '*/*',
              // NB : on ne force PAS d'en-tête Accept-Encoding. dart:io
              // ajoute « gzip » tout seul et décompresse automatiquement.
            },
          ).timeout(_timeout);

          if (resp.statusCode != 200) {
            // Serveur qui refuse cette signature (souvent 403 / 401 /
            // un code maison comme 884). On essaie la signature suivante.
            lastError = Exception('HTTP ${resp.statusCode} sur $url');
            continue;
          }

          final String body = _decodeBody(resp);
          final String head = body.trimLeft();
          if (head.isEmpty) {
            lastError =
                Exception('Le serveur a renvoyé une réponse vide pour $url');
            continue;
          }

          // Garde-fou « ce n'est pas un M3U » : beaucoup d'endpoints
          // (mauvaise URL, page de login, portail captif, signature
          // refusée renvoyant du HTML) répondent 200 avec du HTML ou du
          // JSON au lieu d'une playlist. Sans #EXTM3U/#EXTINF ni la
          // moindre URL de flux, on considère cette signature comme un
          // échec et on tente la suivante.
          final String headUpper = head.toUpperCase();
          final bool looksHtml = head.startsWith('<');
          final bool looksM3u = headUpper.contains('#EXTM3U') ||
              headUpper.contains('#EXTINF') ||
              head.contains('://');
          if (looksHtml && !looksM3u) {
            lastError = Exception(
              'Le serveur a renvoyé une page web (HTML), pas une playlist.',
            );
            continue;
          }
          if (!looksM3u) {
            // Ni balise M3U ni URL de flux : probablement une erreur
            // applicative en texte/JSON. On tente une autre signature.
            lastError = Exception(
              'Réponse sans aucune chaîne (ni #EXTM3U ni URL) pour $url',
            );
            continue;
          }

          // Succès : cette signature a livré une vraie playlist.
          if (kDebugMode && i > 0) {
            debugPrint(
              '[M3uFetcher] playlist obtenue avec la signature #${i + 1} '
              '« $ua » (les précédentes étaient bloquées).',
            );
          }
          return body;
        } on TimeoutException catch (e) {
          // Hôte trop lent / injoignable : ce n'est PAS un problème de
          // signature → inutile de retenter les autres UA (on cumulerait
          // des timeouts de 90 s). On s'arrête là.
          lastError = e;
          break;
        } on Exception catch (e) {
          // Connexion coupée / reset : peut dépendre de l'UA (certains
          // serveurs ferment la connexion selon la signature) → on tente
          // la signature suivante.
          lastError = e;
          continue;
        }
      }

      // Aucune signature n'a fonctionné → message clair.
      throw Exception(_friendlyFailure(lastError, url, userAgents.length));
    } finally {
      if (owns) client.close();
    }
  }

  /// Compose un message d'échec lisible après avoir épuisé toutes les
  /// signatures. On y mentionne qu'on a essayé plusieurs lecteurs pour
  /// que l'utilisateur comprenne que le souci vient du serveur (et non
  /// d'un simple « mauvais UA » réglable à la main).
  static String _friendlyFailure(Object? lastError, String url, int tried) {
    final String detail = lastError == null
        ? ''
        : '\n\nDernière réponse : '
            '${lastError.toString().replaceFirst('Exception: ', '')}';
    return 'Impossible de récupérer la playlist : le serveur a refusé les '
        '$tried signatures de lecteur testées (VLC, IBO/ExoPlayer, '
        'Smarters, TiviMate, Kodi…). Vérifie que l\'URL est correcte et '
        'que l\'abonnement est actif ; un lien « localhost » ne marche pas '
        'depuis cet appareil.$detail';
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
          '[M3uFetcher] UTF-8 invalide, fallback Latin-1 pour ${stripped.length} bytes',
        );
      }
      return latin1.decode(stripped);
    }
  }
}
