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
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../player/data/player_settings.dart';
import '../../../core/app/repair_flags.dart';
import '../../../core/blackbox/black_box.dart';
import 'm3u_parser.dart' show M3uParser;
import 'import_progress.dart';
import 'playlist_import_limits.dart';

abstract final class M3uFetcher {
  /// UA « navigateur » historique, gardé comme DERNIER recours dans la
  /// rotation. Certains serveurs préfèrent au contraire une signature
  /// navigateur — d'où sa présence dans la liste.
  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; SM-S938B) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36 7MOTION/1.0';

  /// Ancien délai unique (builds ≤ 107-test.159) : 90 s pour les en-têtes
  /// ET 90 s pour tout le corps. Mesuré le 05/10/2026 sur la box de test :
  /// « liste M3U du panel refusée après 90,0 s : Impossible de récupérer la
  /// playlist » — le fournisseur (derrière Cloudflare) met plus de 90 s à
  /// générer la liste, ou le corps (plusieurs Mo) ne finit pas en 90 s sur
  /// le Wi-Fi de la box. Repli : `zuno.m3u.timeout_legacy`.
  static const Duration legacyTimeout = Duration(seconds: 90);

  /// En-têtes : 120 s. Cloudflare coupe lui-même une origine muette à
  /// ~100 s, donc attendre plus n'apporte rien.
  static const Duration headersTimeout = Duration(seconds: 120);

  /// Corps : on ne mesure plus la durée totale mais le SILENCE. Tant que
  /// des octets arrivent, on continue ; 60 s sans rien = serveur parti.
  static const Duration idleTimeout = Duration(seconds: 60);

  /// Plafond absolu du corps, pour ne jamais rester bloqué sur un flux
  /// qui goutte à l'infini.
  static const Duration totalTimeout = Duration(minutes: 10);

  /// Délais effectifs. Pur, testé : `legacy` = ancien comportement.
  static FetchTimeouts fetchTimeouts({required bool legacy}) {
    if (legacy) {
      return const FetchTimeouts(
        headers: legacyTimeout,
        idle: legacyTimeout,
        total: legacyTimeout,
      );
    }
    return const FetchTimeouts(
      headers: headersTimeout,
      idle: idleTimeout,
      total: totalTimeout,
    );
  }

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
    final Uint8List bytes = await fetchBytes(
      url,
      httpClient: httpClient,
      preferredUserAgent: preferredUserAgent,
    );
    return M3uParser.decodeBytes(bytes);
  }

  /// Comme [fetch] mais renvoie les OCTETS bruts, sans décodage : à passer à
  /// `M3uParser.parseBytesInBackground` pour que décodage + parsing se fassent
  /// dans l'isolate (le fil UI ne manipule jamais le contenu). Le « sniff »
  /// anti-HTML se fait sur les premiers Ko seulement.
  static Future<Uint8List> fetchBytes(
    String url, {
    http.Client? httpClient,
    String? preferredUserAgent,
    FetchTimeouts? timeouts,
  }) async {
    final http.Client client = httpClient ?? http.Client();
    final bool owns = httpClient == null;
    final String host = Uri.tryParse(url)?.host ?? '?';
    final FetchTimeouts t =
        timeouts ?? fetchTimeouts(legacy: RepairFlags.m3uTimeoutLegacy);
    BlackBox.instance.breadcrumb('Téléchargement M3U $host');
    ImportProgressBus.connecting();

    try {
      final List<String> userAgents = _candidateUserAgents(preferredUserAgent);
      // Mémorise la dernière erreur la plus parlante pour le message final.
      Object? lastError;

      for (int i = 0; i < userAgents.length; i++) {
        final String ua = userAgents[i];
        // Où en était-on quand le délai a été dépassé ? Pour la boîte
        // noire : « en-têtes » (le serveur n'a rien dit) ou « corps,
        // N octets » (il a commencé puis s'est tu).
        bool headersSeen = false;
        int received = 0;
        final Stopwatch sw = Stopwatch()..start();
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
              await client.send(req).timeout(t.headers);
          headersSeen = true;

          if (resp.statusCode != 200) {
            // Serveur qui refuse cette signature (souvent 403 / 401 /
            // un code maison comme 884). On essaie la signature suivante.
            lastError = Exception('HTTP ${resp.statusCode} sur $url');
            continue;
          }

          // Lecture BORNÉE : on accumule les octets mais on COUPE le flux dès
          // kMaxM3uBytes → on ne charge JAMAIS une source géante d'un bloc en
          // RAM (cause racine OOM box faibles). Dépassement → PlaylistImportTooLarge.
          final Uint8List bytes = await _readCapped(
            resp.stream,
            kMaxM3uBytes,
            idle: t.idle,
            onBytes: (int n) => received = n,
          ).timeout(t.total);
          // Sniff sur les 64 premiers Ko (Latin-1 : ne lève jamais) — assez
          // pour voir #EXTM3U / #EXTINF / une URL, sans décoder 60 Mo ici.
          final int sniffLen = bytes.length < 65536 ? bytes.length : 65536;
          final String head =
              latin1.decode(Uint8List.sublistView(bytes, 0, sniffLen)).trimLeft();
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
          BlackBox.instance.info('M3U', '$host : ${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} Mo reçus');
          if (kDebugMode && i > 0) {
            debugPrint(
              '[M3uFetcher] playlist obtenue avec la signature #${i + 1} '
              '« $ua » (les précédentes étaient bloquées).',
            );
          }
          return bytes;
        } on PlaylistImportTooLarge {
          // Source trop volumineuse : la taille ne dépend PAS de la signature
          // → inutile de retenter d'autres UA. On remonte l'erreur claire à l'UI.
          rethrow;
        } on TimeoutException {
          // Hôte trop lent / injoignable : ce n'est PAS un problème de
          // signature → inutile de retenter les autres UA (on cumulerait
          // des délais). On s'arrête là, en disant OÙ ça a coincé.
          final String phase = headersSeen
              ? 'corps, ${(received / (1024 * 1024)).toStringAsFixed(1)} Mo reçus'
              : 'aucune réponse du serveur (en-têtes)';
          BlackBox.instance.warn(
            'M3U',
            '$host : délai dépassé après ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(0)} s ($phase)',
          );
          lastError = Exception(
            headersSeen
                ? 'Le serveur a commencé à envoyer la liste puis s\'est tu '
                    '(${(received / (1024 * 1024)).toStringAsFixed(1)} Mo reçus).'
                : 'Le serveur n\'a pas répondu en ${t.headers.inSeconds} s.',
          );
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

  /// Lit [stream] en accumulant les octets, mais COUPE à [maxBytes] : au-delà,
  /// on lève [PlaylistImportTooLarge] (le `for await` s'arrête, l'abonnement est
  /// annulé) → on ne matérialise JAMAIS une source géante d'un bloc. Anti-OOM.
  /// [idle] : silence maximal entre deux paquets (le serveur a commencé
  /// puis s'est tu). [onBytes] : total reçu, pour la boîte noire.
  static Future<Uint8List> _readCapped(
    Stream<List<int>> stream,
    int maxBytes, {
    Duration? idle,
    void Function(int received)? onBytes,
  }) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    int total = 0;
    final Stream<List<int>> guarded = idle == null
        ? stream
        : stream.timeout(
            idle,
            onTimeout: (EventSink<List<int>> sink) {
              sink.addError(TimeoutException(
                'aucune donnée depuis ${idle.inSeconds} s',
                idle,
              ));
              sink.close();
            },
          );
    await for (final List<int> chunk in guarded) {
      total += chunk.length;
      onBytes?.call(total);
      ImportProgressBus.downloading(total);
      if (total > maxBytes) {
        throw PlaylistImportTooLarge(
          'Playlist trop volumineuse (> ${maxBytes ~/ (1024 * 1024)} Mo). '
          'Réduis la source ou filtre les catégories côté fournisseur.',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

}

/// Trois délais d'un téléchargement M3U (voir [M3uFetcher.fetchTimeouts]).
@immutable
class FetchTimeouts {
  const FetchTimeouts({
    required this.headers,
    required this.idle,
    required this.total,
  });

  /// Attente de la première réponse du serveur (en-têtes).
  final Duration headers;

  /// Silence maximal entre deux paquets du corps.
  final Duration idle;

  /// Durée maximale du corps, tout compris.
  final Duration total;
}
