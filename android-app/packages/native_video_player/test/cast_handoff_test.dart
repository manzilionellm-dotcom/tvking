import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

class _Backend extends NativeVideoBackend {
  final List<Map<String, dynamic>> opens = [];
  final List<Map<String, dynamic>?> resumes = [];
  Completer<void>? stopGate;
  Completer<void>? resumeGate;
  bool stopFails = false;
  int stops = 0;
  int plays = 0;
  int pauses = 0;
  int silences = 0;
  int disposals = 0;

  @override
  void bind(NativeVideoController controller) {}
  @override
  void open(Map<String, dynamic> args) => opens.add(Map.of(args));
  @override
  void play() => plays++;
  @override
  void pause() => pauses++;
  @override
  void silence() => silences++;
  @override
  void seekTo(Duration position) {}
  @override
  void selectTrack(NativeTrack track) {}
  @override
  void disableSubtitles() {}
  @override
  Widget buildView(BuildContext context) => const SizedBox.shrink();
  @override
  void dispose() => disposals++;

  @override
  Future<void> suspendForCast() async {
    stops++;
    if (stopFails) throw StateError('Arrêt non confirmé');
    await stopGate?.future;
  }

  @override
  Future<void> resumeAfterCast(Map<String, dynamic>? args) async {
    resumes.add(args == null ? null : Map.of(args));
    await resumeGate?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<_Backend> engines = [];
  final List<NativeVideoController> controllers = [];

  NativeVideoController controller({String? initialUrl, bool vod = false}) {
    final NativeVideoController result = NativeVideoController(
      initialUrl: initialUrl,
      openAsVod: vod,
    );
    controllers.add(result);
    return result;
  }

  setUp(() {
    engines.clear();
    controllers.clear();
    NativeVideoController.audiblePlayers.debugReset();
    NativeVideoController.appInBackground = false;
    NativeVideoController.backendFactory = () {
      final _Backend result = _Backend();
      engines.add(result);
      return result;
    };
  });

  tearDown(() {
    for (final NativeVideoController c in controllers) {
      c.dispose();
    }
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    NativeVideoController.appInBackground = false;
    debugDefaultTargetPlatformOverride = null;
  });

  test('le transfert attend Stop et conserve le dernier zap sans ouvrir',
      () async {
    final NativeVideoController c =
        controller(initialUrl: 'https://media.example.invalid/a.ts');
    final _Backend backend = engines.single;
    backend.stopGate = Completer<void>();
    bool completed = false;
    final Future<void> stop = c.suspendForCast().then((_) => completed = true);
    expect(c.castSuspended, isTrue);
    expect(c.audible, isFalse);
    c.setUrl('https://media.example.invalid/b.ts');
    c.setUrl('https://media.example.invalid/c.ts');
    c.play();
    c.pause();
    c.suspendForBackground();
    c.resumeFromBackground();
    c.applyBackendEvent('playing', true);
    c.applyBackendEvent('error', 'ancienne lecture');
    c.applyBackendEvent('position', 99000);
    c.applyBackendEvent('appBackground', true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(backend.opens, hasLength(1));
    expect(backend.plays, 0);
    expect(backend.pauses, 0);
    expect(c.isPlaying, isFalse);
    expect(c.hasError, isFalse);
    expect(c.position, Duration.zero);
    expect(NativeVideoController.appInBackground, isTrue);
    backend.stopGate!.complete();
    await stop;
    expect(c.castSuspended, isTrue);
    expect(backend.opens, hasLength(1));
    await c.resumeAfterCast();
    expect(c.castSuspended, isFalse);
    expect(
        backend.resumes.single!['url'], 'https://media.example.invalid/c.ts');
  });

  test('la reprise VOD garde la position et une pause choisie avant le Cast',
      () async {
    final NativeVideoController c = controller();
    c.setUrl('https://media.example.invalid/film.mp4', vod: true);
    c.applyBackendEvent('position', 42000);
    c.pause();
    await c.suspendForCast();
    c.applyBackendEvent('position', 0);
    await c.resumeAfterCast();
    final Map<String, dynamic> args = engines.single.resumes.single!;
    expect(args['url'], 'https://media.example.invalid/film.mp4');
    expect(args['startMs'], 42000);
    expect(args['play'], isFalse);
  });

  test('un nouveau choix de la même URL ne reprend pas la vieille position',
      () async {
    final NativeVideoController c = controller();
    c.setUrl('https://media.example.invalid/film.mp4', vod: true);
    c.applyBackendEvent('position', 42000);
    await c.suspendForCast();
    c.setUrl(
      'https://media.example.invalid/film.mp4',
      vod: true,
      startAt: const Duration(seconds: 3),
      preferredAudio: 'fr',
      preferredText: 'en',
    );
    await c.resumeAfterCast();
    final Map<String, dynamic> args = engines.single.resumes.single!;
    expect(args['startMs'], 3000);
    expect(args['preferredAudio'], 'fr');
    expect(args['preferredText'], 'en');
    expect(args['play'], isTrue);
  });

  test('le direct ne reprend jamais à sa vieille position VOD', () async {
    final NativeVideoController c = controller();
    c.setUrl('https://media.example.invalid/film.mp4', vod: true);
    c.applyBackendEvent('position', 42000);
    await c.suspendForCast();
    c.setUrl('https://media.example.invalid/live.ts');
    await c.resumeAfterCast();
    expect(engines.single.resumes.single!['startMs'], isNull);
    expect(engines.single.resumes.single!['vod'], isNull);
  });

  test('un échec Stop refuse le transfert et toute reprise automatique',
      () async {
    final NativeVideoController c =
        controller(initialUrl: 'https://media.example.invalid/a.ts');
    final _Backend backend = engines.single..stopFails = true;
    await expectLater(c.suspendForCast(), throwsStateError);
    expect(c.castSuspended, isTrue);
    c.play();
    c.resumeFromBackground();
    await expectLater(c.resumeAfterCast(), throwsStateError);
    expect(backend.resumes, isEmpty);
    expect(backend.plays, 0);
    backend.stopFails = false;
    await c.suspendForCast();
    await c.resumeAfterCast();
    expect(backend.stops, 2);
    expect(backend.resumes, hasLength(1));
  });

  test('dispose pendant Stop invalide le transfert et la reprise en attente',
      () async {
    final NativeVideoController c =
        controller(initialUrl: 'https://media.example.invalid/a.ts');
    final _Backend backend = engines.single..stopGate = Completer<void>();
    final Future<void> stop = c.suspendForCast();
    final Future<void> expectation = expectLater(stop, throwsStateError);
    c.dispose();
    backend.stopGate!.complete();
    await expectation;
    await c.resumeAfterCast();
    expect(backend.resumes, isEmpty);
    expect(backend.disposals, 1);
  });

  test('un autre contrôleur révoque le transfert et les réponses tardives',
      () async {
    final NativeVideoController first =
        controller(initialUrl: 'https://media.example.invalid/a.ts');
    final _Backend firstBackend = engines.single..stopGate = Completer<void>();
    final Future<void> stopped = first.suspendForCast();
    final Future<void> expectation = expectLater(stopped, throwsStateError);
    final NativeVideoController second = controller();
    second.setUrl('https://media.example.invalid/b.ts');
    firstBackend.stopGate!.complete();
    await expectation;
    first.applyBackendEvent('playing', true);
    await first.resumeAfterCast();
    expect(firstBackend.resumes, isEmpty);
    expect(first.isPlaying, isFalse);
    expect(second.audible, isTrue);
  });

  test('une révocation pendant la reprise reste opposable aux futurs setUrl',
      () async {
    final NativeVideoController first =
        controller(initialUrl: 'https://media.example.invalid/a.ts');
    final _Backend firstBackend = engines.single
      ..resumeGate = Completer<void>();
    await first.suspendForCast();
    final Future<void> resume = first.resumeAfterCast();
    await Future<void>.delayed(Duration.zero);
    expect(first.castSuspended, isFalse);
    final NativeVideoController second = controller();
    second.setUrl('https://media.example.invalid/b.ts');
    firstBackend.resumeGate!.complete();
    await resume;
    first.setUrl('https://media.example.invalid/stale-retry.ts');
    first.play();
    first.resumeFromBackground();
    await first.resumeAfterCast();
    expect(first.castSuspended, isTrue);
    expect(firstBackend.opens, hasLength(1));
    expect(firstBackend.resumes, hasLength(1));
    expect(firstBackend.plays, 0);
    expect(second.audible, isTrue);
  });

  testWidgets(
      'une vue native attachée pendant le Cast attend et garde le dernier choix',
      (tester) async {
    NativeVideoController.backendFactory = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final List<MethodCall> calls = [];
    final Completer<void> nativeStop = Completer<void>();
    MethodChannel? channel;
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final int id = (call.arguments as Map)['id'] as int;
        channel = MethodChannel('native_video_player/$id');
        messenger.setMockMethodCallHandler(channel!, (call) async {
          calls.add(call);
          if (call.method == 'suspendForCast') await nativeStop.future;
          return null;
        });
      }
      return null;
    });
    final NativeVideoController c =
        controller(initialUrl: 'https://media.example.invalid/a.ts');
    await c.suspendForCast();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
          width: 400, height: 200, child: NativeVideoView(controller: c)),
    ));
    await tester.pump();
    expect(calls.where((c) => c.method == 'setUrl'), isEmpty);
    expect(calls.where((c) => c.method == 'suspendForCast'), hasLength(1));
    c.setUrl('https://media.example.invalid/last.mp4',
        vod: true, startAt: const Duration(seconds: 8));
    final Future<void> resumed = c.resumeAfterCast();
    await tester.pump();
    expect(calls.where((c) => c.method == 'resumeAfterCast'), isEmpty);
    nativeStop.complete();
    await resumed;
    final MethodCall resume =
        calls.singleWhere((c) => c.method == 'resumeAfterCast');
    expect((resume.arguments as Map)['url'],
        'https://media.example.invalid/last.mp4');
    expect((resume.arguments as Map)['startMs'], 8000);
    await c.releaseNative();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    if (channel != null) messenger.setMockMethodCallHandler(channel!, null);
    debugDefaultTargetPlatformOverride = null;
  });
}
