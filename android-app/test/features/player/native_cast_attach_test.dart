import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';

// Le vrai widget crée sa PlatformView et rattache le vrai controller. Seuls
// les messages Android sont simulés : on peut donc vérifier leur ordre exact
// sans lecteur matériel, réseau fournisseur ni identifiants client.
class _NativeCastWire {
  final calls = <MethodCall>[];
  final channels = <MethodChannel>[];
  final localOpens = <String>[];
  Map<String, dynamic>? current;
  bool suspended = false;

  Future<Object?> platformCall(MethodCall call) async {
    if (call.method == 'create') {
      final id = (call.arguments as Map)['id'] as int;
      final channel = MethodChannel('native_video_player/$id');
      channels.add(channel);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, nativeCall);
    }
    return null;
  }

  Future<Object?> nativeCall(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'suspendForCast':
        suspended = true;
      case 'setUrl':
        current = Map<String, dynamic>.from(call.arguments as Map);
        if (!suspended) localOpens.add(current!['url'] as String);
      case 'resumeAfterCast':
        suspended = false;
        if (current != null) localOpens.add(current!['url'] as String);
    }
    return null;
  }

  void close() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}

class _DesktopBackend extends NativeVideoBackend {
  final opened = <String>[];
  @override
  void bind(NativeVideoController controller) {}
  @override
  void open(Map<String, dynamic> args) => opened.add(args['url'] as String);
  @override
  void play() {}
  @override
  void pause() {}
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NativeCastWire wire;

  setUp(() {
    wire = _NativeCastWire();
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, wire.platformCall);
  });

  tearDown(() {
    wire.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
  });

  NativeVideoController makeController() {
    final controller = NativeVideoController(
      initialUrl: 'https://fixture.invalid/initial.ts',
    );
    addTearDown(() async {
      await controller.releaseNative();
      controller.dispose();
    });
    return controller;
  }

  Future<void> attach(WidgetTester tester, NativeVideoController controller) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(width: 320, height: 180,
          child: NativeVideoView(controller: controller)),
    ));
    await tester.pumpAndSettle();
    expect(wire.channels, hasLength(1));
  }

  for (final pending in <bool>[false, true]) {
    testWidgets('Cast déjà actif : suspendre avant '
        '${pending ? 'la dernière URL en attente' : 'la première URL'}',
        (tester) async {
      final controller = makeController();
      if (pending) {
        controller.setUrl('https://fixture.invalid/obsolete.ts');
        controller.setUrl('https://fixture.invalid/pending.mp4',
            vod: true, startAt: const Duration(seconds: 37),
            preferredAudio: 'fr', preferredText: 'en');
      }
      var notifications = 0;
      controller.addListener(() => notifications++);
      // Cet appel doit être utilisable depuis initState : pas de canal
      // requis et aucune notification synchrone pendant la construction.
      final suspension = controller.suspendForCast();
      expect(notifications, 0);
      await suspension;
      expect(notifications, 0);
      expect(controller.isPlaying, isFalse);
      expect(wire.calls, isEmpty);

      await attach(tester, controller);
      final methods = wire.calls.map((call) => call.method).toList();
      expect(methods.where((method) => method == 'suspendForCast'), hasLength(1));
      expect(methods.indexOf('suspendForCast'), lessThan(methods.indexOf('setUrl')));
      final urls = wire.calls.where((call) => call.method == 'setUrl').toList();
      expect(urls, hasLength(1));
      final args = Map<String, dynamic>.from(urls.single.arguments as Map);
      final expectedUrl = pending
          ? 'https://fixture.invalid/pending.mp4'
          : 'https://fixture.invalid/initial.ts';
      expect(args['url'], expectedUrl);
      if (pending) {
        expect(args['vod'], isTrue);
        expect(args['startMs'], 37000);
        expect(args['preferredAudio'], 'fr');
        expect(args['preferredText'], 'en');
      }
      expect(wire.localOpens, isEmpty,
          reason: 'le natif reçoit le verrou avant de connaître la première URL');

      await controller.resumeAfterCast();
      expect(wire.calls.last.method, 'resumeAfterCast');
      expect(wire.localOpens, <String>[expectedUrl]);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('annuler avant attach retire le verrou et conserve les reprises suivantes',
      (tester) async {
    final controller = makeController();
    await controller.suspendForCast();
    await controller.resumeAfterCast();
    await attach(tester, controller);
    expect(wire.calls.map((call) => call.method), isNot(contains('suspendForCast')));
    expect(wire.calls.map((call) => call.method), isNot(contains('resumeAfterCast')));
    expect(wire.localOpens, <String>['https://fixture.invalid/initial.ts']);

    await controller.suspendForCast();
    expect(wire.suspended, isTrue);
    controller.setUrl('https://fixture.invalid/next.ts');
    await tester.pump();
    expect(wire.localOpens, hasLength(1));
    await controller.resumeAfterCast();
    expect(wire.suspended, isFalse);
    expect(wire.localOpens, <String>[
      'https://fixture.invalid/initial.ts', 'https://fixture.invalid/next.ts',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test('le backend PC garde son ouverture et sa passation indépendante', () async {
    final backend = _DesktopBackend();
    NativeVideoController.backendFactory = () => backend;
    final controller = makeController();
    expect(backend.opened, <String>['https://fixture.invalid/initial.ts']);
    await expectLater(controller.suspendForCast(), throwsStateError);
    await controller.resumeAfterCast();
    controller.setUrl('https://fixture.invalid/desktop.ts');
    expect(backend.opened, <String>[
      'https://fixture.invalid/initial.ts', 'https://fixture.invalid/desktop.ts',
    ]);
    expect(wire.calls, isEmpty);
  });
}
