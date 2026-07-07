// =========================================================
//  playlist_health_checker.dart — Ping des serveurs IPTV
// =========================================================
//  Phase 1+/Multi-serveurs (2026-06-01) : pour aider l'utilisateur a
//  choisir entre N playlists, on ping chaque serveur et on classifie
//  sa sante. L'UI affiche un badge couleur (vert / orange / rouge /
//  gris) a cote de chaque playlist dans Reglages > Playlists.
//
//  IMPORTANT : on N'utilise PAS le resultat pour basculer
//  automatiquement entre playlists (decision produit explicite — cf.
//  reponse user 2026-06-01 : auto-detect cree du yo-yo qui pourrit
//  l'experience). Le user clique manuellement "Definir actif" en
//  voyant le badge. Auto-switch silencieux explicitement ecarte.
//
//  Protocole de check :
//    - M3U     : GET HEAD ou GET Range:0-1023 sur l'URL .m3u
//    - Xtream  : GET `${server}/player_api.php?user=X&pass=Y`
//                (= la requete d'auth, deja toleree par tous les
//                providers Xtream Codes).
//
//  Classification :
//    ok        : HTTP 200 + body non-vide (m3u) ou JSON valide (xtream)
//    saturated : HTTP 458/429/503 (provider limite ou surcharge)
//    auth     : HTTP 401/403 (credentials expires)
//    slow      : 200 mais TTFB > 6s
//    down      : timeout / DNS fail / connexion refusee
//    unknown   : code HTTP inconnu (autres 4xx/5xx hors les listes)
//
//  Cache : on memorise le dernier resultat par playlist.id pendant
//  [_kHealthCacheTtl] (5 min). Evite de marteler les serveurs IPTV
//  sur des refresh repetes de l'ecran Playlists. Le user peut forcer
//  un re-check via le bouton "Re-tester" (skip cache).
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/observability/structured_logger.dart';
import '../domain/playlist.dart';
import 'source_link_utils.dart';

/// Statut sante d'une playlist. Stable — les .name sont serialises
/// dans les logs structures.
enum PlaylistHealthStatus {
  /// Le serveur repond OK, contenu attendu reçu.
  ok,

  /// Le serveur dit "trop de connexions" (HTTP 458, 429, 503). Le
  /// user doit fermer une autre app qui consomme un slot.
  saturated,

  /// Credentials refuses (401, 403). Probablement abonnement expire.
  auth,

  /// 200 OK mais lent (TTFB > 6s). Cast et streaming risquent de
  /// timeout sur cette source.
  slow,

  /// Le serveur ne repond pas du tout : timeout, DNS fail, conn refused.
  down,

  /// Une autre erreur (4xx / 5xx hors les listes connues).
  unknown,

  /// Pas encore teste (etat initial avant le 1er ping).
  notChecked,
}

/// Resultat detaille d'un check, prevu pour etre attache a une
/// Playlist en RAM dans l'UI (pas persiste cote SQLite).
@immutable
class PlaylistHealth {
  const PlaylistHealth({
    required this.status,
    required this.checkedAt,
    this.httpCode,
    this.ttfbMs,
    this.errorReason,
  });

  final PlaylistHealthStatus status;
  final DateTime checkedAt;
  final int? httpCode;
  final int? ttfbMs;
  final String? errorReason;

  /// Pre-instance "jamais teste" — utile pour seed l'UI au boot
  /// avant le 1er check.
  static PlaylistHealth notChecked = PlaylistHealth(
    status: PlaylistHealthStatus.notChecked,
    checkedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Libelle court francais pour l'UI (badge texte).
  String get label {
    switch (status) {
      case PlaylistHealthStatus.ok:
        return 'En ligne';
      case PlaylistHealthStatus.saturated:
        return 'Saturé';
      case PlaylistHealthStatus.auth:
        return 'Auth refusée';
      case PlaylistHealthStatus.slow:
        return 'Lent';
      case PlaylistHealthStatus.down:
        return 'Hors ligne';
      case PlaylistHealthStatus.unknown:
        return 'Statut inconnu';
      case PlaylistHealthStatus.notChecked:
        return 'À tester';
    }
  }

  /// Description detaillee pour le tooltip ou les logs.
  String get detail {
    final StringBuffer sb = StringBuffer(label);
    if (httpCode != null) sb.write(' (HTTP $httpCode)');
    if (ttfbMs != null) sb.write(' · ${ttfbMs}ms');
    if (errorReason != null) sb.write(' · $errorReason');
    return sb.toString();
  }
}

/// TTL du cache : on memorise un check pendant 5 min pour ne pas
/// marteler les serveurs IPTV (qui peuvent rate-limit les health checks).
const Duration _kHealthCacheTtl = Duration(minutes: 5);

/// Timeout par requete. 6s = compromis : assez pour les providers
/// lents legitimes (FAI grand public en Europe : 1-3s TTFB normal),
/// assez court pour ne pas geler l'UI.
const Duration _kHealthCheckTimeout = Duration(seconds: 6);

class PlaylistHealthChecker {
  PlaylistHealthChecker._();
  static final PlaylistHealthChecker instance = PlaylistHealthChecker._();

  /// Cache `{playlist.id -> PlaylistHealth}`. Vide au boot, rempli
  /// au fur et a mesure des checks.
  final Map<int, PlaylistHealth> _cache = <int, PlaylistHealth>{};

  /// Acces direct au dernier resultat connu (cache RAM). Renvoie
  /// [PlaylistHealth.notChecked] si jamais teste. Utile pour l'UI
  /// qui veut afficher quelque chose immediatement sans attendre.
  PlaylistHealth peekCached(int playlistId) {
    return _cache[playlistId] ?? PlaylistHealth.notChecked;
  }

  /// Lance un check sante. Si [forceFresh] est false (defaut) et
  /// qu'on a un resultat recent (< 5 min) en cache, on le renvoie
  /// sans hit reseau.
  Future<PlaylistHealth> check(
    Playlist playlist, {
    bool forceFresh = false,
  }) async {
    final int? id = playlist.id;
    if (id == null) {
      // Playlist pas encore en base — pas de check raisonnable.
      return PlaylistHealth.notChecked;
    }
    if (!forceFresh) {
      final PlaylistHealth? cached = _cache[id];
      if (cached != null && cached.status != PlaylistHealthStatus.notChecked) {
        final Duration age = DateTime.now().difference(cached.checkedAt);
        if (age < _kHealthCacheTtl) {
          return cached;
        }
      }
    }
    final PlaylistHealth result = await _runCheck(playlist);
    _cache[id] = result;
    StructuredLogger.instance.info(
      domain: 'playlists',
      event: 'health.checked',
      ctx: <String, Object?>{
        'playlistId': id,
        'type': playlist.type.name,
        'status': result.status.name,
        if (result.httpCode != null) 'httpCode': result.httpCode,
        if (result.ttfbMs != null) 'ttfbMs': result.ttfbMs,
      },
    );
    return result;
  }

  /// Vide le cache — utile pour les tests et pour le bouton
  /// "Re-tester tout" si on l'ajoute un jour.
  @visibleForTesting
  void clearCache() => _cache.clear();

  /// Permet aux tests d'injecter une valeur en cache directement.
  @visibleForTesting
  void primeCache(int playlistId, PlaylistHealth health) {
    _cache[playlistId] = health;
  }

  // ============================================================
  //  Implementations par type de playlist
  // ============================================================

  Future<PlaylistHealth> _runCheck(Playlist playlist) async {
    switch (playlist.type) {
      case PlaylistType.m3u:
        if (playlist.m3uUrl == null || playlist.m3uUrl!.isEmpty) {
          return PlaylistHealth(
            status: PlaylistHealthStatus.down,
            checkedAt: DateTime.now(),
            errorReason: 'URL M3U manquante',
          );
        }
        return _checkM3u(playlist.m3uUrl!);
      case PlaylistType.xtream:
        if (playlist.xtreamServer == null ||
            playlist.xtreamUsername == null ||
            playlist.xtreamPassword == null) {
          return PlaylistHealth(
            status: PlaylistHealthStatus.down,
            checkedAt: DateTime.now(),
            errorReason: 'Identifiants Xtream incomplets',
          );
        }
        return _checkXtream(
          playlist.xtreamServer!,
          playlist.xtreamUsername!,
          playlist.xtreamPassword!,
        );
    }
  }

  Future<PlaylistHealth> _checkM3u(String url) async {
    final Stopwatch sw = Stopwatch()..start();
    HttpClient? client;
    try {
      // Filet défensif : une source déjà en base d'AVANT ce correctif (ou
      // poussée par un chemin qui aurait oublié de normaliser) peut ne pas
      // avoir de schéma → on le complète ici aussi, pour ne jamais afficher
      // un badge rouge sur une source qui, en réalité, fonctionne très bien.
      client = _newClient();
      final HttpClientRequest req = await client
          .getUrl(Uri.parse(SourceLinkUtils.ensureScheme(url)))
          .timeout(_kHealthCheckTimeout);
      req.followRedirects = true;
      req.maxRedirects = 5;
      req.headers.add(HttpHeaders.rangeHeader, 'bytes=0-1023');
      req.headers.add(HttpHeaders.acceptHeader, '*/*');
      final HttpClientResponse resp =
          await req.close().timeout(_kHealthCheckTimeout);
      await resp.drain<void>();
      return _classifyHttp(resp.statusCode, sw.elapsedMilliseconds);
    } on TimeoutException {
      return PlaylistHealth(
        status: PlaylistHealthStatus.down,
        checkedAt: DateTime.now(),
        ttfbMs: sw.elapsedMilliseconds,
        errorReason: 'Timeout',
      );
    } on SocketException catch (e) {
      return PlaylistHealth(
        status: PlaylistHealthStatus.down,
        checkedAt: DateTime.now(),
        ttfbMs: sw.elapsedMilliseconds,
        errorReason: 'Réseau (${e.osError?.message ?? "socket"})',
      );
    } on Exception catch (e) {
      return PlaylistHealth(
        status: PlaylistHealthStatus.unknown,
        checkedAt: DateTime.now(),
        ttfbMs: sw.elapsedMilliseconds,
        errorReason: e.toString(),
      );
    } finally {
      client?.close(force: true);
    }
  }

  Future<PlaylistHealth> _checkXtream(
    String server,
    String username,
    String password,
  ) async {
    final Stopwatch sw = Stopwatch()..start();
    HttpClient? client;
    try {
      // Même filet défensif que pour le M3U ci-dessus.
      final Uri uri = Uri.parse(SourceLinkUtils.ensureScheme(server)).replace(
        path: '/player_api.php',
        queryParameters: <String, String>{
          'username': username,
          'password': password,
        },
      );
      client = _newClient();
      final HttpClientRequest req =
          await client.getUrl(uri).timeout(_kHealthCheckTimeout);
      req.followRedirects = true;
      req.maxRedirects = 5;
      req.headers.add(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse resp =
          await req.close().timeout(_kHealthCheckTimeout);
      final String body = await resp
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      // Pour Xtream on a un signal supplementaire dans le body : si
      // `user_info.auth == 0` -> credentials refuses meme avec HTTP
      // 200. C'est plus precis que de se fier au seul code HTTP
      // (certains serveurs renvoient 200 + JSON {"user_info":{"auth":0}}).
      if (resp.statusCode == 200) {
        try {
          final dynamic parsed = jsonDecode(body);
          if (parsed is Map &&
              parsed['user_info'] is Map &&
              (parsed['user_info'] as Map)['auth'] == 0) {
            return PlaylistHealth(
              status: PlaylistHealthStatus.auth,
              checkedAt: DateTime.now(),
              httpCode: 200,
              ttfbMs: sw.elapsedMilliseconds,
              errorReason: 'auth=0 dans user_info',
            );
          }
        } catch (_) {
          // JSON malforme — on traite comme un OK dégradé (probe
          // marche en tant que ping reseau).
        }
      }
      return _classifyHttp(resp.statusCode, sw.elapsedMilliseconds);
    } on TimeoutException {
      return PlaylistHealth(
        status: PlaylistHealthStatus.down,
        checkedAt: DateTime.now(),
        ttfbMs: sw.elapsedMilliseconds,
        errorReason: 'Timeout',
      );
    } on SocketException catch (e) {
      return PlaylistHealth(
        status: PlaylistHealthStatus.down,
        checkedAt: DateTime.now(),
        ttfbMs: sw.elapsedMilliseconds,
        errorReason: 'Réseau (${e.osError?.message ?? "socket"})',
      );
    } on Exception catch (e) {
      return PlaylistHealth(
        status: PlaylistHealthStatus.unknown,
        checkedAt: DateTime.now(),
        ttfbMs: sw.elapsedMilliseconds,
        errorReason: e.toString(),
      );
    } finally {
      client?.close(force: true);
    }
  }

  /// Mapping HTTP -> [PlaylistHealthStatus]. Public + visibleForTesting
  /// pour qu'on puisse verrouiller la regle sans monter de mock reseau.
  @visibleForTesting
  static PlaylistHealth classifyHttp(int statusCode, int ttfbMs) =>
      _classifyHttp(statusCode, ttfbMs);

  static PlaylistHealth _classifyHttp(int statusCode, int ttfbMs) {
    if (statusCode == 200 || statusCode == 206) {
      // TTFB > 3s = lent (TTFB normal d'un serveur Xtream en bonne
      // sante est < 1s ; > 3s laisse presager des problemes au cast
      // et au streaming).
      final PlaylistHealthStatus status = ttfbMs > 3000
          ? PlaylistHealthStatus.slow
          : PlaylistHealthStatus.ok;
      return PlaylistHealth(
        status: status,
        checkedAt: DateTime.now(),
        httpCode: statusCode,
        ttfbMs: ttfbMs,
      );
    }
    if (statusCode == 401 || statusCode == 403) {
      return PlaylistHealth(
        status: PlaylistHealthStatus.auth,
        checkedAt: DateTime.now(),
        httpCode: statusCode,
        ttfbMs: ttfbMs,
      );
    }
    // HTTP 458 (custom Xtream "trop de connexions"), 429 (Too Many
    // Requests), 503 (Service Unavailable) = saturation provider.
    if (statusCode == 458 || statusCode == 429 || statusCode == 503) {
      return PlaylistHealth(
        status: PlaylistHealthStatus.saturated,
        checkedAt: DateTime.now(),
        httpCode: statusCode,
        ttfbMs: ttfbMs,
      );
    }
    return PlaylistHealth(
      status: PlaylistHealthStatus.unknown,
      checkedAt: DateTime.now(),
      httpCode: statusCode,
      ttfbMs: ttfbMs,
    );
  }

  HttpClient _newClient() {
    return HttpClient()
      ..connectionTimeout = _kHealthCheckTimeout
      ..idleTimeout = _kHealthCheckTimeout
      ..userAgent = 'VLC/3.0.20 LibVLC/3.0.20 (The Few HealthChecker)'
      // Même tolérance que le fetch (cf. iptv_http.dart) : un serveur IPTV
      // https à certificat auto-signé/expiré n'est PAS une source morte.
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
  }
}
