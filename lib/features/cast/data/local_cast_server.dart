// =========================================================
//  local_cast_server.dart — Mini-serveur HTTP "Cast universel"
// =========================================================
//  L'app héberge un serveur HTTP léger sur un port libre du
//  téléphone. La TV (Google TV, Tizen, WebOS, n'importe quelle
//  Smart TV avec un navigateur web) ouvre cette URL et joue
//  le flux dans une page HTML5 <video>.
//
//  Cette approche couvre *n'importe quelle* TV avec un navigateur,
//  même celles que ni DLNA, ni Chromecast, ni Roku ne touchent.
//
//  La page embarque :
//    - mpegts.js (CDN) → pour les flux MPEG-TS bruts (.ts)
//    - hls.js (CDN)    → pour les .m3u8
//    - <video> natif   → pour MP4 / MKV / WebM
//
//  Le serveur sert 2 routes :
//    GET /           → la page HTML5 player
//    GET /current    → JSON { url, title } pour permettre au
//                      JavaScript de rafraîchir quand l'utilisateur
//                      zappe depuis le téléphone
// =========================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';

import '../../../core/observability/structured_logger.dart';
import 'dlna_profiles.dart';
import 'hls_relay_session.dart';

/// Entrée dans la table des relays actifs. Une par session de cast.
class _RelayEntry {
  _RelayEntry({
    required this.upstreamUrl,
    required this.profile,
    required this.createdAt,
  });

  final String upstreamUrl;
  final DlnaProfile profile;
  final DateTime createdAt;

  /// Reconnexions upstream effectuées SANS couper la TV (flux live).
  /// Journalisé à la première pour le diagnostic terrain.
  int upstreamReconnects = 0;
}

class LocalCastServer {
  LocalCastServer._();
  static final LocalCastServer instance = LocalCastServer._();

  HttpServer? _server;
  int _port = 0;

  /// Sessions de relay actives, indexées par token aléatoire.
  /// On garde un nombre limité pour éviter une fuite mémoire si
  /// le caller oublie de clearRelay (failover qui crash, etc.).
  final Map<String, _RelayEntry> _relays = <String, _RelayEntry>{};
  static const int _kMaxRelays = 8;

  /// Sessions HLS live (vraie segmentation TS → segments finis +
  /// playlist glissante) pour le repli Google Cast. Indexées par le
  /// MÊME token que `_relays`. Une session tire le flux upstream en
  /// continu → on n'en garde qu'un petit nombre en vie.
  final Map<String, HlsRelaySession> _hlsSessions =
      <String, HlsRelaySession>{};
  static const int _kMaxHlsSessions = 2;

  /// UA envoyé aux serveurs IPTV (filtres anti-bot Xtream).
  static const String _kUpstreamUserAgent =
      'VLC/3.0.20 LibVLC/3.0.20 (7 MOTION Relay)';

  /// Mode « Caster sur un écran » EN LOCAL (même Wi-Fi) : le PC / la TV
  /// ouvre http://<ip-téléphone>:<port>/screen dans son navigateur. Le
  /// flux est relayé par le TÉLÉPHONE (IP résidentielle → autorisée par
  /// les fournisseurs qui bloquent le cloud, erreur 456). `_browserToken`
  /// = la session courante exposée à la page via /current.
  String? _browserToken;
  String _browserTitle = '';

  /// Lance le serveur (idempotent — réutilise l'instance existante).
  /// Renvoie le port d'écoute, ou jette une exception si bind échoue.
  Future<int> start() async {
    if (_server != null) return _port;

    // On bind sur 0.0.0.0 pour être joignable depuis le LAN
    // (par défaut, dart:io HttpServer ne bind que sur localhost).
    // Port 0 = laisse l'OS choisir un port libre.
    final HttpServer server =
        await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    _port = server.port;

    server.listen(_handleRequest, onError: (Object e) {
      if (kDebugMode) debugPrint('[LocalCastServer] error: $e');
    });

    if (kDebugMode) {
      debugPrint('[LocalCastServer] listening on port $_port');
    }
    return _port;
  }

  Future<void> stop() async {
    for (final HlsRelaySession s in _hlsSessions.values) {
      s.stop();
    }
    _hlsSessions.clear();
    await _server?.close(force: true);
    _server = null;
  }

  int get port => _port;
  bool get isRunning => _server != null;

  // ============================================================
  //  Handlers
  // ============================================================

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final String path = req.uri.path;
      // VRAI HLS live (2026-07-09) : /hls/<token>.m3u8 = playlist
      // GLISSANTE (segments finis ~3 s découpés par TsHlsSegmenter),
      // /hls/<token>/<seq>.ts = segment fini. Le Default Media
      // Receiver (CAF/Shaka) télécharge chaque segment EN ENTIER
      // avant de le décoder : l'ancien « segment unique infini »
      // (/hls/<token>.ts) ne produisait jamais une frame → 100 %
      // d'échecs « codec/format non supporté » sur SHIELD & co.
      // Le récepteur fetch en XHR cross-origin → CORS obligatoire
      // sur la playlist ET les segments.
      if (path.startsWith('/hls/')) {
        if (req.method == 'OPTIONS') {
          _setCorsHeaders(req.response);
          req.response.statusCode = HttpStatus.noContent;
          await req.response.close();
          return;
        }
        final List<String> segs = req.uri.pathSegments; // [hls, ...]
        if (segs.length == 3 && segs[2].endsWith('.ts')) {
          await _serveHlsLiveSegment(req, token: segs[1], seqName: segs[2]);
          return;
        }
        if (path.endsWith('.m3u8')) {
          await _serveHlsManifest(req);
          return;
        }
        if (path.endsWith('.ts')) {
          // Legacy : pass-through direct (plus référencé par les
          // playlists générées, conservé pour un récepteur qui aurait
          // encore l'ancienne URL en cache).
          await _serveHlsSegment(req);
          return;
        }
      }
      if (path.startsWith('/relay/')) {
        await _serveRelay(req);
        return;
      }
      // Mode « Caster sur un écran » LOCAL (additif — ne touche pas au
      // cast DLNA/Chromecast existant) : page récepteur + état courant.
      if (path == '/screen' || path == '/') {
        await _serveScreenPage(req);
        return;
      }
      if (path == '/current') {
        await _serveCurrent(req);
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (e) {
      if (kDebugMode) debugPrint('[LocalCastServer] handler error: $e');
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  /// En-têtes CORS pour les routes /hls/* : la page du Default Media
  /// Receiver (origine gstatic.com) fetch playlist et segments en XHR
  /// cross-origin — sans CORS, Shaka échoue AVANT toute décodage et la
  /// TV remonte un « format non supporté » trompeur.
  void _setCorsHeaders(HttpResponse resp) {
    resp.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Range, Origin, Content-Type')
      ..set('Access-Control-Expose-Headers', 'Content-Length, Content-Range');
  }

  /// Sert la playlist LIVE GLISSANTE d'une session HLS. Au premier
  /// appel on attend que le segmenteur ait produit assez de matière
  /// (3 segments ≈ 9 s de flux = matelas anti-saccades) — le récepteur
  /// vient d'être lancé, son LOAD tolère ce délai (budget 25 s sender).
  Future<void> _serveHlsManifest(HttpRequest req) async {
    final String last = req.uri.pathSegments.last; // <token>.m3u8
    final int dot = last.indexOf('.');
    final String token = dot > 0 ? last.substring(0, dot) : last;
    final HlsRelaySession? session = _hlsSessions[token];
    if (session == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    session.touch();
    session.playlistServed++;
    // 3 segments (~9 s) avant la premiere reponse : demarre la lecture
    // avec un vrai matelas de buffer (diag fluidite 2026-07-09). Les
    // rafraichissements suivants repondent immediatement.
    final bool ready =
        await session.waitForSegments(3, const Duration(seconds: 15));
    if (!ready) {
      // Upstream mort ou trop lent : 503 → le récepteur remonte une
      // vraie erreur réseau (pas un faux « codec »).
      _setCorsHeaders(req.response);
      req.response.statusCode = HttpStatus.serviceUnavailable;
      await req.response.close();
      return;
    }
    if (!session.readyLogged) {
      session.readyLogged = true;
      // Le codec compte : HEVC-dans-TS n'est pas décodé par le Default
      // Media Receiver des vrais Chromecast (limite CAF, pas un bug du
      // relais) — la SHIELD, elle, le décode.
      StructuredLogger.instance.info(
        domain: 'cast',
        event: 'hls_relay.ready',
        ctx: <String, Object?>{
          'codec': session.videoCodec,
          'audio': session.audioCodec,
          'segments': session.segmentCount,
        },
      );
    }
    // URIs RELATIVES à la playlist (/hls/<token>.m3u8) :
    // `<token>/<seq>.ts` → /hls/<token>/<seq>.ts.
    final String manifest = session.playlist(segmentUriPrefix: '$token/');
    _setCorsHeaders(req.response);
    req.response.headers
      ..set('Content-Type', 'application/vnd.apple.mpegurl')
      ..set('Cache-Control', 'no-store, no-cache');
    req.response.write(manifest);
    await req.response.close();
  }

  /// Sert un segment FINI de la fenêtre live (Content-Length connu —
  /// le récepteur télécharge, décode, enchaîne).
  Future<void> _serveHlsLiveSegment(
    HttpRequest req, {
    required String token,
    required String seqName,
  }) async {
    final HlsRelaySession? session = _hlsSessions[token];
    final int dot = seqName.indexOf('.');
    final int? seq =
        int.tryParse(dot > 0 ? seqName.substring(0, dot) : seqName);
    if (session == null || seq == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    session.touch();
    session.segmentsServed++;
    final HlsLiveSegment? segment = session.segment(seq);
    if (segment == null) {
      // Segment déjà évincé (récepteur trop en retard) ou pas encore
      // produit : 404 → Shaka recharge la playlist et se recale.
      _setCorsHeaders(req.response);
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    _setCorsHeaders(req.response);
    req.response.headers
      ..set('Content-Type', 'video/mp2t')
      ..set('Cache-Control', 'no-store, no-cache')
      ..set('Content-Length', segment.bytes.length);
    req.response.add(segment.bytes);
    await req.response.close();
  }

  /// Sert le segment .ts pass-through du provider IPTV. Reutilise
  /// la logique de `_serveRelay` mais avec un Content-Type adapte
  /// au context HLS (segment HLS = video/mp2t officiellement, c'est
  /// ce que le Cast attend dans ce contexte).
  Future<void> _serveHlsSegment(HttpRequest req) async {
    final String last = req.uri.pathSegments.last; // <token>.ts
    final int dot = last.indexOf('.');
    final String token = dot > 0 ? last.substring(0, dot) : last;
    final _RelayEntry? entry = _relays[token];
    if (entry == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    // Reutilise la plomberie de proxy HTTP existante, sauf qu'on
    // force le Content-Type a video/mp2t (segment HLS standard).
    await _proxyUpstream(
      req,
      entry,
      forcedContentType: 'video/mp2t',
      token: token,
    );
  }

  // ============================================================
  //  Relay HTTP — pass-through proxy DLNA-compatible
  // ============================================================
  //  Une URL `/relay/<token>.<ext>` est servie ICI au lieu d'envoyer
  //  l'URL upstream directement au récepteur. Bénéfices :
  //
  //    1. Suivi des redirects (302/307) — les TVs DLNA ne suivent pas.
  //    2. Injection des headers DLNA (`contentFeatures.dlna.org`,
  //       `transferMode.dlna.org`) que beaucoup de récepteurs exigent.
  //    3. User-Agent constant (VLC) qui passe les filtres anti-bot
  //       des serveurs Xtream.
  //    4. Forward du `Range` pour la VOD avec seek.
  //
  //  Pas de buffer, pas de transcoding — c'est un simple tuyau qui
  //  copie les octets upstream → récepteur en streaming.
  // ============================================================

  /// Enregistre une session relay et renvoie l'URL LAN-accessible
  /// à pousser au récepteur. Renvoie `null` si on n'arrive pas à
  /// trouver l'IP locale (cas exotique : pas de réseau).
  ///
  /// [receiverHost] sert à choisir la BONNE interface réseau quand
  /// le téléphone est sur plusieurs réseaux (WiFi + VPN p.ex.).
  ///
  /// [wrapInHls] (Phase 1+/2026-06-01) : si `true`, on renvoie une
  /// URL HLS `.m3u8` qui pointe vers une playlist synthetique a 1
  /// segment .ts. Indispensable pour Google Cast (le SDK ne supporte
  /// PAS MPEG-TS .ts en LIVE officiellement — seulement HLS et DASH).
  /// Voir la doc Google : developers.google.com/cast/docs/media.
  /// Pour DLNA on garde le pass-through .ts direct (les renderers
  /// DLNA conformes attendent `video/mp2t`).
  Future<String?> registerRelay({
    required String upstreamUrl,
    required DlnaProfile profile,
    required String receiverHost,
    bool wrapInHls = false,
  }) async {
    await start();

    // Evict le plus vieux si on dépasse le budget — protège contre
    // une fuite si un caller oublie clearRelay.
    if (_relays.length >= _kMaxRelays) {
      final String oldest = _relays.entries
          .reduce((MapEntry<String, _RelayEntry> a,
                  MapEntry<String, _RelayEntry> b) =>
              a.value.createdAt.isBefore(b.value.createdAt) ? a : b)
          .key;
      _relays.remove(oldest);
    }

    final String token = _randomToken();
    _relays[token] = _RelayEntry(
      upstreamUrl: upstreamUrl,
      profile: profile,
      createdAt: DateTime.now(),
    );

    final String? lanIp = await _lanIpFor(receiverHost);
    if (lanIp == null) {
      _relays.remove(token);
      return null;
    }
    // Google Cast : VRAIE session HLS live (segmentation TS côté
    // téléphone, playlist glissante). Démarrée tout de suite : les
    // premiers segments s'accumulent PENDANT que le sender établit la
    // session Cast (bascule receiver + picker = plusieurs secondes).
    // DLNA garde le pass-through /relay/<token>.<ext> direct.
    if (wrapInHls) {
      _evictOldestHlsSessionsIfNeeded();
      final HlsRelaySession session = HlsRelaySession(
        upstreamUrl: upstreamUrl,
        userAgent: _kUpstreamUserAgent,
      );
      _hlsSessions[token] = session;
      session.start();
      StructuredLogger.instance.info(
        domain: 'cast',
        event: 'hls_relay.start',
        ctx: <String, Object?>{'token': token},
      );
      return 'http://$lanIp:$_port/hls/$token.m3u8';
    }
    return 'http://$lanIp:$_port/relay/$token.${profile.fileExtension}';
  }

  /// Les sessions HLS tirent le flux upstream en continu — on n'en
  /// tolère que [_kMaxHlsSessions] : au-delà, la plus ancienne (déjà
  /// remplacée par un zap en pratique) est arrêtée.
  void _evictOldestHlsSessionsIfNeeded() {
    while (_hlsSessions.length >= _kMaxHlsSessions) {
      final String oldest = _hlsSessions.keys.first;
      _hlsSessions.remove(oldest)?.stop();
      _relays.remove(oldest);
    }
  }

  void clearRelay(String relayUrl) {
    final String? token = _tokenFromUrl(relayUrl);
    if (token == null) return;
    _relays.remove(token);
    _hlsSessions.remove(token)?.stop();
  }

  /// Etat REEL de la session HLS derriere [relayUrl], pour enrichir les
  /// messages d'erreur du cast : codec vu dans la PMT + ce que la TV a
  /// effectivement telecharge. `null` si la session est inconnue.
  String? hlsSessionDebugInfo(String relayUrl) {
    final String? token = _tokenFromUrl(relayUrl);
    final HlsRelaySession? s = token != null ? _hlsSessions[token] : null;
    if (s == null) return null;
    return 'codec=${s.videoCodec}'
        ', audio=${s.audioCodec}'
        ', segments produits=${s.totalSegmentsProduced}'
        ', playlists servies=${s.playlistServed}'
        ', segments servis=${s.segmentsServed}'
        '${s.fatalError != null ? ', upstream KO: ${s.fatalError}' : ''}';
  }

  /// Extrait le token d'une URL relais :
  /// http://ip:port/relay/<token>.<ext> ou /hls/<token>.m3u8
  static String? _tokenFromUrl(String relayUrl) {
    final Uri uri = Uri.tryParse(relayUrl) ?? Uri();
    if (uri.pathSegments.length < 2) return null;
    final String segment = uri.pathSegments.last;
    final int dot = segment.indexOf('.');
    return dot > 0 ? segment.substring(0, dot) : segment;
  }

  String _randomToken() {
    const String alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final Random rng = Random.secure();
    return List<String>.generate(
      10,
      (int _) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  Future<void> _serveRelay(HttpRequest req) async {
    // Extrait le token (avant le `.`) du dernier segment
    final String last = req.uri.pathSegments.last;
    final int dot = last.indexOf('.');
    final String token = dot > 0 ? last.substring(0, dot) : last;
    final _RelayEntry? entry = _relays[token];
    if (entry == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    await _proxyUpstream(req, entry, token: token);
  }

  /// Phase 1+/HLS Wrapper — factorisation du pass-through HTTP pour
  /// que `_serveRelay` (DLNA) et `_serveHlsSegment` (Google Cast)
  /// partagent la meme plomberie. Pas de buffer en RAM ; les headers
  /// DLNA sont injectes sauf si [forcedContentType] est fourni (cas
  /// HLS ou on veut un MIME strict `video/mp2t` pour le segment).
  ///
  /// RECONNEXION UPSTREAM (2026-07-09) : pour un flux LIVE (longueur
  /// inconnue, pas de Range), une coupure upstream ne DOIT PLUS couper
  /// la TV. Les serveurs Xtream ferment périodiquement la socket d'un
  /// live (comportement normal) et un creux WiFi côté téléphone casse
  /// le GET — avant ce fix, la TV voyait EOF, passait STOPPED, et il
  /// fallait re-dérouler tout le failover SOAP (le relais HLS
  /// Chromecast, lui, reconnectait déjà). Ici on RE-GET l'upstream
  /// (URL portail d'origine → token frais, redirections re-suivies) et
  /// on continue d'écrire dans la MÊME réponse TV : le tampon interne
  /// du renderer absorbe le trou, MPEG-TS se resynchronise tout seul
  /// (PAT/PMT périodiques).
  Future<void> _proxyUpstream(
    HttpRequest req,
    _RelayEntry entry, {
    String? forcedContentType,
    String? token,
  }) async {
    // HEAD du récepteur → réponse 200 + headers DLNA SANS interroger
    // l'upstream. Beaucoup de TVs (Samsung, LG) sondent en HEAD avant
    // le GET ; or les serveurs Xtream gèrent MAL les HEAD (coupure de
    // socket, 404) et leurs tokens sont par-connexion — forwarder le
    // HEAD consommait le token et/ou renvoyait 502 → la TV concluait
    // « Resource not found » AVANT même le GET (diag LG 2026-07-09).
    // Le relais SAIT ce qu'il servira (profil DLNA connu) : il répond
    // pour lui-même, comme le font les proxys IPTV/BubbleUPnP.
    if (req.method == 'HEAD') {
      try {
        _writeRelayHeadersLocal(req.response, entry,
            forcedContentType: forcedContentType);
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
      } catch (_) {}
      return;
    }

    final HttpResponse out = req.response;
    final String? rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
    bool headersWritten = false;
    bool clientGone = false;
    // `done` complète (souvent avec erreur) dès que la TV ferme la
    // connexion — c'est notre signal d'arrêt de la boucle.
    unawaited(out.done.then<void>(
      (_) => clientGone = true,
      onError: (Object _) => clientGone = true,
    ));

    // `true` une fois constaté que l'upstream est un flux SANS fin
    // connue (live) : seul cas où la reconnexion est saine. Une VOD
    // (Content-Length connu ou Range) reprise à zéro corromprait la
    // lecture → pas de reconnexion, comportement historique.
    bool unbounded = false;
    int consecutiveNoData = 0;
    const int kMaxConsecutiveNoData = 6;

    while (!clientGone) {
      final HttpClient client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8)
        // idleTimeout doit être LARGE — un flux LIVE peut avoir des
        // creux de quelques secondes entre les segments. À 30s on
        // coupait après ~5s sur certaines TVs LG (popup natif
        // "périphérique déconnecté").
        ..idleTimeout = const Duration(minutes: 10)
        ..userAgent = _kUpstreamUserAgent
        ..autoUncompress = false;
      bool gotData = false;
      try {
        final HttpClientRequest up =
            await client.getUrl(Uri.parse(entry.upstreamUrl));
        up.followRedirects = true;
        up.maxRedirects = 5;
        if (rangeHeader != null) {
          up.headers.add(HttpHeaders.rangeHeader, rangeHeader);
        }
        final HttpClientResponse upResp = await up.close();
        if (upResp.statusCode < 200 || upResp.statusCode >= 300) {
          await upResp.drain<void>();
          throw HttpException('upstream HTTP ${upResp.statusCode}');
        }

        if (!headersWritten) {
          _writeRelayHeaders(out, upResp, entry,
              forcedContentType: forcedContentType);
          // Status code (200 / 206) — recopié de l'upstream
          out.statusCode = upResp.statusCode;
          headersWritten = true;
          unbounded = upResp.contentLength == -1 && rangeHeader == null;
        }

        // Pipe manuel chunk par chunk (au lieu de addStream) : le
        // `flush()` par chunk donne la BACKPRESSURE (on ne bufferise
        // pas pour une TV lente) et surface immédiatement l'erreur
        // d'écriture quand la TV coupe.
        await for (final List<int> chunk in upResp) {
          if (clientGone) break;
          out.add(chunk);
          await out.flush();
          gotData = true;
          consecutiveNoData = 0;
        }
        // Fin de socket upstream « propre » : reconnexion si live.
      } on Object catch (e) {
        if (kDebugMode) debugPrint('[Relay] $e');
        if (!headersWritten) {
          // Premier contact upstream raté → 502, comme avant.
          try {
            out.statusCode = HttpStatus.badGateway;
            await out.close();
          } catch (_) {}
          return;
        }
      } finally {
        client.close(force: true);
      }

      if (clientGone || !unbounded) break;
      // Session libérée (zap / disconnect) pendant qu'on servait → stop.
      if (token != null && !_relays.containsKey(token)) break;
      if (!gotData) consecutiveNoData++;
      if (consecutiveNoData > kMaxConsecutiveNoData) break;
      entry.upstreamReconnects++;
      if (entry.upstreamReconnects == 1) {
        StructuredLogger.instance.info(
          domain: 'cast',
          event: 'relay.upstream_reconnect',
          ctx: <String, Object?>{'token': token},
        );
      }
      await Future<void>.delayed(
          Duration(milliseconds: 400 * (consecutiveNoData + 1)));
    }
    try {
      await out.close();
    } catch (_) {}
  }

  /// Headers DLNA construits LOCALEMENT (réponse HEAD) : aucun aller-
  /// retour upstream, pas de Content-Length (flux live sans fin connue).
  void _writeRelayHeadersLocal(
    HttpResponse out,
    _RelayEntry entry, {
    String? forcedContentType,
  }) {
    out.headers.set(
      HttpHeaders.contentTypeHeader,
      forcedContentType ?? entry.profile.mime,
    );
    final String profileTag = entry.profile.buildProtocolInfo();
    final String contentFeatures =
        profileTag.replaceFirst(RegExp(r'^http-get:\*:[^:]+:'), '');
    out.headers.set('contentFeatures.dlna.org', contentFeatures);
    out.headers.set('getcontentFeatures.dlna.org', contentFeatures);
    out.headers
        .set('transferMode.dlna.org', entry.profile.transferMode.header);
    out.headers.set('Cache-Control', 'no-store, no-cache');
  }

  /// Recopie les headers utiles de l'upstream et AJOUTE les headers
  /// DLNA que les récepteurs exigent. Si [forcedContentType] est
  /// fourni (cas HLS), il remplace le MIME au lieu d'utiliser le
  /// profile DLNA — necessaire pour annoncer `video/mp2t` aux
  /// segments HLS attendus par Cast.
  void _writeRelayHeaders(
    HttpResponse out,
    HttpClientResponse up,
    _RelayEntry entry, {
    String? forcedContentType,
  }) {
    // Type MIME : si forcedContentType (cas HLS segment) on l'utilise
    // tel quel ; sinon on prefere le profil DLNA a l'upstream
    // (souvent `application/octet-stream` sur les flux IPTV).
    out.headers.set(
      HttpHeaders.contentTypeHeader,
      forcedContentType ?? entry.profile.mime,
    );

    // Content-Length / Range
    if (up.contentLength != -1) {
      out.headers.set(HttpHeaders.contentLengthHeader, up.contentLength);
    }
    final String? cr = up.headers.value('content-range');
    if (cr != null) out.headers.set('Content-Range', cr);
    final String? ar = up.headers.value(HttpHeaders.acceptRangesHeader);
    if (ar != null) out.headers.set(HttpHeaders.acceptRangesHeader, ar);

    // ----- Headers DLNA (le coeur du fix) -----
    final String profileTag = entry.profile.buildProtocolInfo();
    // contentFeatures.dlna.org = même format que protocolInfo mais
    // sans le préfixe http-get:*:
    // (cf. DLNA Guidelines vol.1 §7.4.1)
    final String contentFeatures =
        profileTag.replaceFirst(RegExp(r'^http-get:\*:[^:]+:'), '');
    out.headers.set('contentFeatures.dlna.org', contentFeatures);
    out.headers.set('getcontentFeatures.dlna.org', contentFeatures);
    out.headers.set('transferMode.dlna.org', entry.profile.transferMode.header);

    // Pas de cache — c'est du LIVE quoi qu'il arrive.
    out.headers.set('Cache-Control', 'no-store, no-cache');
    // Pas de `Connection: close` — certaines TVs LG l'interprètent
    // comme "le serveur va couper", déclenchent un popup natif
    // "périphérique déconnecté" après quelques secondes. Keep-alive
    // par défaut convient mieux à un flux LIVE.
  }

  /// Découvre l'IP locale du téléphone sur le bon réseau (celui
  /// du récepteur). On préfère une IP du même /24 ; sinon on tombe
  /// sur la première IPv4 non-loopback disponible.
  Future<String?> _lanIpFor(String receiverHost) async {
    try {
      final List<NetworkInterface> ifs = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      // Heuristique /24
      final List<String> rParts = receiverHost.split('.');
      if (rParts.length == 4) {
        final String prefix = '${rParts[0]}.${rParts[1]}.${rParts[2]}.';
        for (final NetworkInterface ni in ifs) {
          for (final InternetAddress a in ni.addresses) {
            if (a.address.startsWith(prefix)) return a.address;
          }
        }
      }
      // Fallback : première IPv4 non-loopback
      for (final NetworkInterface ni in ifs) {
        for (final InternetAddress a in ni.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[Relay] LAN IP lookup: $e');
    }
    return null;
  }

  // ============================================================
  //  « Caster sur un écran » LOCAL (même Wi-Fi) — phone → navigateur
  // ============================================================
  //  Contourne le blocage cloud (456) : c'est le TÉLÉPHONE (IP
  //  résidentielle, autorisée) qui récupère le flux et le sert au PC /
  //  à la TV via son navigateur. Le PC ouvre http://<ip>:<port>/screen.
  //  100 % additif — n'affecte ni le relais DLNA ni le cast Chromecast.

  /// Démarre (ou met à jour) le flux exposé au navigateur. Renvoie
  /// l'URL à ouvrir sur le PC / la TV (même Wi-Fi), ou `null` si l'IP
  /// locale est introuvable.
  Future<String?> serveBrowser({
    required String upstreamUrl,
    String title = '',
  }) async {
    await start();
    // Une seule session navigateur à la fois : on remplace la précédente.
    if (_browserToken != null) _relays.remove(_browserToken);
    final DlnaProfile profile =
        DlnaProfiles.select(url: upstreamUrl, finalMime: null);
    final String token = _randomToken();
    _relays[token] = _RelayEntry(
      upstreamUrl: upstreamUrl,
      profile: profile,
      createdAt: DateTime.now(),
    );
    _browserToken = token;
    _browserTitle = title;
    final String? lanIp = await _lanIpFor('');
    if (lanIp == null) return null;
    return 'http://$lanIp:$_port/screen';
  }

  /// Arrête la session navigateur (l'écran repassera en « attente »).
  void stopBrowser() {
    if (_browserToken != null) {
      _relays.remove(_browserToken);
      _browserToken = null;
    }
  }

  Future<void> _serveCurrent(HttpRequest req) async {
    req.response.headers
      ..set('Content-Type', 'application/json; charset=utf-8')
      ..set('Cache-Control', 'no-store, no-cache');
    // PAS de Access-Control-Allow-Origin ici (audit sécurité 2026-07-05,
    // AUDIT-CAST-7MOTION §5.3) : le SEUL appelant légitime est le poll() de
    // _screenHtml, servie par CE MÊME serveur → requête same-origin, aucun
    // CORS requis. Le wildcard précédent exposait le token du relais (donc
    // l'accès au flux abonné, via /relay/<token>) à N'IMPORTE QUEL script
    // JS tournant sur le LAN (page tierce ouverte dans un navigateur du même
    // Wi-Fi), qui pouvait le lire silencieusement en arrière-plan sans que
    // l'utilisateur n'ouvre jamais /screen. Aucun code de ce dépôt ne fait de
    // fetch cross-origin vers /current (vérifié) — retrait sans régression.
    final String? tok = _browserToken;
    final _RelayEntry? e = tok != null ? _relays[tok] : null;
    if (tok == null || e == null) {
      req.response.write('{"url":null}');
    } else {
      final String ext = e.profile.fileExtension;
      final String t =
          _browserTitle.replaceAll('"', '').replaceAll(r'\', '');
      req.response.write('{"url":"/relay/$tok.$ext","title":"$t"}');
    }
    await req.response.close();
  }

  Future<void> _serveScreenPage(HttpRequest req) async {
    req.response.headers
      ..set('Content-Type', 'text/html; charset=utf-8')
      ..set('Cache-Control', 'no-store, no-cache');
    req.response.write(_screenHtml);
    await req.response.close();
  }

  // Page récepteur servie EN LOCAL (http) → pas de « mixed content »
  // (la page http peut charger le relais http du même origin ; le script
  // mpegts.js vient d'un CDN https, ce qui est autorisé depuis du http).
  static const String _screenHtml = r'''<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>7 MOTION - Ecran</title>
<script src="//cdn.jsdelivr.net/npm/mpegts.js@1.7.3/dist/mpegts.js"></script>
<style>*{margin:0;padding:0;box-sizing:border-box}html,body{width:100%;height:100%;
background:#0A0A0C;color:#fff;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;overflow:hidden}
#v{position:fixed;inset:0;width:100%;height:100%;background:#000;object-fit:contain;display:none}
#m{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;text-align:center;
padding:6vh 5vw;font-size:clamp(16px,2.6vw,28px);color:#9aa;line-height:1.5}
#m b{color:#D63A30}</style></head>
<body><video id="v" playsinline webkit-playsinline autoplay></video>
<div id="m"><span>7&nbsp;<b>MOTION</b> &mdash; en attente d'une chaine depuis le telephone...</span></div>
<script>(function(){
var v=document.getElementById('v'),m=document.getElementById('m');
var player=null,curUrl=null;
function show(t){m.innerHTML='<span>'+t+'</span>';m.style.display='flex';v.style.display='none';}
function teardown(){try{if(player){player.destroy();player=null;}}catch(e){}}
function play(url){teardown();
  if(!window.mpegts||!mpegts.isSupported()){show("Navigateur non compatible. Essaie Chrome ou Edge.");return;}
  try{player=mpegts.createPlayer({type:'mpegts',isLive:true,url:url},
    {liveBufferLatencyChasing:true,lazyLoad:false,enableWorker:true});
  player.attachMediaElement(v);
  player.on(mpegts.Events.ERROR,function(t,d){
    if(t==='MediaError'){show("Codec non lisible sur cet ecran (souvent HEVC). Essaie Chromecast/DLNA.");}
    else{show("Flux interrompu. Le telephone joue-t-il toujours la chaine ?");}
  });
  player.load();curUrl=url;m.style.display='none';v.style.display='block';v.muted=false;
  var p=v.play();if(p&&p.catch)p.catch(function(){v.muted=true;v.play().catch(function(){});});
  }catch(e){show("Lecture impossible.");}}
var fails=0;
function poll(){fetch('/current',{cache:'no-store'}).then(function(r){return r.json();})
  .then(function(s){fails=0;
    if(s&&s.url){if(s.url!==curUrl)play(s.url);}
    else{teardown();curUrl=null;show("7&nbsp;<b>MOTION</b> &mdash; en attente d'une chaine depuis le telephone...");}})
  .catch(function(){fails++;if(fails===5)show("Connexion au telephone perdue. Meme Wi-Fi ?");})
  .then(function(){setTimeout(poll,1500);});}
poll();})();</script></body></html>''';
}
