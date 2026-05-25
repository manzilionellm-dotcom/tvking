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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class LocalCastServer {
  LocalCastServer._();
  static final LocalCastServer instance = LocalCastServer._();

  HttpServer? _server;
  String? _currentUrl;
  String? _currentTitle;
  int _port = 0;

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
    _currentUrl = null;
    _currentTitle = null;
  }

  /// Met à jour le flux courant. Le HTML appelle GET /current toutes
  /// les 2s ; dès qu'on change l'URL, la page recharge la vidéo.
  void setCurrent({required String url, required String title}) {
    _currentUrl = url;
    _currentTitle = title;
  }

  String? get currentUrl => _currentUrl;
  String? get currentTitle => _currentTitle;
  int get port => _port;
  bool get isRunning => _server != null;

  // ============================================================
  //  Handlers
  // ============================================================

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final String path = req.uri.path;
      if (path == '/' || path == '/index.html') {
        await _serveHtml(req);
        return;
      }
      if (path == '/current') {
        await _serveCurrentJson(req);
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

  Future<void> _serveHtml(HttpRequest req) async {
    req.response.headers.contentType =
        ContentType('text', 'html', charset: 'utf-8');
    req.response.headers
        .set('Cache-Control', 'no-store, no-cache, must-revalidate');
    req.response.write(_buildPlayerHtml());
    await req.response.close();
  }

  Future<void> _serveCurrentJson(HttpRequest req) async {
    req.response.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.write(jsonEncode(<String, dynamic>{
      'url': _currentUrl,
      'title': _currentTitle,
    }));
    await req.response.close();
  }

  // ============================================================
  //  Page HTML5 player
  // ============================================================

  String _buildPlayerHtml() {
    // hls.js et mpegts.js sont chargés depuis le CDN jsDelivr — léger
    // et toujours à jour. La TV doit avoir une connexion internet
    // (ce qui est de toute façon le cas vu qu'elle va lire un flux IPTV).
    return r'''
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <title>7 MOTION — Cast</title>
  <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.13/dist/hls.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/mpegts.js@1.7.3/dist/mpegts.min.js"></script>
  <style>
    html, body {
      margin: 0; padding: 0; background: #000; color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      height: 100%; overflow: hidden;
    }
    #stage {
      position: fixed; inset: 0; display: flex;
      align-items: center; justify-content: center; background: #000;
    }
    video {
      width: 100%; height: 100%; background: #000; object-fit: contain;
    }
    #empty {
      position: absolute; inset: 0; display: flex;
      flex-direction: column; align-items: center; justify-content: center;
      gap: 16px; padding: 32px; text-align: center;
    }
    #empty.hidden { display: none; }
    #logo {
      width: 88px; height: 88px; border-radius: 18px;
      background: #050507;
      border: 1px solid rgba(255,90,74,0.35);
      box-shadow: 0 0 32px rgba(255,90,74,0.35);
      display: flex; align-items: center; justify-content: center;
      font-size: 48px; font-weight: 800; color: #D63A30;
      letter-spacing: -2px;
    }
    h1 { margin: 0; font-size: 22px; letter-spacing: 4px; font-weight: 700; color: #F0EDE9; }
    p { margin: 0; opacity: 0.7; font-size: 14px; max-width: 480px; line-height: 1.5; color: #B6B0A8; }
    #title {
      position: absolute; top: 0; left: 0; right: 0;
      padding: 14px 20px;
      background: linear-gradient(to bottom, rgba(0,0,0,0.7), transparent);
      font-size: 16px; font-weight: 700;
      opacity: 0; transition: opacity 0.4s ease;
      pointer-events: none;
    }
    #title.show { opacity: 1; }
    #err {
      position: absolute; bottom: 24px; left: 24px; right: 24px;
      padding: 12px 16px; background: rgba(255,71,87,0.95);
      border-radius: 10px; font-size: 13px;
      display: none;
    }
    #err.show { display: block; }
  </style>
</head>
<body>
<div id="stage">
  <div id="empty">
    <div id="logo">7</div>
    <h1>7 MOTION</h1>
    <p>En attente d'une chaîne… Lance n'importe quelle chaîne depuis ton téléphone, elle apparaîtra ici dans 2 secondes.</p>
  </div>
  <video id="v" playsinline autoplay controls></video>
  <div id="title"></div>
  <div id="err"></div>
</div>
<script>
(function() {
  var v = document.getElementById('v');
  var empty = document.getElementById('empty');
  var titleEl = document.getElementById('title');
  var errEl = document.getElementById('err');
  var currentUrl = null;
  var hls = null;
  var mpegts = null;

  function showError(msg) {
    errEl.textContent = msg;
    errEl.classList.add('show');
    setTimeout(function () { errEl.classList.remove('show'); }, 5000);
  }

  function setTitle(t) {
    if (!t) { titleEl.classList.remove('show'); return; }
    titleEl.textContent = t;
    titleEl.classList.add('show');
    setTimeout(function () { titleEl.classList.remove('show'); }, 4000);
  }

  function destroyPlayers() {
    try { if (hls) { hls.destroy(); hls = null; } } catch (e) {}
    try { if (mpegts) { mpegts.destroy(); mpegts = null; } } catch (e) {}
  }

  function play(url, title) {
    destroyPlayers();
    empty.classList.add('hidden');
    setTitle(title || '');
    var lower = url.toLowerCase();
    var isHls = lower.indexOf('.m3u8') !== -1;
    var isTs  = lower.indexOf('.ts')   !== -1 || lower.indexOf('mpeg') !== -1;

    if (isHls && window.Hls && window.Hls.isSupported()) {
      hls = new window.Hls({ liveDurationInfinity: true });
      hls.loadSource(url);
      hls.attachMedia(v);
      hls.on(window.Hls.Events.ERROR, function (e, d) {
        if (d.fatal) showError('HLS: ' + d.type + ' — ' + (d.details||''));
      });
    } else if (isTs && window.mpegts && window.mpegts.isSupported()) {
      mpegts = window.mpegts.createPlayer({ type: 'mpegts', url: url, isLive: true });
      mpegts.attachMediaElement(v);
      mpegts.load();
      mpegts.play().catch(function (e) { showError('TS: ' + e.message); });
    } else {
      v.src = url;
      v.play().catch(function (e) { showError('Lecture refusée : ' + e.message); });
    }
  }

  // Polling de l'API /current — quand l'URL change, on lance la nouvelle vidéo.
  function poll() {
    fetch('/current', { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (data && data.url && data.url !== currentUrl) {
          currentUrl = data.url;
          play(data.url, data.title);
        } else if (!data || !data.url) {
          if (currentUrl !== null) {
            currentUrl = null;
            destroyPlayers();
            v.removeAttribute('src');
            v.load();
            empty.classList.remove('hidden');
          }
        }
      })
      .catch(function () { /* TV momentanément offline, on réessaie */ });
  }

  setInterval(poll, 2000);
  poll();
})();
</script>
</body>
</html>
''';
  }
}
