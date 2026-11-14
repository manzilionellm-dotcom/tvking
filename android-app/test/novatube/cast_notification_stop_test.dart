import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/google_cast_transport.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/player/data/pip_service.dart';

const MethodChannel _pip = MethodChannel('com.manzilionellm.tvking/pip');
const MethodChannel _cast = MethodChannel('com.manzilionellm.tvking/cast');
const CastDevice _device = CastDevice(
  id: 'fixture', name: 'Écran de test', kind: CastDeviceKind.googleCast,
  host: '192.0.2.1', port: 8009, controlUrl: '',
);

// Transport volontairement simulé : ces tests vérifient le routage de l'arrêt
// et les courses d'identité. Ils ne constituent aucune preuve FGS Android.
class _RelayTransport extends GoogleCastTransport {
  _RelayTransport() : super(_device);

  @override
  Future<void> playStream({
    required String streamUrl, String title = 'Test', String? imageUrl,
  }) async {
    lastCastPath = 'local_hls_relay';
    lastRelayUrl = 'http://127.0.0.1:1/relay/fixture.ts';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const StandardMethodCodec codec = StandardMethodCodec();
  late List<MethodCall> calls;
  late List<String> castCalls;
  CastManager? manager;

  Future<void> nativeEvent(Object? arguments, {String method = 'castStopRequested'}) async {
    final Completer<void> handled = Completer<void>();
    messenger.handlePlatformMessage(
      _pip.name, codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) => handled.complete(),
    );
    await handled.future;
  }

  Future<void> nativeStop(String session) => nativeEvent(<String, String>{'sessionId': session});

  String lastSession() => (calls.lastWhere(
    (MethodCall call) => call.method == 'startBackgroundAudio',
  ).arguments as Map<dynamic, dynamic>)['castSessionId'] as String;

  setUp(() {
    calls = <MethodCall>[];
    castCalls = <String>[];
    messenger.setMockMethodCallHandler(_pip, (MethodCall call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(_cast, (MethodCall call) async {
      castCalls.add(call.method);
      return null;
    });
  });

  tearDown(() async {
    if (manager != null) {
      await manager!.disconnect();
      manager!.dispose();
      manager = null;
    }
    for (final MethodCall call in calls.where((call) => call.method == 'startBackgroundAudio').toList()) {
      final Object? id = (call.arguments as Map<dynamic, dynamic>)['castSessionId'];
      if (id is String) await PipService.instance.stopBackgroundAudio(castSessionId: id);
    }
    messenger.setMockMethodCallHandler(_pip, null);
    messenger.setMockMethodCallHandler(_cast, null);
  });

  test('audio historique conserve les méthodes et les arguments antérieurs', () async {
    await PipService.instance.startBackgroundAudio('Audio');
    await PipService.instance.stopBackgroundAudio();
    expect(calls.map((call) => call.method), <String>['startBackgroundAudio', 'stopBackgroundAudio']);
    expect(calls.first.arguments, <String, String>{'title': 'Audio'});
    expect(calls.last.arguments, isNull);
  });

  test('un arrêt utilisateur valide est consommé une seule fois avant await', () async {
    int stops = 0;
    final Completer<void> closing = Completer<void>();
    await PipService.instance.startBackgroundAudio(
      'Cast', castSessionId: 'a', onCastStopRequested: () async {
        stops++;
        await closing.future;
      },
    );
    final Future<void> first = nativeStop('a');
    await Future<void>.delayed(Duration.zero);
    await nativeStop('a');
    expect(stops, 1);
    closing.complete();
    await first;
  });

  test('événement obsolète ou malformé et arrêt interne ne déconnectent pas', () async {
    final List<String> stops = <String>[];
    await PipService.instance.startBackgroundAudio('A', castSessionId: 'a',
        onCastStopRequested: () async { stops.add('a'); });
    await PipService.instance.startBackgroundAudio('B', castSessionId: 'b',
        onCastStopRequested: () async { stops.add('b'); });
    await nativeStop('a');
    await nativeEvent(null);
    await nativeEvent(<String, Object>{'sessionId': 7});
    await nativeEvent(<String, String>{'sessionId': 'b'}, method: 'stopBackgroundAudio');
    await PipService.instance.stopBackgroundAudio(castSessionId: 'a');
    expect(stops, isEmpty);
    await nativeStop('b');
    expect(stops, <String>['b']);
    await PipService.instance.stopBackgroundAudio(castSessionId: 'b');
    await nativeStop('b');
    expect(stops, <String>['b']);
  });

  test('arrêt applicatif invalide le callback sans créer un arrêt utilisateur', () async {
    int stops = 0;
    await PipService.instance.startBackgroundAudio('Cast', castSessionId: 'a',
        onCastStopRequested: () async { stops++; });
    await PipService.instance.stopBackgroundAudio(castSessionId: 'a');
    await nativeStop('a');
    expect(stops, 0);
    expect(calls.last.arguments, <String, String>{'castSessionId': 'a'});
  });

  test('la notification passe par le vrai disconnect du manager et ferme une seule session', () async {
    final Completer<bool> permission = Completer<bool>();
    int permissionRequests = 0;
    manager = CastManager.forTesting(
      transportFactory: (_) => _RelayTransport(),
      probe: (url) async => StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
      requestNotificationPermission: () {
        permissionRequests++;
        return permission.future;
      },
    );
    await manager!.castTo(_device, streamUrl: 'http://stream.invalid/first.ts', title: 'Premier');
    await Future<void>.delayed(Duration.zero);
    final String first = lastSession();
    await manager!.castTo(_device, streamUrl: 'http://stream.invalid/second.ts', title: 'Deuxième');
    await Future<void>.delayed(Duration.zero);
    final String second = lastSession();
    expect(second, isNot(first));
    castCalls.clear();
    await nativeStop(first);
    expect(manager!.state, CastState.casting);
    expect(manager!.currentTitle, 'Deuxième');
    expect(castCalls, isEmpty);
    await nativeStop(second);
    expect(manager!.state, CastState.idle);
    expect(manager!.device, isNull);
    expect(castCalls, <String>['stop', 'disconnect']);
    await nativeStop(second);
    expect(castCalls, <String>['stop', 'disconnect']);
    expect(calls.lastWhere((call) => call.method == 'stopBackgroundAudio').arguments,
        <String, String>{'castSessionId': second});
    final int starts = calls.where((call) => call.method == 'startBackgroundAudio').length;
    permission.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(permissionRequests, 1);
    expect(calls.where((call) => call.method == 'startBackgroundAudio'), hasLength(starts),
        reason: 'La permission de la première session ne peut réafficher le service arrêté.');
  });
}
