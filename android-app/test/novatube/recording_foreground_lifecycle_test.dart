import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/recordings/data/recording_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel =
      MethodChannel('com.manzilionellm.tvking/recording_service');
  const StandardMethodCodec codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? lastSession;
  Completer<bool>? acknowledgement;

  Future<void> nativeStop(String session, String reason) async {
    final Completer<void> handled = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall('recordingStopped', <String, String>{
        'sessionId': session,
        'reason': reason,
      })),
      (_) => handled.complete(),
    );
    await handled.future;
  }

  setUp(() async {
    acknowledgement = null;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'start') {
        lastSession = (call.arguments as Map<dynamic, dynamic>)['sessionId'] as String;
        return acknowledgement == null ? true : await acknowledgement!.future;
      }
      return true;
    });
    await RecordingService.instance.stop();
  });

  tearDown(() async {
    await RecordingService.instance.stop();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('un timeout avant confirmation ne laisse pas un REC actif', () async {
    acknowledgement = Completer<bool>();
    final List<String> stopped = <String>[];
    final Future<bool> starting = RecordingService.instance.start(
      title: 'Flux de test',
      onStopped: (String reason) async { stopped.add(reason); },
    );
    await Future<void>.delayed(Duration.zero);
    await nativeStop(lastSession!, 'foregroundTimeout');
    acknowledgement!.complete(true);
    expect(await starting, isFalse);
    expect(stopped, <String>['foregroundTimeout']);
  });

  test('un événement retardé ne ferme pas le nouvel enregistrement', () async {
    final List<String> stopped = <String>[];
    expect(await RecordingService.instance.start(title: 'Premier'), isTrue);
    final String oldSession = lastSession!;
    await RecordingService.instance.stop();
    expect(await RecordingService.instance.start(
      title: 'Deuxième',
      onStopped: (String reason) async { stopped.add(reason); },
    ), isTrue);
    final String newSession = lastSession!;
    expect(newSession, isNot(oldSession));
    await nativeStop(oldSession, 'foregroundTimeout');
    expect(stopped, isEmpty);
    await nativeStop(newSession, 'notificationStop');
    await nativeStop(newSession, 'serviceDestroyed');
    expect(stopped, <String>['notificationStop']);
  });

  test('le refus de promotion Android reste un échec de démarrage', () async {
    acknowledgement = Completer<bool>()..complete(false);
    expect(await RecordingService.instance.start(title: 'Quota épuisé'), isFalse);
  });
}
