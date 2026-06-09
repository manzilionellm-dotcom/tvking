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

import '../../../core/net/native_http.dart';
import '../../../core/observability/structured_logger.dart';
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

  /// Budget GLOBAL pour l'ensemble de la rotation de signatures. Garde-fou
  /// contre l'empilement de N tentatives lentes (consigne : « ne PAS
  /// cumuler N×90s si l'hôte est injoignable »). Si on dépasse ce budget,
  /// on arrête d'essayer de nouvelles signatures et on renvoie l'erreur.
  static const Duration _totalBudget = Duration(seconds: 150);

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

      // ----- PHASE NATIVE (pile TLS SYSTÈME) — correctif « 884 » -----
      // On tente d'ABORD le pont natif HttpURLConnection : sa pile TLS est
      // celle du système Android (comme le navigateur / IBO), donc les
      // fronts anti-bot qui rejettent l'empreinte TLS de dart:io la
      // laissent passer. S'il est indisponible (iOS, vieil APK) ou échoue,
      // on retombe sur la pile dart:io ci-dessous → aucune régression.
      final String? nativeBody = await _fetchViaNative(url, userAgents);
      if (nativeBody != null) return nativeBody;

      // Mémorise la dernière erreur la plus parlante pour le message final.
      Object? lastError;
      // Chronomètre global pour le garde-fou de budget (cf. _totalBudget).
      final Stopwatch elapsed = Stopwatch()..start();

      for (int i = 0; i < userAgents.length; i++) {
        // Garde-fou budget global : on n'enchaîne pas indéfiniment des
        // tentatives lentes si l'hôte traîne (évite N×90s cumulés).
        if (elapsed.elapsed > _totalBudget) {
          lastError ??= Exception('Délai global dépassé ($url)');
          break;
        }
        final String ua = userAgents[i];
        try {
          // En-têtes « complets » façon navigateur. Beaucoup de pare-feux
          // anti-bot de fronts CDN bloquent les requêtes « trop nues »
          // (sans Accept-Language ni Connection) avec un code maison
          // (ex. « 884 »), MÊME avec un User-Agent de navigateur.
          final Map<String, String> headers = <String, String>{
            'User-Agent': ua,
            'Accept': '*/*',
            'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
            'Connection': 'keep-alive',
            // NB : on ne force PAS d'en-tête Accept-Encoding. dart:io
            // ajoute « gzip » tout seul et décompresse automatiquement.
          };

          // PREUVE / DIAGNOSTIC 884 : on journalise la requête EXACTE
          // envoyée (URL + en-têtes + n° de signature). C'est cette trace
          // qu'on compare à la capture d'une requête qui MARCHE (navigateur
          // / IBO Player) pour isoler l'élément discriminant. Voir
          // docs/DIAGNOSTIC_HTTP_884.md. (En release, le sink par défaut du
          // logger est silencieux ; brancher un sink pour capturer.)
          StructuredLogger.instance.info(
            domain: 'net',
            event: 'm3u.request',
            ctx: <String, Object?>{
              'url': url,
              'uaIndex': i + 1,
              'ua': ua,
              'headers': headers,
            },
          );

          final http.Response resp = await client
              .get(Uri.parse(url), headers: headers)
              .timeout(_timeout);

          // Trace de la réponse reçue (statut + taille + content-type) :
          // l'autre moitié de la preuve (« ce que le serveur nous renvoie »,
          // ex. le fameux 884).
          StructuredLogger.instance.info(
            domain: 'net',
            event: 'm3u.response',
            ctx: <String, Object?>{
              'uaIndex': i + 1,
              'status': resp.statusCode,
              'bytes': resp.bodyBytes.length,
              'contentType': resp.headers['content-type'],
            },
          );

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

  /// Tente le téléchargement via le PONT NATIF (pile TLS système Android),
  /// en réutilisant la même rotation de signatures. Renvoie le corps de la
  /// 1ʳᵉ playlist valide, ou `null` si le pont est indisponible / si aucune
  /// signature n'aboutit (→ l'appelant retombe sur dart:io).
  static Future<String?> _fetchViaNative(
    String url,
    List<String> userAgents,
  ) async {
    if (!NativeHttp.isAvailable) return null;
    final Stopwatch elapsed = Stopwatch()..start();
    for (int i = 0; i < userAgents.length; i++) {
      if (elapsed.elapsed > _totalBudget) break;
      final String ua = userAgents[i];
      final Map<String, String> headers = <String, String>{
        'User-Agent': ua,
        'Accept': '*/*',
        'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
        'Connection': 'keep-alive',
      };
      StructuredLogger.instance.info(
        domain: 'net',
        event: 'm3u.request.native',
        ctx: <String, Object?>{
          'url': url,
          'uaIndex': i + 1,
          'ua': ua,
          'headers': headers,
        },
      );
      final NativeHttpResponse? resp =
          await NativeHttp.get(url, headers: headers);
      // Pont indisponible / erreur réseau native → on abandonne la phase
      // native et on laisse dart:io tenter sa chance.
      if (resp == null) return null;
      StructuredLogger.instance.info(
        domain: 'net',
        event: 'm3u.response.native',
        ctx: <String, Object?>{
          'uaIndex': i + 1,
          'status': resp.statusCode,
          'bytes': resp.bodyBytes.length,
          'contentType': resp.contentType,
        },
      );
      if (resp.statusCode != 200) continue;
      final String body = _decodeBytes(resp.bodyBytes);
      if (!_looksLikePlaylist(body)) continue;
      if (kDebugMode) {
        debugPrint(
          '[M3uFetcher] playlist obtenue via le pont NATIF (signature '
          '#${i + 1}) — empreinte TLS système, le « 884 » est contourné.',
        );
      }
      return body;
    }
    return null;
  }

  /// `true` si [body] ressemble à une vraie playlist M3U (et pas à une
  /// page HTML d'erreur ni à un JSON applicatif). Mutualisé entre la phase
  /// native et la phase dart:io.
  static bool _looksLikePlaylist(String body) {
    final String head = body.trimLeft();
    if (head.isEmpty) return false;
    final String headUpper = head.toUpperCase();
    final bool looksHtml = head.startsWith('<');
    final bool looksM3u = headUpper.contains('#EXTM3U') ||
        headUpper.contains('#EXTINF') ||
        head.contains('://');
    if (looksHtml && !looksM3u) return false;
    return looksM3u;
  }

  /// Décodage UTF-8 → Latin-1 fallback + BOM strip.
  /// On travaille sur les `bodyBytes` (jamais `body`) pour avoir le
  /// contrôle total de l'encoding.
  static String _decodeBody(http.Response resp) => _decodeBytes(resp.bodyBytes);

  static String _decodeBytes(List<int> bytes) {
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
