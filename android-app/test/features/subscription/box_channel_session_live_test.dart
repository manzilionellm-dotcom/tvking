// Vraie prise locale : un import lent ne retarde pas l'accusé du prochain
// ordre, et les effets métier restent strictement ordonnés.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/data/box_channel_session.dart';

const _run = bool.fromEnvironment('RUN_PANEL_CONNECTION');
const _mac = 'MK:11:22:33:44:77';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('réception rapide pendant un import lent, traitement ordonné', () async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = _RealHttp();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18789);
    final connected = Completer<WebSocket>();
    final receivedBoth = Completer<void>();
    final processedBoth = Completer<void>();
    final importFinished = Completer<void>();
    final received = <int>[];
    final processed = <int>[];
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      connected.complete(socket);
      socket.listen((_) {});
    });
    final session = BoxChannelSession(
      mac: _mac,
      alive: () => true,
      onReceived: (frame) {
        received.add(frame.seq);
        if (received.length == 2) receivedBoth.complete();
      },
      onFrame: (frame) async {
        if (frame.seq == 1) await importFinished.future;
        processed.add(frame.seq);
        if (processed.length == 2) processedBoth.complete();
      },
    );
    final run = session.run();
    WebSocket? peer;
    try {
      peer = await connected.future.timeout(const Duration(seconds: 5));
      final clock = Stopwatch()..start();
      for (final seq in <int>[1, 2]) {
        peer.add(jsonEncode(<String, Object>{
          'seq': seq,
          'mac': _mac,
          'type': seq == 1 ? 'source' : 'activate',
          'order_id': 'ord_queue_fixture_$seq',
        }));
      }
      await receivedBoth.future.timeout(const Duration(seconds: 1));
      expect(clock.elapsedMilliseconds, lessThan(1000));
      expect(received, <int>[1, 2]);
      expect(processed, isEmpty,
          reason:
              'La réception continue, mais les effets ne se chevauchent pas.');
      importFinished.complete();
      await processedBoth.future.timeout(const Duration(seconds: 2));
      expect(processed, <int>[1, 2]);
    } finally {
      if (!importFinished.isCompleted) importFinished.complete();
      session.stop();
      await peer?.close();
      await run;
      await server.close(force: true);
      HttpOverrides.global = previous;
    }
  }, skip: !_run);
}
