import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:native_video_player/native_video_player.dart';

import 'package:tv_king/features/tv/desktop/media_kit_video_backend.dart';

class _Player extends PlatformPlayer {
  _Player() : super(configuration: const PlayerConfiguration());

  final List<({Media media, bool play})> opened = [];
  final Completer<void> openStarted = Completer<void>();
  final Completer<void> stopStarted = Completer<void>();
  final Completer<void> volumeStarted = Completer<void>();
  final Completer<void> disposed = Completer<void>();
  Completer<void>? openingGate;
  Completer<void>? stoppingGate;
  Completer<void>? volumeGate;
  bool stopFails = false;
  bool hasNetworkMedia = false;
  int stops = 0;
  int plays = 0;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((media: playable as Media, play: play));
    if (!openStarted.isCompleted) openStarted.complete();
    await openingGate?.future;
    hasNetworkMedia = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (!stopStarted.isCompleted) stopStarted.complete();
    await stoppingGate?.future;
    if (stopFails) throw StateError('Stop refusé');
    hasNetworkMedia = false;
  }

  @override
  Future<void> play() async => plays++;
  @override
  Future<void> pause() async {}
  @override
  Future<void> setVolume(double volume) async {
    if (!volumeStarted.isCompleted) volumeStarted.complete();
    await volumeGate?.future;
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    hasNetworkMedia = false;
    if (!disposed.isCompleted) disposed.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Player player;
  late NativeVideoController controller;

  setUp(() {
    NativeVideoController.audiblePlayers.debugReset();
    player = _Player();
    NativeVideoController.backendFactory =
        () => MediaKitVideoBackend.forTesting(
              player: Player(platformPlayer: player),
            );
    controller = NativeVideoController();
  });

  tearDown(() async {
    if (player.openingGate case final Completer<void> gate
        when !gate.isCompleted) {
      gate.complete();
    }
    if (player.stoppingGate case final Completer<void> gate
        when !gate.isCompleted) {
      gate.complete();
    }
    if (player.volumeGate case final Completer<void> gate
        when !gate.isCompleted) {
      gate.complete();
    }
    controller.dispose();
    await player.disposed.future;
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
  });

  test('Windows attend ouverture en vol puis Stop, et annule les zaps en file',
      () async {
    player.openingGate = Completer<void>();
    player.stoppingGate = Completer<void>();
    controller.setUrl('https://media.example.invalid/a.ts');
    await player.openStarted.future;
    controller.setUrl('https://media.example.invalid/b.ts');
    bool transferred = false;
    final Future<void> transfer =
        controller.suspendForCast().then((_) => transferred = true);
    await Future<void>.delayed(Duration.zero);
    expect(player.stops, 0);
    expect(transferred, isFalse);
    player.openingGate!.complete();
    await player.stopStarted.future;
    expect(player.hasNetworkMedia, isTrue);
    expect(transferred, isFalse);
    player.stoppingGate!.complete();
    await transfer;
    expect(player.hasNetworkMedia, isFalse);
    expect(player.opened.map((entry) => entry.media.uri),
        ['https://media.example.invalid/a.ts']);
    controller.setUrl('https://media.example.invalid/c.ts');
    controller.play();
    controller.resumeFromBackground();
    expect(player.plays, 0);
    await controller.resumeAfterCast();
    expect(player.opened.map((entry) => entry.media.uri), [
      'https://media.example.invalid/a.ts',
      'https://media.example.invalid/c.ts',
    ]);
  });

  test(
      'Windows ne lance pas une ouverture devenue obsolète pendant ses réglages',
      () async {
    player.volumeGate = Completer<void>();
    controller.setUrl('https://media.example.invalid/a.ts');
    await player.volumeStarted.future;
    final Future<void> transfer = controller.suspendForCast();
    player.volumeGate!.complete();
    await transfer;
    expect(player.opened, isEmpty);
    expect(player.stops, 1);
    expect(player.hasNetworkMedia, isFalse);
  });

  test('Windows propage un Stop échoué et garde tout démarrage local bloqué',
      () async {
    controller.setUrl('https://media.example.invalid/a.ts');
    await player.openStarted.future;
    await Future<void>.delayed(Duration.zero);
    player.stopFails = true;
    await expectLater(controller.suspendForCast(), throwsStateError);
    expect(controller.castSuspended, isTrue);
    expect(player.hasNetworkMedia, isTrue);
    controller.setUrl('https://media.example.invalid/b.ts');
    controller.play();
    await expectLater(controller.resumeAfterCast(), throwsStateError);
    expect(player.opened, hasLength(1));
    expect(player.plays, 0);
    player.stopFails = false;
    await controller.suspendForCast();
    expect(player.hasNetworkMedia, isFalse);
    await controller.resumeAfterCast();
    expect(player.opened.last.media.uri, 'https://media.example.invalid/b.ts');
  });

  test('Windows reprend le bon film à sa position tout en conservant la pause',
      () async {
    controller.setUrl('https://media.example.invalid/film.mp4', vod: true);
    await player.openStarted.future;
    controller.applyBackendEvent('position', 54000);
    controller.pause();
    await controller.suspendForCast();
    await controller.resumeAfterCast();
    expect(player.opened.last.media.start, const Duration(seconds: 54));
    expect(player.opened.last.play, isFalse);
  });

  test('un zap déclenché par la fin du transfert remplace la reprise en file',
      () async {
    controller.setUrl('https://media.example.invalid/a.ts');
    await player.openStarted.future;
    await controller.suspendForCast();
    bool changed = false;
    controller.addListener(() {
      if (!controller.castSuspended && !changed) {
        changed = true;
        controller.setUrl('https://media.example.invalid/last.ts');
      }
    });
    await controller.resumeAfterCast();
    await Future<void>.delayed(Duration.zero);
    expect(player.opened.map((entry) => entry.media.uri), [
      'https://media.example.invalid/a.ts',
      'https://media.example.invalid/last.ts',
    ]);
  });

  test(
      'Windows dispose pendant Stop interdit tout transfert ou reprise tardifs',
      () async {
    player.stoppingGate = Completer<void>();
    controller.setUrl('https://media.example.invalid/a.ts');
    await player.openStarted.future;
    final Future<void> transfer = controller.suspendForCast();
    final Future<void> expectation = expectLater(transfer, throwsStateError);
    await player.stopStarted.future;
    controller.dispose();
    player.stoppingGate!.complete();
    await expectation;
    await controller.resumeAfterCast();
    await player.disposed.future;
    expect(player.opened, hasLength(1));
    expect(player.hasNetworkMedia, isFalse);
  });
}
