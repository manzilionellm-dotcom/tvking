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
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/i18n/l10n_now.dart';
import '../../player/data/player_settings.dart';
import 'iptv_http.dart';
import 'playlist_import_limits.dart';
import 'source_link_utils.dart';

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
  /// [onBytes] : rappel de progression du téléchargement, appelé au fil
  /// des morceaux reçus avec (octetsReçus, tailleTotaleOuNull). La taille
  /// totale vaut `null` quand le serveur répond en « chunked » (fréquent
  /// en IPTV) — l'UI bascule alors sur un compteur d'octets animé.
  static Future<String> fetch(
    String url, {
    http.Client? httpClient,
    String? preferredUserAgent,
    void Function(int received, int? total)? onBytes,
  }) async {
    // Filet défensif : complète http:// si absent (le schéma est
    // normalement déjà garanti par l'appelant via `SourceLinkUtils`, cf.
    // `PlaylistRepository`). Sans ça, `Uri.parse` sur un lien sans schéma
    // échoue ou produit une URL invalide → « playlist injoignable » pour
    // un lien pourtant correct, juste incomplet.
    url = SourceLinkUtils.ensureScheme(url);
    // Client TOLÉRANT aux certificats invalides (auto-signés/expirés, très
    // courants sur les serveurs IPTV) — cf. iptv_http.dart. Sans ça, un
    // panel https « sécurisé maison » était rejeté avant même la requête.
    final http.Client client = httpClient ?? createIptvHttpClient();
    final bool owns = httpClient == null;

    try {
      final List<String> userAgents = _candidateUserAgents(preferredUserAgent);
      // Mémorise la dernière erreur la plus parlante pour le message final.
      Object? lastError;

      for (int i = 0; i < userAgents.length; i++) {
        final String ua = userAgents[i];
        try {
          // Requête STREAMÉE (pas client.get) pour lire le corps par morceaux
          // et COUPER au plafond mémoire — cf. _readCapped. En-têtes « complets »
          // façon navigateur : beaucoup de pare-feux anti-bot de fronts CDN
          // bloquent les requêtes « trop nues » (sans Accept-Language ni
          // Connection) avec un code maison (ex. « 884 »), MÊME avec un UA de
          // navigateur. NB : on ne force PAS d'Accept-Encoding (dart:io ajoute
          // « gzip » tout seul et décompresse automatiquement).
          final http.Request req = http.Request('GET', Uri.parse(url))
            ..followRedirects = true
            ..headers.addAll(<String, String>{
              'User-Agent': ua,
              'Accept': '*/*',
              'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7',
              'Connection': 'keep-alive',
            });
          final http.StreamedResponse resp =
              await client.send(req).timeout(_timeout);

          if (resp.statusCode != 200) {
            // Serveur qui refuse cette signature (souvent 403 / 401 /
            // un code maison comme 884). On essaie la signature suivante.
            lastError = Exception(l10nNow.m3uHttpError(resp.statusCode, url));
            continue;
          }

          // Lecture BORNÉE : on accumule les octets mais on COUPE le flux dès
          // kMaxM3uBytes → on ne charge JAMAIS une source géante d'un bloc en
          // RAM (cause racine OOM box faibles). Dépassement → PlaylistImportTooLarge.
          // On rapporte la progression au fil de l'eau (barre vivante).
          final int? total =
              (resp.contentLength != null && resp.contentLength! > 0)
                  ? resp.contentLength
                  : null;
          final Uint8List bytes =
              await _readCapped(resp.stream, kMaxM3uBytes, onBytes, total)
                  .timeout(_timeout);
          final String body = await _decodeBytesInBackground(bytes);
          final String head = body.trimLeft();
          if (head.isEmpty) {
            lastError = Exception(l10nNow.m3uEmptyResponse(url));
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
              head.contains('://') ||
              // Même repli que M3uParser._looksLikeUrl : playlist « brute »
              // de chemins SANS schéma mais avec extension média connue —
              // le parseur l'accepte, le fetcher ne doit pas la refuser.
              _hasMediaExtension(head);
          if (looksHtml && !looksM3u) {
            lastError = Exception(l10nNow.m3uHtmlResponse);
            continue;
          }
          if (!looksM3u) {
            // Ni balise M3U ni URL de flux : probablement une erreur
            // applicative en texte/JSON. On tente une autre signature.
            lastError = Exception(l10nNow.m3uNoChannelResponse(url));
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
        } on PlaylistImportTooLarge {
          // Source trop volumineuse : la taille ne dépend PAS de la signature
          // → inutile de retenter d'autres UA. On remonte l'erreur claire à l'UI.
          rethrow;
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
      throw Exception(friendlyFailure(lastError, url, userAgents.length));
    } finally {
      if (owns) client.close();
    }
  }

  /// Compose un message d'échec lisible après avoir épuisé toutes les
  /// signatures. On y mentionne qu'on a essayé plusieurs lecteurs pour
  /// que l'utilisateur comprenne que le souci vient du serveur (et non
  /// d'un simple « mauvais UA » réglable à la main).
  /// Public + visibleForTesting : le choix du message (DNS vs refus
  /// serveur) est testé sans réseau.
  @visibleForTesting
  static String friendlyFailure(Object? lastError, String url, int tried) {
    final String detail = lastError == null
        ? ''
        : '\n\nDernière réponse : '
            '${lastError.toString().replaceFirst('Exception: ', '')}';
    // ÉCHEC DNS (terrain 2026-07-08 : « Failed host lookup » sur un
    // domaine qui résout parfaitement depuis l'extérieur) : ce n'est ni
    // l'URL ni l'abonnement — c'est le RÉSEAU de l'appareil qui ne
    // résout pas le domaine (blocage DNS opérateur, très courant sur
    // l'IPTV, ou domaine réellement mort). Le message générique
    // « vérifie l'URL » envoyait l'utilisateur sur une fausse piste.
    final String s = lastError?.toString().toLowerCase() ?? '';
    final bool dnsFailure = s.contains('host lookup') ||
        s.contains('no address associated') ||
        s.contains('name or service not known') ||
        s.contains('nodename nor servname');
    if (dnsFailure) {
      return 'Le domaine de cette source est introuvable depuis ton réseau '
          '(résolution DNS impossible). Si cette source marche ailleurs, '
          'ton opérateur bloque probablement ce domaine : essaie en Wi-Fi, '
          'avec un DNS privé (Réglages Android → Réseau → DNS privé → '
          'dns.google) ou un VPN. Sinon, demande un nouveau lien à ton '
          'revendeur.$detail';
    }
    return 'Impossible de récupérer la playlist : le serveur a refusé les '
        '$tried signatures de lecteur testées (VLC, IBO/ExoPlayer, '
        'Smarters, TiviMate, Kodi…). Vérifie que l\'URL est correcte et '
        'que l\'abonnement est actif ; un lien « localhost » ne marche pas '
        'depuis cet appareil.$detail';
  }

  /// Repli du test « ça ressemble à un M3U » : une extension média connue
  /// dans les premiers Ko suffit (aligné sur M3uParser._looksLikeUrl).
  /// On ne balaie que le DÉBUT du corps (le corps peut faire 60 Mo).
  static bool _hasMediaExtension(String body) {
    final String sample =
        (body.length > 8192 ? body.substring(0, 8192) : body).toLowerCase();
    const List<String> mediaExt = <String>[
      '.m3u8', '.ts', '.mp4', '.mkv', '.mpd', '.flv', '.avi', '.mov',
      '.webm', '.m4v', '.aac', '.mp3',
    ];
    for (final String ext in mediaExt) {
      if (sample.contains(ext)) return true;
    }
    return false;
  }

  /// Lit [stream] en accumulant les octets, mais COUPE à [maxBytes] : au-delà,
  /// on lève [PlaylistImportTooLarge] (le `for await` s'arrête, l'abonnement est
  /// annulé) → on ne matérialise JAMAIS une source géante d'un bloc. Anti-OOM.
  static Future<Uint8List> _readCapped(
    Stream<List<int>> stream,
    int maxBytes, [
    void Function(int received, int? total)? onBytes,
    int? totalBytes,
  ]) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    int total = 0;
    await for (final List<int> chunk in stream) {
      total += chunk.length;
      if (total > maxBytes) {
        throw PlaylistImportTooLarge(
          l10nNow.m3uTooLarge(maxBytes ~/ (1024 * 1024)),
        );
      }
      builder.add(chunk);
      onBytes?.call(total, totalBytes);
    }
    return builder.takeBytes();
  }

  /// Décodage octets → String HORS du fil d'affichage. Une playlist pèse
  /// jusqu'à [kMaxM3uBytes] (60 Mo) : le `utf8.decode` d'un bloc pareil sur
  /// le main isolate gelait l'UI 200 ms-1 s (le DOUBLE en cas de repli
  /// Latin-1, qui re-décode tout). Les octets partent en O(1) via
  /// [TransferableTypedData] ; la String revient sans copie (Isolate.exit).
  /// Petits corps : décodage inline — l'isolate coûterait plus qu'il ne rend.
  static Future<String> _decodeBytesInBackground(Uint8List bytes) {
    const int inlineMax = 256 * 1024; // 256 Ko ≈ < 5 ms de décodage
    if (bytes.length <= inlineMax) {
      return Future<String>.value(_m3uDecodeEntry(bytes));
    }
    return compute(
      _m3uDecodeTransferableEntry,
      TransferableTypedData.fromList(<Uint8List>[bytes]),
    );
  }
}

/// Entrée isolate du décodage (top-level = requis par `compute`).
String _m3uDecodeTransferableEntry(TransferableTypedData data) =>
    _m3uDecodeEntry(data.materialize().asUint8List());

/// Décodage UTF-8 → Latin-1 fallback + BOM strip.
/// On travaille sur les octets bruts (jamais `body`) pour avoir le
/// contrôle total de l'encoding.
String _m3uDecodeEntry(Uint8List bytes) {
  if (bytes.isEmpty) return '';

  // Strip BOM UTF-8 (EF BB BF) si présent
  final Uint8List stripped =
      (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
          ? Uint8List.sublistView(bytes, 3)
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
