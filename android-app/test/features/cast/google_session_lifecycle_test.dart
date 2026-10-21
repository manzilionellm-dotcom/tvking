import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/google_cast_transport.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

const MethodChannel _channel = MethodChannel('com.manzilionellm.tvking/cast');
const CastDevice _google = CastDevice(
  id: 'google',
  name: 'Google synthétique',
  kind: CastDeviceKind.googleCast,
  host: '192.0.2.1',
  port: 8009,
  controlUrl: '',
);
const CastDevice _roku = CastDevice(
  id: 'roku',
  name: 'Roku synthétique',
  kind: CastDeviceKind.roku,
  host: '192.0.2.2',
  port: 8060,
  controlUrl: 'http://192.0.2.2',
);

class _Transport implements CastTransport {
  int stops = 0;
  @override
  Future<void> playStream(
      {required String streamUrl,
      String title = 'Test',
      String? imageUrl}) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> commands;
  Future<Object?> Function(MethodCall)? handler;

  setUp(() {
    commands = <String>[];
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      commands.add(call.method);
      if (handler != null) return handler!(call);
      switch (call.method) {
        case 'isCastAvailable':
        case 'hasActiveSession':
          return true;
        case 'setReceiverApplicationId':
          return 'unchanged';
        case 'loadMedia':
          return false;
        default:
          return null;
      }
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test(
      'annulation pendant la réponse de disponibilité ne sélectionne aucun receiver',
      () async {
    final Completer<void> checking = Completer<void>();
    final Completer<bool> available = Completer<bool>();
    bool current = true;
    handler = (call) async {
      if (call.method == 'isCastAvailable') {
        checking.complete();
        return available.future;
      }
      return null;
    };
    final GoogleCastTransport transport = GoogleCastTransport(_google)
      ..sessionIsCurrent = () => current;
    final Future<void> result = expectLater(
      transport.playStream(streamUrl: 'http://stream.invalid/live.m3u8'),
      throwsA(isA<Exception>()),
    );
    await checking.future;
    current = false;
    available.complete(true);
    await result;
    expect(commands, <String>['isCastAvailable']);
  });

  test('un LOAD annulé ne déclenche ni attente de lecture ni repli', () async {
    final Completer<void> loading = Completer<void>();
    final Completer<bool> loaded = Completer<bool>();
    bool current = true;
    handler = (call) async {
      switch (call.method) {
        case 'isCastAvailable':
        case 'hasActiveSession':
          return true;
        case 'setReceiverApplicationId':
          return 'unchanged';
        case 'loadMedia':
          loading.complete();
          return loaded.future;
        default:
          return null;
      }
    };
    final GoogleCastTransport transport = GoogleCastTransport(_google)
      ..sessionIsCurrent = () => current;
    final Future<void> result = expectLater(
      transport.playStream(streamUrl: 'http://stream.invalid/live.m3u8'),
      throwsA(isA<Exception>()),
    );
    await loading.future;
    current = false;
    loaded.complete(false);
    await result;
    expect(commands.where((command) => command == 'loadMedia'), hasLength(1));
    expect(transport.lastRelayUrl, isNull);
    expect(commands, isNot(contains('showRoutePicker')));
  });

  test('l’ancien handshake Google ne charge jamais la nouvelle session de Cast',
      () async {
    final Completer<void> checking = Completer<void>();
    final Completer<bool> active = Completer<bool>();
    handler = (call) async {
      switch (call.method) {
        case 'isCastAvailable':
          return true;
        case 'setReceiverApplicationId':
          return 'unchanged';
        case 'hasActiveSession':
          checking.complete();
          return active.future;
        case 'loadMedia':
          return false;
        default:
          return null;
      }
    };
    final _Transport nextTransport = _Transport();
    final CastManager manager = CastManager.forTesting(
      transportFactory: (device) =>
          device.id == 'google' ? GoogleCastTransport(device) : nextTransport,
      probe: (url) async =>
          StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
      timeout: const Duration(seconds: 30),
    );
    try {
      final Future<void> first = manager.castTo(
        _google,
        streamUrl: 'http://stream.invalid/old.m3u8',
        title: 'Ancien',
        owner: Object(),
      );
      await checking.future;
      final Object nextOwner = Object();
      await manager.castTo(
        _roku,
        streamUrl: 'http://stream.invalid/new.m3u8',
        title: 'Nouveau',
        owner: nextOwner,
      );
      active.complete(true);
      await first;
      expect(commands, isNot(contains('loadMedia')));
      expect(manager.ownsSession(nextOwner), isTrue);
      expect(manager.state, CastState.casting);
      expect(nextTransport.stops, 0);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });

  testWidgets(
      'la réponse Stop Google tardive ne redéconnecte pas le Cast suivant',
      (tester) async {
    final Completer<void> checking = Completer<void>();
    final Completer<bool> active = Completer<bool>();
    final Completer<void> stopping = Completer<void>();
    final Completer<void> stopReply = Completer<void>();
    handler = (call) async {
      switch (call.method) {
        case 'isCastAvailable':
          return true;
        case 'setReceiverApplicationId':
          return 'unchanged';
        case 'hasActiveSession':
          checking.complete();
          return active.future;
        case 'stop':
          stopping.complete();
          await stopReply.future;
          return null;
        default:
          return null;
      }
    };
    final _Transport nextTransport = _Transport();
    final CastManager manager = CastManager.forTesting(
      transportFactory: (device) =>
          device.id == 'google' ? GoogleCastTransport(device) : nextTransport,
      probe: (url) async =>
          StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
      timeout: const Duration(seconds: 30),
    );
    try {
      final Future<void> first = manager.castTo(
        _google,
        streamUrl: 'http://stream.invalid/old.m3u8',
        title: 'Ancien',
      );
      await checking.future;
      final Future<void> closing = manager.disconnect();
      await stopping.future;
      await tester.pump(const Duration(seconds: 6));
      await closing;
      expect(
          commands.where((command) => command == 'disconnect'), hasLength(1));
      await manager.castTo(
        _roku,
        streamUrl: 'http://stream.invalid/new.m3u8',
        title: 'Nouveau',
      );
      stopReply.complete();
      active.complete(true);
      await first;
      await tester.pump();
      expect(commands.where((command) => command == 'disconnect'), hasLength(1),
          reason:
              'la continuation du Stop expiré ne doit plus envoyer de disconnect');
      expect(manager.device?.id, 'roku');
      expect(manager.state, CastState.casting);
      expect(nextTransport.stops, 0);
    } finally {
      await manager.disconnect();
      manager.dispose();
    }
  });
}
