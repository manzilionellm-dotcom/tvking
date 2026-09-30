// =========================================================
//  remote_server_test.dart — Le serveur, comme le verrait un téléphone
// =========================================================
//  On parle à 127.0.0.1 (autorisé ICI seulement, parce que le test
//  n'a pas de Wi-Fi). Sur la box, cette autorisation est coupée :
//  un test plus bas le prouve.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/remote/data/phone_remote_server.dart';
import 'package:tv_king/features/remote/domain/remote_command.dart';
import 'package:tv_king/features/remote/domain/remote_token.dart';

void main() {
  late DateTime now;
  late List<RemoteCommand> done;
  late PhoneRemoteServer server;
  late _Probe phone;

  setUp(() async {
    now = DateTime.utc(2026, 9, 30, 12);
    done = <RemoteCommand>[];
    server = await PhoneRemoteServer.bind(
      InternetAddress.loopbackIPv4,
      allowLoopback: true,
      clock: () => now,
      maxPerSecond: 40,
      onCommand: (RemoteCommand c) async {
        done.add(c);
      },
    );
    phone = _Probe(server);
  });

  tearDown(() async {
    await server.close();
    phone.client.close(force: true);
  });

  test('la page s\'ouvre, sans le jeton dedans, et sans CORS', () async {
    final _Hit home = await phone.get('/');
    expect(home.status, 404);

    final _Hit page = await phone.get('/r/${server.token}/');
    expect(page.status, 200);
    expect(page.body, contains('Zuno'));
    expect(page.body.contains(server.token), isFalse);
    expect(page.body, isNot(contains('<script src')));
    expect(page.cors, isNull);

    final _Hit redir = await phone.get('/r/${server.token}');
    expect(redir.status, 302);
    expect(redir.location, '/r/${server.token}/');
    expect(redir.location, isNot(contains('://')));
  });

  test('aucune commande avant appairage, puis une seule, puis plus', () async {
    final _Hit early = await phone.post('/r/${server.token}/cmd', '{"a":"up"}');
    expect(early.status, 401);
    expect(done, isEmpty);
    final _Hit statusBefore = await phone.get('/r/${server.token}/status');
    expect(statusBefore.status, 401);

    final _Hit paired = await phone.post('/r/${server.token}/pair', '{}');
    expect(paired.status, 200);
    expect(paired.body, '{"ok":true,"left":${kRemoteSessionTtl.inSeconds}}');
    expect(paired.body.contains(server.token), isFalse);
    expect(paired.setCookie, contains('HttpOnly'));
    expect(paired.setCookie, contains('SameSite=Strict'));
    expect(paired.setCookie, isNot(contains('Secure')));
    final String secret = phone.cookie!.split('=').last;
    expect(paired.body.contains(secret), isFalse);
    expect(paired.cors, isNull);

    final _Hit up = await phone.post('/r/${server.token}/cmd', '{"a":"up"}');
    expect(up.status, 200);
    expect(up.body, '{"ok":true}');
    expect((done.single as RemotePress).button, RemoteButton.up);

    final _Hit stranger = await phone.post(
      '/r/${server.token}/cmd',
      '{"a":"down"}',
      withCookie: false,
    );
    expect(stranger.status, 401);
    expect(done, hasLength(1));

    // Le jeton de l'adresse, mis dans le cookie, ne suffit pas.
    final _Hit confused = await phone.post(
      '/r/${server.token}/cmd',
      '{"a":"ok"}',
      withCookie: false,
      cookieValue: 'zuno_phone=${server.token}',
    );
    expect(confused.status, 401);

    final _Probe other = _Probe(server);
    addTearDown(() => other.client.close(force: true));
    final _Hit stolen = await other.post('/r/${server.token}/pair', '{}');
    expect(stolen.status, 403);
    expect(done, hasLength(1));

    final _Hit still =
        await phone.post('/r/${server.token}/cmd', '{"a":"ch_up"}');
    expect(still.status, 200);
    expect((done.last as RemotePress).button, RemoteButton.channelUp);

    final _Hit stat = await phone.get('/r/${server.token}/status');
    expect(stat.status, 200);
    expect(stat.body, contains('"paired":true'));
    expect(stat.body.contains(server.token), isFalse);
  });

  test('texte transmis, pas renvoyé, et commandes inconnues ignorées',
      () async {
    await phone.post('/r/${server.token}/pair', '{}');
    final _Hit q = await phone.post(
      '/r/${server.token}/cmd',
      '{"a":"query","t":"secret-chaine"}',
    );
    expect(q.status, 200);
    expect(q.body, '{"ok":true}');
    expect(q.body, isNot(contains('secret')));
    expect((done.single as RemoteQuery).text, 'secret-chaine');

    final _Hit bad =
        await phone.post('/r/${server.token}/cmd', '{"a":"reboot"}');
    expect(bad.status, 400);
    expect(done, hasLength(1));

    final _Hit huge = await phone.post(
      '/r/${server.token}/cmd',
      '{"a":"query","t":"${'a' * (kRemoteTextMax + 1)}"}',
    );
    expect(huge.status, 400);
    expect(done, hasLength(1));
  });

  test('mauvais site, mauvais type, mauvaise adresse, trop gros', () async {
    await phone.post('/r/${server.token}/pair', '{}');

    final _Hit evil = await phone.post(
      '/r/${server.token}/cmd',
      '{"a":"ok"}',
      origin: 'http://evil.example',
    );
    expect(evil.status, 403);
    expect(evil.cors, isNull);
    expect(done, isEmpty);

    final _Hit plain = await phone.post(
      '/r/${server.token}/cmd',
      '{"a":"ok"}',
      contentType: 'text/plain',
    );
    expect(plain.status, 400);

    final _Hit noHeader = await phone.post(
      '/r/${server.token}/cmd',
      '{"a":"ok"}',
      remoteHeader: false,
    );
    expect(noHeader.status, 400);
    expect(done, isEmpty);

    final _Hit fat = await phone.post(
      '/r/${server.token}/cmd',
      'x' * 3000,
    );
    expect(fat.status, 413);
    expect(done, isEmpty);

    final String wrong = 'ab' * 16;
    final _Hit miss = await phone.post('/r/$wrong/cmd', '{"a":"up"}');
    expect(miss.status, 404);

    final String options = await _raw(
      server.port,
      'OPTIONS /r/${server.token}/cmd HTTP/1.1\r\n'
      'Host: 127.0.0.1:${server.port}\r\n'
      'Origin: http://evil.example\r\n'
      'Access-Control-Request-Method: POST\r\n'
      'Connection: close\r\n\r\n',
    );
    expect(
        options.toLowerCase(), isNot(contains('access-control-allow-origin')));
    expect(options, isNot(contains(' 200 ')));

    final String spoof = await _raw(
      server.port,
      'POST /r/${server.token}/cmd HTTP/1.1\r\n'
      'Host: evil.example\r\n'
      'Content-Type: application/json\r\n'
      'X-Zuno-Remote: 1\r\n'
      'Content-Length: 10\r\n'
      'Connection: close\r\n\r\n'
      '{"a":"up"}',
    );
    expect(spoof, contains('400'));
    expect(done, isEmpty);

    final String traversal = await _raw(
      server.port,
      'GET /r/../../etc/passwd HTTP/1.1\r\n'
      'Host: 127.0.0.1:${server.port}\r\n'
      'Connection: close\r\n\r\n',
    );
    expect(traversal, contains('404'));
  });

  test('nouveau code et expiration tuent l\'ancien téléphone', () async {
    await phone.post('/r/${server.token}/pair', '{}');
    final String old = server.token;
    final String? oldCookie = phone.cookie;
    server.rotate();
    expect(server.token, isNot(old));
    // rotate() a lu l'horloge AVANT qu'on l'avance : la nouvelle session
    // naît maintenant, puis on la fait expirer plus bas.

    final _Hit dead = await phone.post(
      '/r/$old/cmd',
      '{"a":"up"}',
      cookieValue: oldCookie,
    );
    expect(dead.status, 404);
    expect(done, isEmpty);

    now = now.add(kRemoteSessionTtl);
    expect(server.isExpired, isTrue);
    final _Hit late = await phone.post('/r/${server.token}/pair', '{}');
    expect(late.status, 410);
    final _Hit page = await phone.get('/r/${server.token}/');
    expect(page.status, 410);
    expect(page.body, contains('expir'));
    expect(page.body.contains(server.token), isFalse);
  });

  test('sur la box, 127.0.0.1 n\'est pas un téléphone', () async {
    final PhoneRemoteServer locked = await PhoneRemoteServer.bind(
      InternetAddress.loopbackIPv4,
      allowLoopback: false,
      clock: () => now,
      onCommand: (RemoteCommand c) async {
        done.add(c);
      },
    );
    addTearDown(locked.close);
    final _Probe local = _Probe(locked);
    addTearDown(local.client.close);
    final _Hit hit = await local.get('/r/${locked.token}/');
    expect(hit.status, 403);
    expect(done, isEmpty);
  });

  test('au-delà du plafond, la commande n\'est pas exécutée', () async {
    final PhoneRemoteServer tight = await PhoneRemoteServer.bind(
      InternetAddress.loopbackIPv4,
      allowLoopback: true,
      clock: () => now,
      maxPerSecond: 2,
      onCommand: (RemoteCommand c) async {
        done.add(c);
      },
    );
    addTearDown(tight.close);
    final _Probe p = _Probe(tight);
    addTearDown(p.client.close);
    expect((await p.post('/r/${tight.token}/pair', '{}')).status, 200);
    expect((await p.post('/r/${tight.token}/cmd', '{"a":"up"}')).status, 200);
    final _Hit blocked = await p.post('/r/${tight.token}/cmd', '{"a":"down"}');
    expect(blocked.status, 429);
    expect(done, hasLength(1));
  });
}

class _Hit {
  _Hit(this.status, this.body, this.cors, this.setCookie, this.location);
  final int status;
  final String body;
  final String? cors;
  final String? setCookie;
  final String? location;
}

class _Probe {
  _Probe(this.server);
  final PhoneRemoteServer server;
  final HttpClient client = HttpClient();
  String? cookie;

  Future<_Hit> get(String path) async {
    final HttpClientRequest req = await client.getUrl(_uri(path));
    req.followRedirects = false;
    if (cookie != null) req.headers.set(HttpHeaders.cookieHeader, cookie!);
    return _finish(req);
  }

  Future<_Hit> post(
    String path,
    String body, {
    bool withCookie = true,
    String? origin,
    String contentType = 'application/json',
    bool remoteHeader = true,
    String? cookieValue,
  }) async {
    final HttpClientRequest req = await client.postUrl(_uri(path));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.contentTypeHeader, contentType);
    if (remoteHeader) req.headers.set('X-Zuno-Remote', '1');
    if (origin != null) req.headers.set('origin', origin);
    final String? c = cookieValue ?? (withCookie ? cookie : null);
    if (c != null) req.headers.set(HttpHeaders.cookieHeader, c);
    final List<int> bytes = utf8.encode(body);
    req.contentLength = bytes.length;
    req.add(bytes);
    return _finish(req);
  }

  Uri _uri(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  Future<_Hit> _finish(HttpClientRequest req) async {
    final HttpClientResponse resp = await req.close();
    final List<int> bytes =
        await resp.fold<List<int>>(<int>[], (List<int> a, List<int> b) {
      a.addAll(b);
      return a;
    });
    final List<String>? setCookie = resp.headers[HttpHeaders.setCookieHeader];
    if (setCookie != null && setCookie.isNotEmpty) {
      cookie = setCookie.first.split(';').first.trim();
    }
    return _Hit(
      resp.statusCode,
      utf8.decode(bytes),
      resp.headers.value('access-control-allow-origin'),
      setCookie?.first,
      resp.headers.value(HttpHeaders.locationHeader),
    );
  }
}

Future<String> _raw(int port, String request) async {
  final Socket socket =
      await Socket.connect(InternetAddress.loopbackIPv4, port);
  socket.write(request);
  await socket.flush();
  final List<int> bytes = <int>[];
  final Completer<void> done = Completer<void>();
  final StreamSubscription<List<int>> sub = socket.listen(
    bytes.addAll,
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    onError: (Object _) {
      if (!done.isCompleted) done.complete();
    },
  );
  try {
    await done.future.timeout(const Duration(seconds: 3));
  } on TimeoutException {
    // La réponse est déjà dans [bytes] : on n'attend pas plus.
  }
  await sub.cancel();
  await socket.close();
  return utf8.decode(bytes, allowMalformed: true);
}
