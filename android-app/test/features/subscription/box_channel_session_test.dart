// Vraies prises locales : reprise du même ordre après un échec, déduplication
// et arrêt au changement de cycle de vie. Aucun Worker de production contacté.
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/subscription/data/box_channel_session.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late HttpOverrides? previous;
  final List<WebSocket> sockets = <WebSocket>[];
  setUp(() async {
    previous = HttpOverrides.current;
    HttpOverrides.global = _RealHttp();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    for (final socket in sockets) { await socket.close(); }
    sockets.clear();
    await server.close(force: true);
    HttpOverrides.global = previous;
  });

  test('un ordre échoué est rejoué à la reconnexion sans avancer le numéro', () async {
    const String mac = 'MK:11:22:33:44:55';
    int attempts = 0, opens = 0;
    final Completer<void> applied = Completer<void>();
    server.listen((request) async {
      expect(request.uri.path, '/api/box/ws');
      expect(request.uri.query.contains('secret'), isFalse);
      expect(request.headers.value('X-Device-Secret'), 'fixture-proof');
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      // Lire la prise permet aussi de traiter ping/pong et la fermeture :
      // sans écoute, le faux serveur laisse le client attendre la poignée.
      socket.listen((_) {});
      socket.add('{"v":1,"seq":7,"type":"source","mac":"$mac"}');
    });
    late BoxChannelSession session;
    session = BoxChannelSession(mac: mac, alive: () => true,
      baseUrl: 'http://127.0.0.1:${server.port}',
      retryDelay: const Duration(milliseconds: 10),
      headers: () async => <String,String>{'X-Device-Secret':'fixture-proof'},
      onConnected: () => opens++,
      onFrame: (frame) async {
        expect(frame.seq, 7);
        expect(session.seq, 0);
        if (++attempts == 1) return false;
        applied.complete();
        session.stop();
        return true;
      });
    final Future<void> run = session.run();
    await applied.future.timeout(const Duration(seconds: 3));
    await run.timeout(const Duration(seconds: 2));
    expect(attempts,2); expect(opens,2); expect(session.seq,7); expect(session.open,isFalse);
  });

  test('les doublons et une autre MAC ne déclenchent pas de nouvel import', () async {
    const String mac = 'MK:11:22:33:44:55';
    final Completer<void> last = Completer<void>();
    final List<int> applied = <int>[];
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((_) {});
      for (final frame in <String>[
        '{"seq":"bad","type":"source","mac":"$mac"}',
        '{"seq":6,"type":"source","mac":"MK:00:00:00:00:00"}',
        '{"seq":7,"type":"source","mac":"$mac"}',
        '{"seq":7,"type":"source","mac":"$mac"}',
        '{"seq":8,"type":"source_clear","mac":"$mac"}',
      ]) { socket.add(frame); }
    });
    late BoxChannelSession session;
    session = BoxChannelSession(mac:mac,alive:()=>true,
      baseUrl:'http://127.0.0.1:${server.port}',onFrame:(frame) async {
        applied.add(frame.seq);
        if(frame.seq==8){last.complete();session.stop();}
        return true;
      });
    final Future<void> run=session.run();
    await last.future.timeout(const Duration(seconds:2));
    await run.timeout(const Duration(seconds:2));
    expect(applied,<int>[7,8]);
  });
}
