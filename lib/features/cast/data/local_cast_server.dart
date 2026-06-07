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

import 'dlna_profiles.dart';

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
      // Phase 1+/HLS Wrapper (2026-06-01) : /hls/<token>.m3u8
      // genere une playlist HLS minimale pointant vers le segment
      // .ts. Decouverte clef : Google Cast SDK ne supporte PAS
      // officiellement MPEG-TS (.ts) en LIVE — seulement HLS et
      // DASH. Pour faire passer un flux .ts brut a un Chromecast,
      // on le wrap dans une playlist HLS synthetique. Le segment
      // sous-jacent est servi tel quel via /hls/<token>.ts.
      if (path.startsWith('/hls/') && path.endsWith('.m3u8')) {
        await _serveHlsManifest(req);
        return;
      }
      if (path.startsWith('/hls/') && path.endsWith('.ts')) {
        await _serveHlsSegment(req);
        return;
      }
      if (path.startsWith('/relay/')) {
        await _serveRelay(req);
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

  /// Phase 1+/HLS Wrapper — sert une playlist HLS minimale qui
  /// reference le segment .ts comme s'il etait un VOD/Event-style
  /// HLS valide.
  ///
  /// Format genere :
  ///   #EXTM3U
  ///   #EXT-X-VERSION:3
  ///   #EXT-X-TARGETDURATION:9
  ///   #EXT-X-MEDIA-SEQUENCE:0
  ///   #EXT-X-PLAYLIST-TYPE:EVENT
  ///   #EXTINF:8.0,
  ///   /hls/<token>.ts
  ///   #EXT-X-ENDLIST
  ///
  /// L'EXT-X-ENDLIST tag est present meme pour du live IPTV parce
  /// que le segment unique n'a pas de fin connue cote receveur — le
  /// Chromecast joue jusqu'a fermeture de la connexion TCP. C'est
  /// la technique standard "single-segment HLS" utilisee par
  /// BubbleUPnP / IPTV Proxy / etc.
  Future<void> _serveHlsManifest(HttpRequest req) async {
    final String last = req.uri.pathSegments.last; // <token>.m3u8
    final int dot = last.indexOf('.');
    final String token = dot > 0 ? last.substring(0, dot) : last;
    final _RelayEntry? entry = _relays[token];
    if (entry == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    // Playlist HLS LIVE a segment unique "infini". PAS de
    // #EXT-X-ENDLIST : avec lui, le receiver croit a un VOD de 8 s et
    // arrete la lecture au bout de 8 s (ecran "cast" bleu sans image
    // pour du live). PLAYLIST-TYPE:EVENT = playlist live append-only ;
    // le segment .ts est un flux continu que le receiver lit jusqu'a
    // fermeture TCP. Technique "single infinite segment" des proxys
    // IPTV->Cast.
    final String manifest = '#EXTM3U\n'
        '#EXT-X-VERSION:3\n'
        '#EXT-X-TARGETDURATION:10\n'
        '#EXT-X-MEDIA-SEQUENCE:0\n'
        '#EXT-X-PLAYLIST-TYPE:EVENT\n'
        '#EXTINF:10.0,\n'
        '/hls/$token.ts\n';
    req.response.headers
      ..set('Content-Type', 'application/vnd.apple.mpegurl')
      ..set('Cache-Control', 'no-store, no-cache')
      ..set('Access-Control-Allow-Origin', '*');
    req.response.write(manifest);
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
    if (lanIp == null) return null;
    // Phase 1+/HLS Wrapper : route /hls/<token>.m3u8 pour Google
    // Cast, /relay/<token>.<ext> pour DLNA legacy.
    if (wrapInHls) {
      return 'http://$lanIp:$_port/hls/$token.m3u8';
    }
    return 'http://$lanIp:$_port/relay/$token.${profile.fileExtension}';
  }

  void clearRelay(String relayUrl) {
    // L'URL contient le token : http://ip:port/relay/<token>.<ext>
    final Uri uri = Uri.tryParse(relayUrl) ?? Uri();
    if (uri.pathSegments.length < 2) return;
    final String segment = uri.pathSegments.last;
    final int dot = segment.indexOf('.');
    final String token = dot > 0 ? segment.substring(0, dot) : segment;
    _relays.remove(token);
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
    await _proxyUpstream(req, entry);
  }

  /// Phase 1+/HLS Wrapper — factorisation du pass-through HTTP pour
  /// que `_serveRelay` (DLNA) et `_serveHlsSegment` (Google Cast)
  /// partagent la meme plomberie. Pas de buffer en RAM, addStream
  /// pur ; les headers DLNA sont injectes sauf si
  /// [forcedContentType] est fourni (cas HLS ou on veut un MIME
  /// strict `video/mp2t` pour le segment).
  Future<void> _proxyUpstream(
    HttpRequest req,
    _RelayEntry entry, {
    String? forcedContentType,
  }) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      // idleTimeout doit être LARGE — un flux LIVE peut avoir des creux
      // de quelques secondes entre les segments. À 30s on coupait après
      // ~5s sur certaines TVs LG (popup natif "périphérique déconnecté").
      ..idleTimeout = const Duration(minutes: 10)
      ..userAgent = 'VLC/3.0.20 LibVLC/3.0.20 (7 MOTION Relay)'
      ..autoUncompress = false;

    try {
      final Uri upstream = Uri.parse(entry.upstreamUrl);

      // HEAD du récepteur → on répond avec les headers DLNA sans body.
      // Indispensable : beaucoup de TVs Samsung font un HEAD AVANT
      // le GET pour vérifier le profile et la disponibilité.
      if (req.method == 'HEAD') {
        final HttpClientRequest probe = await client.headUrl(upstream);
        final HttpClientResponse pResp = await probe.close();
        _writeRelayHeaders(req.response, pResp, entry,
            forcedContentType: forcedContentType);
        await pResp.drain<void>();
        await req.response.close();
        return;
      }

      // GET (avec ou sans Range)
      final HttpClientRequest up = await client.getUrl(upstream);
      up.followRedirects = true;
      up.maxRedirects = 5;
      final String? rangeHeader =
          req.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null) {
        up.headers.add(HttpHeaders.rangeHeader, rangeHeader);
      }
      final HttpClientResponse upResp = await up.close();

      _writeRelayHeaders(req.response, upResp, entry,
          forcedContentType: forcedContentType);
      // Status code (200 / 206) — recopié de l'upstream
      req.response.statusCode = upResp.statusCode;

      // Pipe streaming pur. addStream avale les chunks au fil de l'eau,
      // pas de buffer côté serveur. Si le client (TV) ferme, on coupe
      // la connexion upstream automatiquement.
      try {
        await req.response.addStream(upResp);
      } on Exception catch (e) {
        if (kDebugMode) debugPrint('[Relay] stream broken: $e');
      }
      await req.response.close();
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[Relay] $e');
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      } catch (_) {}
    } finally {
      client.close(force: false);
    }
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

}
