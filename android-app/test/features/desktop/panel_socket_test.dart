import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/data/box_channel_session.dart';
import 'package:tv_king/features/subscription/domain/box_channel.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  test('ordre non appliqué : reconnexion et rejeu, jamais perdu', () async {
    HttpOverrides.global = _RealHttp();
    const String mac = 'MK:AA:BB:CC:DD:01';
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<WebSocket> sockets = <WebSocket>[];
    final StreamSubscription<HttpRequest> requests = server.listen((
      request,
    ) async {
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.add(
        jsonEncode(<String, Object>{'seq': 7, 'type': 'source', 'mac': mac}),
      );
    });
    int attempts = 0;
    final Completer<void> applied = Completer<void>();
    late BoxChannelSession session;
    session = BoxChannelSession(
      mac: mac,
      backendUrl: 'http://127.0.0.1:${server.port}',
      alive: () => !applied.isCompleted,
      onFrame: (BoxChannelFrame frame) async {
        attempts++;
        expect(frame.seq, 7);
        if (attempts == 1) return false;
        applied.complete();
        session.stop();
        return true;
      },
    );
    final Future<void> running = session.run();
    try {
      await applied.future.timeout(const Duration(seconds: 8));
      await running.timeout(const Duration(seconds: 3));
      expect(attempts, 2);
      expect(session.seq, 7);
      expect(sockets.length, 2);
    } finally {
      session.stop();
      for (final WebSocket socket in sockets) {
        await socket.close();
      }
      await requests.cancel();
      await server.close(force: true);
      HttpOverrides.global = null;
    }
  });
}
