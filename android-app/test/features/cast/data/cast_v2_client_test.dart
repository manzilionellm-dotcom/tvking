import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_v2_client.dart';
import 'package:tv_king/features/cast/data/cast_v2_codec.dart';

void main() {
  late ServerSocket server;
  final List<Socket> peers = <Socket>[];
  late List<CastV2Message> received;
  late CastV2Client client;
  bool reject = false, buffering = false, drop = false;
  setUp(() async {
    reject = false;
    buffering = false;
    drop = false;
    received = <CastV2Message>[];
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((Socket s) {
      peers.add(s);
      final CastV2FrameDecoder d = CastV2FrameDecoder();
      void reply(String ns, Map<String, dynamic> body) => s.add(CastV2Message(
              namespace: ns,
              sourceId:
                  ns == CastV2Commands.media ? 'transport-1' : 'receiver-0',
              destinationId: 'sender-0',
              payload: body)
          .encodeFrame());
      void status(Object? id, String state) =>
          reply(CastV2Commands.media, <String, dynamic>{
            'type': 'MEDIA_STATUS',
            if (id != null) 'requestId': id,
            'status': <Object>[
              <String, dynamic>{'mediaSessionId': 99, 'playerState': state}
            ]
          });
      s.listen((List<int> bytes) {
        for (final CastV2Message m in d.add(bytes)) {
          received.add(m);
          final Object? id = m.payload['requestId'];
          switch (m.payload['type']) {
            case 'LAUNCH':
              if (drop) {
                s.destroy();
                break;
              }
              reply(CastV2Commands.receiver, <String, dynamic>{
                'type': 'RECEIVER_STATUS',
                'requestId': id,
                'status': <String, dynamic>{
                  'applications': <Object>[
                    <String, dynamic>{
                      'appId': 'CC1AD845',
                      'transportId': 'transport-1'
                    }
                  ]
                }
              });
              reply(
                  CastV2Commands.heartbeat, <String, dynamic>{'type': 'PING'});
            case 'LOAD':
              if (reject) {
                reply(CastV2Commands.media,
                    <String, dynamic>{'type': 'LOAD_FAILED', 'requestId': id});
                break;
              }
              status(id, 'BUFFERING');
              if (!buffering) status(null, 'PLAYING');
            case 'PLAY':
              status(id, 'PLAYING');
            case 'PAUSE':
              status(id, 'PAUSED');
            case 'STOP':
              status(id, 'IDLE');
          }
        }
      });
    });
    client = CastV2Client(
        connector: Socket.connect, timeout: const Duration(milliseconds: 500));
  });
  tearDown(() async {
    client.close();
    for (final Socket p in peers) {
      p.destroy();
    }
    peers.clear();
    await server.close();
  });
  Future<void> open() => client.open('127.0.0.1', server.port);
  Future<void> load() => client.load(
      url: 'http://example.com/a.m3u8',
      contentType: 'application/x-mpegURL',
      title: 'Test');
  test('CONNECT LAUNCH app CONNECT LOAD controls and PONG', () async {
    await open();
    await load();
    await client.command('PAUSE');
    await client.command('PLAY');
    await client.command('STOP');
    expect(
        received
            .where((CastV2Message m) => m.payload['type'] == 'CONNECT')
            .map((CastV2Message m) => m.destinationId),
        <String>['receiver-0', 'transport-1']);
    expect(
        received.any((CastV2Message m) => m.payload['type'] == 'PONG'), true);
    expect(
        received
            .where((CastV2Message m) =>
                <String>{'PLAY', 'PAUSE', 'STOP'}.contains(m.payload['type']))
            .every((CastV2Message m) =>
                m.payload['mediaSessionId'] == 99 &&
                m.destinationId == 'transport-1'),
        true);
  });
  test('LOAD_FAILED is not success', () async {
    reject = true;
    await open();
    await expectLater(load(), throwsStateError);
  });
  test('BUFFERING without PLAYING times out', () async {
    buffering = true;
    await open();
    await expectLater(load(), throwsA(isA<TimeoutException>()));
  });
  test('disconnect fails pending request', () async {
    drop = true;
    await expectLater(open(), throwsA(isA<SocketException>()));
  });
  test('cancelled connect cannot resurrect session', () async {
    client.close();
    final Completer<Socket> c = Completer<Socket>();
    client = CastV2Client(connector: (host, port) => c.future);
    final Future<void> opening = open();
    client.close();
    final Future<void> assertion = expectLater(opening, throwsStateError);
    c.complete(await Socket.connect('127.0.0.1', server.port));
    await assertion;
  });
}
