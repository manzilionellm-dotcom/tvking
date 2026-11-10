import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_king/features/subscription/data/device_realtime_channel.dart';

const _mac = 'MK:11:22:33:44:55';
const _otherMac = 'MK:11:22:33:44:66';
const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _credentials = DeviceRealtimeCredentials(
  deviceKey: _key,
  deviceId: 'fixture-android-id',
);

class _Socket extends Stream<dynamic> implements WebSocket {
  final _incoming = StreamController<dynamic>();
  final List<dynamic> sent = <dynamic>[];
  bool closed = false;

  void emit(Map<String, Object?> frame) => _incoming.add(jsonEncode(frame));

  @override
  void add(dynamic data) => sent.add(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    if (closed) return;
    closed = true;
    // close() ne doit pas attendre un listener qui n'a jamais été posé
    // dans le cas testé de l'ouverture arrivée après stop/timeout.
    unawaited(_incoming.close());
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _incoming.stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fixture {
  final requests = <http.Request>[];
  final sockets = <_Socket>[];
  final uris = <Uri>[];
  final wakes = <DeviceRealtimeWake>[];
  final connections = <bool>[];
  int tickets = 0;

  late final client = MockClient((request) async {
    requests.add(request);
    if (request.url.path.startsWith('/api/status/')) {
      return http.Response('{"device_token":"fixture.payload.signature"}', 200);
    }
    tickets++;
    return http.Response(
        jsonEncode(<String, String>{
          'ticket':
              '00000000-0000-0000-0000-${tickets.toString().padLeft(12, '0')}',
        }),
        200);
  });

  DeviceRealtimeChannel channel({
    FutureOr<void> Function(DeviceRealtimeWake)? onWake,
    Duration helloInterval = const Duration(seconds: 25),
  }) =>
      DeviceRealtimeChannel(
        mac: _mac,
        credentialProvider: () async => _credentials,
        alive: () => true,
        onWake: onWake ?? wakes.add,
        onConnectionChanged: connections.add,
        client: client,
        baseUrl: 'https://panel.example.test',
        retryDelay: const Duration(milliseconds: 5),
        maxRetryDelay: const Duration(milliseconds: 10),
        helloInterval: helloInterval,
        connect: (uri) async {
          uris.add(uri);
          final socket = _Socket();
          sockets.add(socket);
          return socket;
        },
      );
}

Future<void> _until(bool Function() condition) async {
  final limit = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(limit)) fail('Condition locale non satisfaite');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Map<String, Object?> _frame(int version, String kind, {String? mac}) =>
    <String, Object?>{
      'v': 1,
      'type': kind,
      'version': version,
      if (mac != null) 'mac': mac,
    };

void main() {
  test('contrat v1 : réveils globaux/ciblés, MAC et révision strictes', () {
    final global =
        parseDeviceRealtimeWake(jsonEncode(_frame(4, 'theme')), mac: _mac)!;
    expect(global.kinds, <String>{'theme'});
    expect(global.revisions, <String, int>{'theme': 4});
    expect(global.resync, isFalse);
    expect(
        parseDeviceRealtimeWake(jsonEncode(_frame(5, 'source', mac: _mac)),
            mac: _mac),
        isNotNull);
    for (final invalid in <Object?>[
      null,
      <Object>[],
      _frame(6, 'source', mac: _otherMac),
      <String, Object?>{..._frame(7, 'theme'), 'mac': null},
      _frame(0, 'theme'),
      _frame(8, 'unknown'),
      _frame(8, 'hello'),
      <String, Object?>{..._frame(8, 'theme'), 'v': 2},
      <String, Object?>{..._frame(8, 'theme'), 'version': '8'},
      <String, Object?>{..._frame(8, 'theme'), 'version': 8.5},
      <String, Object?>{'v': 1, 'type': 'theme', 'seq': 8},
    ]) {
      expect(parseDeviceRealtimeWake(jsonEncode(invalid), mac: _mac), isNull);
    }
    expect(parseDeviceRealtimeWake('{', mac: _mac), isNull);
    expect(() => global.kinds.add('reset'), throwsUnsupportedError);
    expect(() => global.revisions['theme'] = 99, throwsUnsupportedError);
  });

  test('chaque étape transporte seulement ses preuves, sans redirect',
      () async {
    final fixture = _Fixture();
    final channel = fixture.channel();
    final running = channel.run();
    addTearDown(() async {
      channel.stop();
      await running;
    });
    await _until(() => channel.open);

    expect(fixture.requests, hasLength(2));
    final status = fixture.requests[0];
    expect(status.method, 'GET');
    expect(status.url.path, '/api/status/${Uri.encodeComponent(_mac)}');
    expect(status.headers['X-Device-Key'], _key);
    expect(status.headers['X-Device-Id'], 'fixture-android-id');
    expect(status.headers.containsKey('Authorization'), isFalse);
    final ticket = fixture.requests[1];
    expect(ticket.method, 'POST');
    expect(ticket.url.path, '/api/device-rt/ticket');
    expect(ticket.body, isEmpty);
    expect(ticket.headers['Authorization'], 'Bearer fixture.payload.signature');
    expect(ticket.headers.containsKey('X-Device-Key'), isFalse);
    expect(ticket.headers.containsKey('X-Device-Id'), isFalse);
    expect(
        fixture.requests.every((request) => !request.followRedirects), isTrue);
    expect(fixture.uris.single.scheme, 'wss');
    expect(fixture.uris.single.host, 'panel.example.test');
    expect(fixture.uris.single.path, '/api/device-rt/ws');
    expect(fixture.uris.single.queryParameters.keys, <String>['ticket']);
    expect(fixture.wakes.single.resync, isTrue);
    expect(fixture.connections, <bool>[true]);
  });

  test('une importation bloquée ne retient ni suspension ni déduplication',
      () async {
    final fixture = _Fixture();
    final importDone = Completer<void>();
    final channel = fixture.channel(onWake: (wake) async {
      fixture.wakes.add(wake);
      if (wake.kinds.contains('source')) await importDone.future;
    });
    final running = channel.run();
    addTearDown(() async {
      importDone.complete();
      channel.stop();
      await running;
    });
    await _until(() => channel.open);
    final socket = fixture.sockets.single;
    socket.emit(_frame(100, 'theme', mac: _otherMac));
    socket.emit(_frame(1, 'source', mac: _mac));
    socket.emit(_frame(1, 'source', mac: _mac));
    socket.emit(_frame(2, 'suspend', mac: _mac));
    socket.emit(_frame(1, 'theme'));
    await _until(() => fixture.wakes.length == 3);
    expect(
        fixture.wakes
            .where((wake) => !wake.resync)
            .map((wake) => wake.kinds.single),
        <String>['source', 'suspend']);
    expect(importDone.isCompleted, isFalse);
  });

  test('reconnexion : nouveau ticket, resync et compteur serveur plus bas',
      () async {
    final fixture = _Fixture();
    final channel =
        fixture.channel(helloInterval: const Duration(milliseconds: 5));
    final running = channel.run();
    addTearDown(() async {
      channel.stop();
      await running;
    });
    await _until(() => channel.open);
    fixture.sockets.first.emit(_frame(50, 'theme'));
    await _until(() => fixture.wakes.length == 2);
    await _until(() => fixture.sockets.first.sent.isNotEmpty);
    expect(jsonDecode(fixture.sockets.first.sent.first as String)['type'],
        'hello');
    await fixture.sockets.first.close(4001, 'session_expired');
    await _until(() => fixture.sockets.length == 2 && channel.open);
    fixture.sockets.last.emit(_frame(1, 'theme'));
    await _until(() => fixture.wakes.length == 4);
    expect(fixture.tickets, 2);
    expect(fixture.uris[0].query, isNot(fixture.uris[1].query));
    expect(fixture.wakes.where((wake) => wake.resync), hasLength(2));
    expect(fixture.wakes.last.revisions, <String, int>{'theme': 1});
    expect(fixture.connections, <bool>[true, false, true]);
    channel.stop();
    await running;
    expect(fixture.connections.last, isFalse);
    expect(fixture.sockets.last.closed, isTrue);
  });

  test(
      'clé refusée, token absent ou redirect : aucune ouverture ni réenrôlement',
      () async {
    for (final response in <http.Response>[
      http.Response('{}', 401),
      http.Response('{}', 403),
      http.Response('{"status":"active"}', 200),
      http.Response('', 302,
          headers: <String, String>{'location': 'https://elsewhere.test'}),
    ]) {
      var requests = 0;
      var connections = 0;
      late DeviceRealtimeChannel channel;
      final client = MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        expect(request.followRedirects, isFalse);
        return response;
      });
      channel = DeviceRealtimeChannel(
        mac: _mac,
        credentialProvider: () async => _credentials,
        alive: () => true,
        onWake: (_) => fail('Aucun réveil sans authentification'),
        client: client,
        retryDelay: const Duration(hours: 1),
        connect: (_) async {
          connections++;
          return _Socket();
        },
      );
      final running = channel.run();
      await _until(() => requests == 1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(requests, 1);
      expect(connections, 0);
      channel.stop();
      await running;
      client.close();
    }
  });

  test('stop ferme une ouverture tardive et ne relance pas de connexion',
      () async {
    final fixture = _Fixture();
    final delayedSocket = Completer<WebSocket>();
    final connecting = Completer<void>();
    final socket = _Socket();
    final channel = DeviceRealtimeChannel(
      mac: _mac,
      credentialProvider: () async => _credentials,
      alive: () => true,
      onWake: (_) => fail('Veille arrêtée'),
      client: fixture.client,
      connect: (_) {
        connecting.complete();
        return delayedSocket.future;
      },
    );
    final running = channel.run();
    await connecting.future;
    channel.stop();
    delayedSocket.complete(socket);
    await running;
    expect(socket.closed, isTrue);
    expect(channel.open, isFalse);
    expect(fixture.tickets, 1);
  });
}
