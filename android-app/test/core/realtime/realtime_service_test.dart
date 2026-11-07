import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:tv_king/core/realtime/realtime_service.dart';

class FakeSocket implements RealtimeSocket {
  final StreamController<Object?> controller =
      StreamController<Object?>.broadcast(sync: true);
  final List<String> sent = <String>[];
  @override
  Stream<Object?> get messages => controller.stream;
  @override
  void send(String message) {
    sent.add(message);
  }

  @override
  Future<void> close() async {
    if (!controller.isClosed) await controller.close();
  }

  void event(String type, {String? mac}) => controller.add(jsonEncode(
      <String, Object?>{'v': 1, 'type': type, if (mac != null) 'mac': mac}));
}

void main() {
  const String mac = 'MK:AA:BB:CC:DD:EE';
  test('every declared panel event refreshes only matching repositories',
      () async {
    final FakeSocket socket = FakeSocket();
    final Map<String, int> calls = <String, int>{};
    final Set<String> resources =
        realtimeRefreshMap.values.expand((List<String> e) => e).toSet();
    final RealtimeService service = RealtimeService(
        mac: mac,
        connect: () async => socket,
        refreshers: <String, Refresh>{
          for (final String name in resources)
            name: () async {
              calls[name] = (calls[name] ?? 0) + 1;
            }
        });
    service.start();
    await Future<void>.delayed(Duration.zero);
    socket.event('hello');
    await service.idle;
    for (final MapEntry<String, List<String>> mapping
        in realtimeRefreshMap.entries) {
      calls.clear();
      socket.event(mapping.key, mac: mac);
      await service.idle;
      expect(calls.keys.toSet(), mapping.value.toSet(), reason: mapping.key);
    }
    calls.clear();
    socket.event('source', mac: 'MK:00:00:00:00:00');
    socket.event('unrecognised');
    socket.controller.add('{broken');
    await service.idle;
    expect(calls, isEmpty);
    await service.dispose();
  });
  test('reconnect uses exponential delay; no duplicate connect; resume resyncs',
      () {
    fakeAsync((FakeAsync time) {
      int attempts = 0, refreshes = 0;
      final FakeSocket socket = FakeSocket();
      final RealtimeService service = RealtimeService(
          mac: mac,
          jitter: false,
          connect: () async {
            attempts++;
            if (attempts < 3) throw StateError('offline');
            return socket;
          },
          refreshers: <String, Refresh>{
            'status': () async {
              refreshes++;
            }
          });
      service.start();
      time.flushMicrotasks();
      expect(attempts, 1);
      time.elapse(const Duration(milliseconds: 999));
      expect(attempts, 1);
      time.elapse(const Duration(milliseconds: 1));
      time.flushMicrotasks();
      expect(attempts, 2);
      time.elapse(const Duration(seconds: 2));
      time.flushMicrotasks();
      expect(attempts, 3);
      socket.event('hello');
      time.flushMicrotasks();
      expect(service.connected, isTrue);
      final int before = refreshes;
      // Acknowledged heartbeats keep the connection healthy; fallback stays off.
      for (int i = 0; i < 4; i++) {
        time.elapse(const Duration(seconds: 10));
        socket.event('hello');
        time.flushMicrotasks();
      }
      expect(refreshes, before);
      service.stop();
      time.flushMicrotasks();
      final int stoppedAttempts = attempts;
      time.elapse(const Duration(minutes: 2));
      time.flushMicrotasks();
      expect(attempts, stoppedAttempts);
    });
  });
  test('events during an in-flight refresh are not lost', () async {
    final FakeSocket socket = FakeSocket();
    final List<Completer<void>> runs = <Completer<void>>[];
    final RealtimeService service = RealtimeService(
        mac: mac,
        connect: () async => socket,
        refreshers: <String, Refresh>{
          'sources': () {
            final Completer<void> c = Completer<void>();
            runs.add(c);
            return c.future;
          }
        });
    service.start();
    await Future<void>.delayed(Duration.zero);
    socket.event('hello');
    runs[0].complete();
    await Future<void>.delayed(Duration.zero);
    socket.event('source_clear');
    expect(runs.length, 2);
    runs[1].complete();
    await Future<void>.delayed(Duration.zero);
    expect(runs.length, 3);
    runs[2].complete();
    await service.idle;
    await service.dispose();
  });
  test('socket without heartbeat is discarded; offline fallback remains active',
      () {
    fakeAsync((FakeAsync time) {
      final FakeSocket socket = FakeSocket();
      int calls = 0;
      final RealtimeService service = RealtimeService(
          mac: mac,
          jitter: false,
          connect: () async => socket,
          refreshers: <String, Refresh>{
            'status': () async {
              calls++;
            }
          });
      service.start();
      time.flushMicrotasks();
      socket.event('hello');
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 36));
      time.flushMicrotasks();
      expect(service.connected, isFalse);
      final int before = calls;
      time.elapse(const Duration(seconds: 30));
      time.flushMicrotasks();
      expect(calls, greaterThan(before));
      service.stop();
      time.flushMicrotasks();
    });
  });
  test('a socket completing after handshake timeout is closed', () {
    fakeAsync((FakeAsync time) {
      final Completer<RealtimeSocket> pending = Completer<RealtimeSocket>();
      final FakeSocket socket = FakeSocket();
      final RealtimeService service = RealtimeService(
        mac: mac,
        connect: () => pending.future,
        refreshers: <String, Refresh>{},
        jitter: false,
      );
      service.start();
      time.elapse(const Duration(seconds: 15));
      time.flushMicrotasks();
      pending.complete(socket);
      time.flushMicrotasks();
      expect(socket.controller.isClosed, isTrue);
      expect(service.connected, isFalse);
      service.stop();
      time.flushMicrotasks();
    });
  });
  test('app resume closes the old socket and refetches every resource', () {
    fakeAsync((FakeAsync time) {
      final List<FakeSocket> sockets = <FakeSocket>[];
      int refreshes = 0;
      final RealtimeService service = RealtimeService(
        mac: mac,
        connect: () async {
          final FakeSocket s = FakeSocket();
          sockets.add(s);
          return s;
        },
        refreshers: <String, Refresh>{
          'status': () async {
            refreshes++;
          }
        },
      );
      service.start();
      service.start();
      time.flushMicrotasks();
      expect(sockets.length, 1);
      sockets.first.event('hello');
      time.flushMicrotasks();
      final int before = refreshes;
      service.resume();
      time.flushMicrotasks();
      expect(sockets.length, 2);
      expect(sockets.first.controller.isClosed, isTrue);
      expect(refreshes, greaterThan(before));
      sockets.last.event('hello');
      time.flushMicrotasks();
      expect(service.connected, isTrue);
      service.stop();
      time.flushMicrotasks();
    });
  });
}
