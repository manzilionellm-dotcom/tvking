// Vraies sockets locales : un Future expiré ne prouve pas une annulation HTTP.
// Le récepteur constate ici la fermeture du socket de la seule requête lente.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/cast/data/upnp_av_transport.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

class _RealHttp extends HttpOverrides {}

class _SocketReceiver {
  ServerSocket? server;
  final sockets = <Socket>[];
  final timers = <Timer>[];
  final slowReceived = Completer<void>();
  final slowClosed = Completer<void>();
  final commands = <String>[];
  Duration pauseDelay = const Duration(milliseconds: 400);
  Duration? slowReply;

  Future<CastDevice> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((socket) {
      sockets.add(socket);
      final bytes = <int>[];
      bool handled = false;
      String? action;
      socket.listen((chunk) {
        bytes.addAll(chunk);
        final raw = latin1.decode(bytes);
        final split = raw.indexOf('\r\n\r\n');
        if (handled || split < 0) return;
        final length = int.parse(
            RegExp(r'content-length:\s*(\d+)', caseSensitive: false)
                    .firstMatch(raw)
                    ?.group(1) ??
                '0');
        if (bytes.length < split + 4 + length) return;
        handled = true;
        action =
            RegExp(r'soapaction:[^\r\n]*#([^"\r\n]+)', caseSensitive: false)
                .firstMatch(raw)
                ?.group(1);
        commands.add(action ?? 'inconnue');
        if (action == 'GetTransportInfo') {
          if (!slowReceived.isCompleted) slowReceived.complete();
          if (slowReply != null) {
            timers.add(Timer(
                slowReply!,
                () => reply(socket,
                    '<CurrentTransportState>STOPPED</CurrentTransportState>')));
          }
        } else {
          timers
              .add(Timer(pauseDelay, () => reply(socket, '<PauseResponse/>')));
        }
      }, onDone: () {
        if (action == 'GetTransportInfo' && !slowClosed.isCompleted) {
          slowClosed.complete();
        }
      }, onError: (Object _) {
        if (action == 'GetTransportInfo' && !slowClosed.isCompleted) {
          slowClosed.complete();
        }
      });
    });
    return CastDevice(
        id: 'socket-timeout',
        name: 'Récepteur socket',
        kind: CastDeviceKind.dlna,
        host: '127.0.0.1',
        port: server!.port,
        controlUrl: 'http://127.0.0.1:${server!.port}/control');
  }

  void reply(Socket socket, String body) {
    final response = utf8.encode('<Envelope><Body>$body</Body></Envelope>');
    try {
      socket.add(ascii.encode('HTTP/1.1 200 OK\r\n'
          'Content-Type: text/xml\r\nContent-Length: ${response.length}\r\n'
          'Connection: close\r\n\r\n'));
      socket.add(response);
      unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));
    } on Object {
      // Le client du scénario d'annulation peut déjà avoir fermé son côté.
    }
  }

  Future<void> close() async {
    for (final timer in timers) {
      timer.cancel();
    }
    for (final socket in sockets) {
      socket.destroy();
    }
    await server?.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppPlatform.configureZuno(isAndroidHandset: false);
    RepairFlags.debugReset();
  });
  tearDown(() {
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
  });

  test('expiration ferme uniquement la requête lente, Pause parallèle survit',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final receiver = _SocketReceiver();
      final device = await receiver.start();
      final transport = UpnpAvTransport(device)
        ..soapTimeout = const Duration(milliseconds: 250);
      final other = UpnpAvTransport(device)
        ..soapTimeout = const Duration(seconds: 2);
      try {
        final slow = transport.currentTransportState();
        await receiver.slowReceived.future;
        transport.soapTimeout = const Duration(seconds: 2);
        final sameSessionPause = transport.pause();
        final otherSessionPause = other.pause();
        expect(await slow, isNull);
        await receiver.slowClosed.future
            .timeout(const Duration(milliseconds: 750));
        await Future.wait([sameSessionPause, otherSessionPause]);
        expect(
            receiver.commands.where((command) => command == 'Pause').length, 2);
      } finally {
        await receiver.close();
      }
    }, _RealHttp());
  });

  test('réponse postérieure au délai ne résout jamais une seconde fois',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final receiver = _SocketReceiver()
        ..slowReply = const Duration(milliseconds: 700);
      final transport = UpnpAvTransport(await receiver.start())
        ..soapTimeout = const Duration(milliseconds: 250);
      int settlements = 0;
      try {
        final result = transport.currentTransportState().then((value) {
          settlements++;
          return value;
        });
        expect(await result, isNull);
        await receiver.slowClosed.future
            .timeout(const Duration(milliseconds: 300));
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(settlements, 1);
      } finally {
        await receiver.close();
      }
    }, _RealHttp());
  });

  test('7 MOTION conserve le timeout historique sans fermeture anticipée',
      () async {
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
    await HttpOverrides.runWithHttpOverrides(() async {
      final receiver = _SocketReceiver()
        ..slowReply = const Duration(milliseconds: 700);
      final transport = UpnpAvTransport(await receiver.start())
        ..soapTimeout = const Duration(milliseconds: 150);
      try {
        expect(await transport.currentTransportState(), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(receiver.slowClosed.isCompleted, isFalse);
        await receiver.slowClosed.future.timeout(const Duration(seconds: 2));
      } finally {
        await receiver.close();
      }
    }, _RealHttp());
  });
}
