import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:tv_king/features/recordings/data/recording_repository.dart';

class _Backend extends NativeVideoBackend {
  Completer<void>? closing;
  bool stopFails = false;
  final List<String> opens = <String>[];
  final List<String?> resumes = <String?>[];
  @override
  void bind(NativeVideoController controller) {}
  @override
  void open(Map<String, dynamic> args) => opens.add(args['url'] as String);
  @override
  void play() {}
  @override
  void pause() {}
  @override
  void silence() {}
  @override
  void seekTo(Duration position) {}
  @override
  void selectTrack(NativeTrack track) {}
  @override
  void disableSubtitles() {}
  @override
  Widget buildView(BuildContext context) => const SizedBox.shrink();
  @override
  void dispose() {}
  @override
  Future<void> suspendForCast() async {
    if (stopFails) throw StateError('Fermeture non confirmée');
    await closing?.future;
  }

  @override
  Future<void> resumeAfterCast(Map<String, dynamic>? args) async {
    resumes.add(args?['url'] as String?);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<_Backend> backends = <_Backend>[];
  final List<NativeVideoController> controllers = <NativeVideoController>[];
  NativeVideoController create(String url) {
    final NativeVideoController controller =
        NativeVideoController(initialUrl: url);
    controllers.add(controller);
    return controller;
  }

  setUp(() {
    backends.clear();
    controllers.clear();
    NativeVideoController.audiblePlayers.debugReset();
    NativeVideoController.backendFactory = () {
      final _Backend backend = _Backend();
      backends.add(backend);
      return backend;
    };
  });
  tearDown(() {
    for (final NativeVideoController controller in controllers) {
      controller.dispose();
    }
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
  });

  test('REC attend la fermeture native avant de reprendre sur le relais',
      () async {
    final NativeVideoController controller =
        create('https://source.example.invalid/live');
    final _Backend backend = backends.single;
    backend.closing = Completer<void>();
    bool closed = false;
    final Future<void> stopped = controller.suspendForRecording().then((_) {
      closed = true;
    });
    controller.setUrl('http://127.0.0.1:1234/stream.ts');
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(backend.opens, hasLength(1));
    expect(backend.resumes, isEmpty);
    backend.closing!.complete();
    await stopped;
    await controller.resumeAfterRecording();
    expect(backend.resumes, <String>['http://127.0.0.1:1234/stream.ts']);
    expect(controller.recordingSourceHeld, isFalse);
    expect(controller.castSuspended, isFalse);
  });

  test(
      'REC : fermeture échouée refuse toute reprise jusqu’au nouvel arrêt confirmé',
      () async {
    final NativeVideoController controller =
        create('https://source.example.invalid/live');
    final _Backend backend = backends.single..stopFails = true;
    await expectLater(controller.suspendForRecording(), throwsStateError);
    controller.setUrl('http://127.0.0.1:1234/stream.ts');
    await expectLater(controller.resumeAfterRecording(), throwsStateError);
    expect(backend.resumes, isEmpty);
    expect(controller.recordingSourceHeld, isTrue);
    backend.stopFails = false;
    await controller.suspendForRecording();
    controller.setUrl('https://source.example.invalid/live');
    await controller.resumeAfterRecording();
    expect(backend.resumes, <String>['https://source.example.invalid/live']);
  });

  test('REC ne prend pas un lecteur déjà réservé au Cast', () async {
    final NativeVideoController controller =
        create('https://source.example.invalid/live');
    await controller.suspendForCast();
    await expectLater(controller.suspendForRecording(), throwsStateError);
    expect(controller.recordingSourceHeld, isFalse);
    expect(controller.castSuspended, isTrue);
  });

  test('REC ne conserve pas un faux historique de transfert Cast', () async {
    final NativeVideoController controller =
        create('https://source.example.invalid/live');
    await controller.suspendForRecording();
    controller.setUrl('http://127.0.0.1:1234/stream.ts');
    await controller.resumeAfterRecording();
    create('https://source.example.invalid/other');
    expect(controller.castSuspended, isFalse,
        reason:
            'Le lecteur local normal est silencieux, sans verrou Cast résiduel');
  });

  test('vue détruite durant la fermeture REC : aucune ouverture tardive',
      () async {
    final NativeVideoController controller =
        create('https://source.example.invalid/live');
    final _Backend backend = backends.single;
    backend.closing = Completer<void>();
    final Future<void> stop = controller.suspendForRecording();
    final Future<void> asserted = expectLater(stop, throwsStateError);
    controller.dispose();
    backend.closing!.complete();
    await asserted;
    await controller.resumeAfterRecording();
    expect(backend.resumes, isEmpty);
  });

  test('deux captures du même nom gardent des chemins distincts', () async {
    final Directory directory =
        await Directory.systemTemp.createTemp('recording_paths_');
    const MethodChannel channel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (MethodCall call) async => directory.path);
    try {
      final List<String> paths = await Future.wait<String>(
          List<Future<String>>.generate(
              30,
              (_) => RecordingRepository.instance
                  .createFilePath(channelName: 'Même chaîne')));
      expect(paths.toSet(), hasLength(30));
      expect(paths.every((String path) => path.endsWith('.ts')), isTrue);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    }
  });
}
