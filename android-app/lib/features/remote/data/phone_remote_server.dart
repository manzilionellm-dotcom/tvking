// =========================================================
//  phone_remote_server.dart — Mini-serveur de la télécommande
// =========================================================
//  POURQUOI UN SERVEUR DANS LA BOX (et pas le Worker Cloudflare) :
//  le téléphone et la box sont dans le salon, sur le même Wi-Fi.
//  Faire voyager « monter le volume » par Internet ajouterait un
//  compte, un serveur, et une porte de plus. Ici, la page et les
//  commandes ne quittent pas la maison. Rien n'est déployé.
//
//  CE QUE LE SERVEUR ACCEPTE
//    GET  /r/<jeton>/         la page (sans le jeton dedans)
//    POST /r/<jeton>/pair     le premier téléphone s'appaire
//    POST /r/<jeton>/cmd      une commande de la liste fermée
//    GET  /r/<jeton>/status   secondes restantes (ne prolonge pas)
//
//  CE QU'IL REFUSE
//    • toute autre adresse (pas de fichier, pas de proxy, pas de
//      page d'accueil) ;
//    • une commande tant que personne n'a appairé ;
//    • un deuxième téléphone ;
//    • un jeton expiré ou inconnu ;
//    • un client dont l'adresse IP n'est pas privée (pas Internet) ;
//    • un en-tête Host qui n'est pas l'adresse de la box (rebinding
//      DNS : un site web qui se fait passer pour la box) ;
//    • un Origin d'un autre site ;
//    • une rafale (plafond par seconde).
//
//  Aucun en-tête Access-Control-Allow-Origin : un site ouvert dans
//  le téléphone ne peut pas lire ni piloter la box.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../domain/lan_ipv4.dart';
import '../domain/remote_command.dart';
import '../domain/remote_session.dart';
import '../domain/remote_token.dart';
import 'remote_page.dart';

/// Corps maximum d'une requête. Largement assez pour un texte de
/// [kRemoteTextMax] caractères, ridicule pour un abus.
const int kRemoteMaxBodyBytes = 2048;

final ContentType _jsonType =
    ContentType('application', 'json', charset: 'utf-8');
final ContentType _htmlType = ContentType('text', 'html', charset: 'utf-8');

class _BodyTooLarge implements Exception {}

class _RemoteRateLimit {
  _RemoteRateLimit(
      {required this.maxPerSecond, required DateTime Function() clock})
      : _clock = clock;

  final int maxPerSecond;
  final DateTime Function() _clock;
  int _window = -1;
  int _count = 0;

  bool allow() {
    final int sec = _clock().millisecondsSinceEpoch ~/ 1000;
    if (sec != _window) {
      _window = sec;
      _count = 0;
    }
    _count += 1;
    return _count <= maxPerSecond;
  }

  void reset() {
    _window = -1;
    _count = 0;
  }
}

class PhoneRemoteServer {
  PhoneRemoteServer._({
    required HttpServer http,
    required InternetAddress address,
    required bool allowLoopback,
    required DateTime Function() clock,
    required int maxPerSecond,
    required this.onCommand,
  })  : _http = http,
        _address = address,
        _allowLoopback = allowLoopback,
        _clock = clock,
        _limit = _RemoteRateLimit(maxPerSecond: maxPerSecond, clock: clock),
        _session = RemoteSession.issue(clock: clock);

  /// [allowLoopback] doit rester FAUX sur la box. Les tests le passent
  /// à vrai uniquement pour parler à 127.0.0.1.
  static Future<PhoneRemoteServer> bind(
    InternetAddress address, {
    bool allowLoopback = false,
    DateTime Function()? clock,
    int maxPerSecond = 25,
    int port = 0,
    required Future<void> Function(RemoteCommand command) onCommand,
  }) async {
    final HttpServer http = await HttpServer.bind(address, port);
    final PhoneRemoteServer server = PhoneRemoteServer._(
      http: http,
      address: address,
      allowLoopback: allowLoopback,
      clock: clock ?? DateTime.now,
      maxPerSecond: maxPerSecond,
      onCommand: onCommand,
    );
    http.listen(server._onRequest, onError: (Object _) {
      debugPrint('[remote] connexion ignorée');
    });
    debugPrint('[remote] en écoute sur le réseau local, port ${http.port}');
    return server;
  }

  final Future<void> Function(RemoteCommand command) onCommand;

  HttpServer? _http;
  final InternetAddress _address;
  final bool _allowLoopback;
  final DateTime Function() _clock;
  final _RemoteRateLimit _limit;
  RemoteSession _session;

  bool get isRunning => _http != null;
  int get port => _http?.port ?? 0;
  String get ip => _address.address;
  String get token => _session.token;
  bool get isExpired => _session.isExpired;
  bool get isPaired => _session.isPaired;
  int get secondsLeft => _session.secondsLeft;

  /// Adresse complète du QR. Le jeton est dans le chemin, pas dans
  /// un paramètre (il n'apparaît pas non plus dans la page HTML).
  String get url => 'http://$ip:$port/r/$token/';

  /// Nouveau jeton, plus aucun téléphone. L'ancien QR meurt tout de suite.
  void rotate() {
    _session = RemoteSession.issue(clock: _clock);
    _limit.reset();
  }

  Future<void> close() async {
    final HttpServer? http = _http;
    _http = null;
    await http?.close(force: true);
  }

  void _onRequest(HttpRequest req) {
    unawaited(_handle(req));
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      await _dispatch(req);
    } catch (_) {
      debugPrint('[remote] requête refusée');
      try {
        await _send(req, 400);
      } catch (_) {}
    }
  }

  Future<void> _dispatch(HttpRequest req) async {
    // 1) Lire le corps MAINTENANT (plafond serré). Si on répondait
    //    avant de le lire, le téléphone et la box s'attendraient
    //    mutuellement (l'un écrit, l'autre ne lit pas).
    List<int> body = const <int>[];
    if (req.method == 'POST') {
      try {
        body = await _readLimited(req);
      } on _BodyTooLarge {
        await _send(req, 413);
        return;
      } catch (_) {
        await _send(req, 400);
        return;
      }
    }

    // 2) Pas Internet. Un routeur qui transfère le port vers la box
    //    verrait arriver une adresse publique : on la refuse.
    final InternetAddress? client = req.connectionInfo?.remoteAddress;
    if (client == null ||
        !remoteClientAllowed(client, allowLoopback: _allowLoopback)) {
      await _send(req, 403);
      return;
    }

    // 3) L'en-tête Host doit être NOTRE adresse. Sinon un site web
    //    peut, par DNS menteur, faire croire au téléphone qu'il parle
    //    à la box alors qu'il parle à l'attaquant — ou l'inverse.
    if (!_hostOk(req)) {
      await _send(req, 400);
      return;
    }

    // 4) Un autre site (Origin) n'a rien à faire ici.
    if (!_originOk(req)) {
      await _send(req, 403);
      return;
    }

    // 5) Plafond : une télécommande humaine reste en dessous,
    //    un script qui mitraille non.
    if (!_limit.allow()) {
      await _send(req, 429, retryAfter: '1');
      return;
    }

    final _Route? route = _route(req.uri.path);
    if (route == null) {
      await _send(req, 404, bytes: _notFound, type: _htmlType);
      return;
    }
    if (route.tokenMismatch) {
      await _send(req, 404, bytes: _notFound, type: _htmlType);
      return;
    }
    if (route.redirect) {
      // Chemin relatif uniquement : jamais une adresse externe.
      await _send(req, 302, location: '/r/$token/');
      return;
    }
    if (_session.isExpired) {
      await _send(
        req,
        410,
        bytes: route.kind == _Kind.page ? _expired : null,
        type: route.kind == _Kind.page ? _htmlType : null,
      );
      return;
    }

    switch (route.kind) {
      case _Kind.page:
        if (req.method != 'GET' && req.method != 'HEAD') {
          await _send(req, 405);
          return;
        }
        await _send(req, 200, bytes: _pageBytes, type: _htmlType);
      case _Kind.status:
        if (req.method != 'GET') {
          await _send(req, 405);
          return;
        }
        if (!_session.matches(_phoneCookie(req))) {
          await _send(req, 401);
          return;
        }
        await _send(req, 200,
            bytes: utf8.encode(_statusJson()), type: _jsonType);
      case _Kind.pair:
        if (!_postOk(req)) {
          await _send(req, 400);
          return;
        }
        await _pair(req);
      case _Kind.cmd:
        if (!_postOk(req)) {
          await _send(req, 400);
          return;
        }
        await _cmd(req, body);
    }
  }

  Future<void> _pair(HttpRequest req) async {
    final String? presented = _phoneCookie(req);
    if (_session.isPaired) {
      if (!_session.matches(presented)) {
        await _send(req, 403);
        return;
      }
      await _send(req, 200, bytes: utf8.encode(_leftJson()), type: _jsonType);
      return;
    }
    // Secret choisi PAR LA BOX, pas par le téléphone (sinon il pourrait
    // imposer un cookie qu'il connaît déjà).
    final String secret = newRemoteToken();
    if (_session.pairNewPhone(secret) == null) {
      await _send(req, 403);
      return;
    }
    await _send(
      req,
      200,
      bytes: utf8.encode(_leftJson()),
      type: _jsonType,
      setCookie: _setCookie(secret),
    );
  }

  Future<void> _cmd(HttpRequest req, List<int> body) async {
    // Aucune commande sans appairage, même avec le bon jeton dans l'adresse.
    if (!_session.matches(_phoneCookie(req))) {
      await _send(req, 401);
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(body));
    } catch (_) {
      await _send(req, 400);
      return;
    }
    final RemoteCommand? command = parseRemoteCommand(decoded);
    if (command == null) {
      await _send(req, 400);
      return;
    }
    try {
      await onCommand(command);
    } catch (_) {
      debugPrint('[remote] commande non appliquée');
    }
    await _send(req, 200, bytes: utf8.encode('{"ok":true}'), type: _jsonType);
  }

  bool _hostOk(HttpRequest req) {
    final String? host = req.headers.value(HttpHeaders.hostHeader);
    if (host == null) return false;
    return host.trim().toLowerCase() == '$ip:$port';
  }

  bool _originOk(HttpRequest req) {
    final String? origin = req.headers.value('origin');
    if (origin == null || origin.isEmpty || origin == 'null') return true;
    return origin.toLowerCase() == 'http://$ip:$port';
  }

  /// POST : JSON + en-tête que seul NOTRE script ajoute. Un formulaire
  /// d'un autre site ne peut pas poser cet en-tête sans un accord CORS,
  /// et on n'accorde jamais CORS.
  bool _postOk(HttpRequest req) {
    if (req.method != 'POST') return false;
    if (req.headers.value('x-zuno-remote') != '1') return false;
    final String? mime = req.headers.contentType?.mimeType;
    return mime == 'application/json';
  }

  String? _phoneCookie(HttpRequest req) {
    for (final Cookie cookie in req.cookies) {
      if (cookie.name == 'zuno_phone') return cookie.value;
    }
    return null;
  }

  String _setCookie(String secret) {
    return 'zuno_phone=$secret; HttpOnly; SameSite=Strict; '
        'Path=/r/$token/; Max-Age=$secondsLeft';
  }

  String _leftJson() => '{"ok":true,"left":$secondsLeft}';

  String _statusJson() => '{"ok":true,"paired":true,"left":$secondsLeft}';

  _Route? _route(String path) {
    if (path.contains('..') || path.contains('\\')) return null;
    final RegExpMatch? m =
        RegExp(r'^/r/([0-9a-f]{32})(/.*)?$').firstMatch(path);
    if (m == null) return null;
    final String presented = m.group(1)!;
    if (!constantTimeEquals(presented, token)) {
      return const _Route.mismatch();
    }
    final String? suffix = m.group(2);
    if (suffix == null) return const _Route.redirect();
    switch (suffix) {
      case '/':
        return const _Route(_Kind.page);
      case '/status':
        return const _Route(_Kind.status);
      case '/pair':
        return const _Route(_Kind.pair);
      case '/cmd':
        return const _Route(_Kind.cmd);
      default:
        return null;
    }
  }

  Future<List<int>> _readLimited(HttpRequest req) async {
    // On CONSOMME le corps avant de répondre, sinon le téléphone
    // (qui écrit) et la box (qui répond sans lire) se bloquent.
    // Au-delà du plafond on jette les octets, sans jamais en garder
    // plus de 64 Ko en mémoire.
    final BytesBuilder out = BytesBuilder(copy: false);
    var seen = 0;
    var tooBig = false;
    await for (final List<int> chunk
        in req.timeout(const Duration(seconds: 3))) {
      seen += chunk.length;
      if (seen > kRemoteMaxBodyBytes) {
        tooBig = true;
        if (seen > 65536) break;
        continue;
      }
      out.add(chunk);
    }
    if (tooBig) throw _BodyTooLarge();
    return out.takeBytes();
  }

  void _securityHeaders(HttpResponse res) {
    res.headers.set('X-Content-Type-Options', 'nosniff');
    res.headers.set('Referrer-Policy', 'no-referrer');
    res.headers.set('X-Frame-Options', 'DENY');
    res.headers.set(
      'Content-Security-Policy',
      "default-src 'none'; style-src 'unsafe-inline'; "
          "script-src 'unsafe-inline'; img-src 'none'; connect-src 'self'; "
          "form-action 'none'; base-uri 'none'; frame-ancestors 'none'",
    );
    res.headers.set('Cache-Control', 'no-store');
    // Volontairement AUCUN Access-Control-Allow-Origin.
  }

  Future<void> _send(
    HttpRequest req,
    int status, {
    List<int>? bytes,
    ContentType? type,
    String? setCookie,
    String? location,
    String? retryAfter,
  }) async {
    final HttpResponse res = req.response;
    res.persistentConnection = false;
    res.statusCode = status;
    _securityHeaders(res);
    if (type != null) res.headers.contentType = type;
    if (setCookie != null) {
      res.headers.add(HttpHeaders.setCookieHeader, setCookie);
    }
    if (location != null) {
      res.headers.set(HttpHeaders.locationHeader, location);
    }
    if (retryAfter != null) res.headers.set('Retry-After', retryAfter);
    if (bytes != null && bytes.isNotEmpty) res.add(bytes);
    await res.close();
  }
}

enum _Kind { page, status, pair, cmd }

class _Route {
  const _Route(this.kind)
      : redirect = false,
        tokenMismatch = false;
  const _Route.redirect()
      : kind = _Kind.page,
        redirect = true,
        tokenMismatch = false;
  const _Route.mismatch()
      : kind = _Kind.page,
        redirect = false,
        tokenMismatch = true;

  final _Kind kind;
  final bool redirect;
  final bool tokenMismatch;
}

final List<int> _pageBytes = utf8.encode(remoteControlPageHtml());

final List<int> _expired = utf8.encode(
  '<!doctype html><meta charset="utf-8"><title>Zuno</title>'
  '<p>Code expiré. Regarde l’écran de la box.</p>',
);

final List<int> _notFound = utf8.encode(
  '<!doctype html><meta charset="utf-8"><title>Zuno</title>'
  '<p>Page introuvable.</p>',
);
