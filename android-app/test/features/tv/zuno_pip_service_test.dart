import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/data/zuno_pip_service.dart';

// Le vrai coordinateur reçoit les messages Android simulés. On vérifie les
// courses de cycle de vie, pas seulement une copie de sa condition d'affichage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.sevenmotion.zuno/pip-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ZunoPipService service;
  late ZunoPipPlayback playback;
  late List<MethodCall> calls;
  late List<bool> suspensions;
  late List<bool> visibility;
  late int resumes;
  late int modeChanges;
  late Map<String, bool> snapshot;
  Future<Object?> Function()? readSnapshot;

  Future<void> drain() async {
    // Les invocations de canal sont réellement asynchrones dans ces tests.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> event({required bool inPip, required bool visible}) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(
        'onPipModeChanged',
        <String, bool>{'inPip': inPip, 'visible': visible},
      )),
      (_) => done.complete(),
    );
    await done.future;
    await drain();
  }

  ZunoPipPlayback acquire() => service.acquire(
    onSuspend: suspensions.add,
    onResume: () => resumes++,
    onModeChanged: () => modeChanges++,
    onVisibilityChanged: visibility.add,
  );

  setUp(() async {
    calls = <MethodCall>[];
    suspensions = <bool>[];
    visibility = <bool>[];
    resumes = 0;
    modeChanges = 0;
    snapshot = <String, bool>{'inPip': false, 'visible': true};
    readSnapshot = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getPipState':
          return readSnapshot == null ? snapshot : await readSnapshot!();
        case 'isPipSupported':
          return true;
        default:
          return null;
      }
    });
    service = ZunoPipService.forTesting(enabled: true, channel: channel);
    playback = acquire();
    await drain();
  });

  tearDown(() async {
    playback.dispose();
    service.dispose();
    await drain();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('seule la lecture locale autorise PiP, sans spam à chaque position', () async {
    calls.clear();
    playback.update(playing: true, casting: false, width: 1920, height: 1080);
    playback.update(playing: true, casting: false, width: 1920, height: 1080);
    await drain();
    final active = calls.where((call) => call.method == 'setPlaybackActive');
    expect(active, hasLength(1));
    expect(active.single.arguments, <String, bool>{'active': true});
    expect(calls.where((call) => call.method == 'setAspectRatio'), hasLength(1));

    playback.update(playing: true, casting: true, width: 1920, height: 1080);
    await drain();
    expect(calls.lastWhere((call) => call.method == 'setPlaybackActive').arguments,
        <String, bool>{'active': false});
  });

  test('la fenêtre PiP visible continue pendant hidden et paused', () async {
    playback.update(playing: true, casting: false);
    await event(inPip: true, visible: true);
    snapshot = <String, bool>{'inPip': true, 'visible': true};
    await playback.onLifecycle(AppLifecycleState.hidden);
    await playback.onLifecycle(AppLifecycleState.paused);
    expect(service.isInPipMode, isTrue);
    expect(service.isVisible, isTrue);
    expect(suspensions, isEmpty);
    expect(resumes, 0);
  });

  test('écran éteint en PiP : arrêt forcé malgré le mode physique encore vrai', () async {
    playback.update(playing: true, casting: false);
    await event(inPip: true, visible: true);
    await event(inPip: true, visible: false);
    expect(service.isInPipMode, isTrue);
    expect(service.isVisible, isFalse);
    expect(suspensions, <bool>[true]);
    expect(visibility.last, isFalse);
  });

  test('un arrêt natif confirme et renforce une pause de repli une seule fois', () async {
    // Un pont ancien ou une réponse invalide laisse d'abord le cycle normal
    // choisir son repli pause. Le onStop ultérieur, lui, impose un vrai arrêt.
    readSnapshot = () async => null;
    await playback.onLifecycle(AppLifecycleState.paused);
    expect(suspensions, <bool>[false]);

    await event(inPip: false, visible: false);
    await event(inPip: false, visible: false);
    expect(suspensions, <bool>[false, true]);

    await playback.onLifecycle(AppLifecycleState.resumed);
    await playback.onLifecycle(AppLifecycleState.resumed);
    expect(resumes, 1);
  });

  test('agrandir PiP ne coupe ni ne rouvre le lecteur', () async {
    await event(inPip: true, visible: true);
    snapshot = <String, bool>{'inPip': true, 'visible': true};
    await playback.onLifecycle(AppLifecycleState.paused);
    await event(inPip: false, visible: true);
    snapshot = <String, bool>{'inPip': false, 'visible': true};
    await playback.onLifecycle(AppLifecycleState.resumed);
    expect(service.isInPipMode, isFalse);
    expect(suspensions, isEmpty);
    expect(resumes, 0);
    expect(modeChanges, greaterThanOrEqualTo(2));
  });

  test('un instantané ancien ne remplace pas le nouvel événement Android', () async {
    final pending = Completer<Object?>();
    readSnapshot = () => pending.future;
    final background = playback.onLifecycle(AppLifecycleState.paused);
    await drain();
    await event(inPip: true, visible: true);
    pending.complete(<String, bool>{'inPip': false, 'visible': false});
    await background;
    expect(service.isInPipMode, isTrue);
    expect(service.isVisible, isTrue);
    expect(suspensions, isEmpty);
  });

  test('une pause asynchrone arrivée après resumed ne coupe pas le retour', () async {
    final pending = Completer<Object?>();
    readSnapshot = () => pending.future;
    final background = playback.onLifecycle(AppLifecycleState.paused);
    await drain();
    readSnapshot = () async => <String, bool>{'inPip': false, 'visible': true};
    await playback.onLifecycle(AppLifecycleState.resumed);
    pending.complete(<String, bool>{'inPip': false, 'visible': false});
    await background;
    expect(suspensions, isEmpty);
    expect(service.isVisible, isTrue);
  });

  test('une sortie ordinaire suspend une fois et reprend une fois', () async {
    snapshot = <String, bool>{'inPip': false, 'visible': false};
    await playback.onLifecycle(AppLifecycleState.hidden);
    await playback.onLifecycle(AppLifecycleState.paused);
    expect(suspensions, hasLength(1));
    snapshot = <String, bool>{'inPip': false, 'visible': true};
    await playback.onLifecycle(AppLifecycleState.resumed);
    await playback.onLifecycle(AppLifecycleState.resumed);
    expect(resumes, 1);
  });

  test('la réponse d’une route détruite ne suspend pas son successeur', () async {
    final pending = Completer<Object?>();
    readSnapshot = () => pending.future;
    final background = playback.onLifecycle(AppLifecycleState.paused);
    await drain();
    final previous = playback;
    playback = acquire();
    playback.update(playing: true, casting: false);
    await drain();
    calls.clear();
    previous.dispose();
    previous.update(playing: false, casting: false);
    pending.complete(<String, bool>{'inPip': false, 'visible': false});
    await background;
    await drain();
    expect(suspensions, isEmpty);
    expect(calls.where((call) => call.method == 'setPlaybackActive'), isEmpty,
        reason: 'l’ancien propriétaire ne peut pas désarmer le nouveau lecteur');
  });

  test('un appareil sans PiP conserve son cycle de vie sans appel Android', () async {
    playback.dispose();
    service.dispose();
    await drain();
    calls.clear();
    service = ZunoPipService.forTesting(enabled: false, channel: channel);
    playback = acquire();
    playback.update(playing: true, casting: false, width: 1920, height: 1080);
    await playback.onLifecycle(AppLifecycleState.paused);
    await playback.onLifecycle(AppLifecycleState.resumed);
    expect(calls, isEmpty);
    expect(suspensions, hasLength(1));
    expect(resumes, 1);
  });
}
