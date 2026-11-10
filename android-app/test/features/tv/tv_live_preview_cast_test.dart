// Retour vers Direct pendant un Cast : aucun aperçu ne doit ouvrir un second
// flux. Le gestionnaire reçoit ses événements natifs habituels ; les vraies
// vues natives passent par un messager simulé. Aucune URL n'est contactée.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:native_video_player/playback_lease.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_transport.dart';
import 'package:tv_king/features/cast/data/google_cast_api.dart';
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/presentation/tv_live_preview.dart';

class _Transport implements CastTransport {
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
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<MethodChannel> natives = <MethodChannel>[];
  final List<MethodCall> calls = <MethodCall>[];
  late CastManager manager;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    ForegroundPlayback.debugReset();
    manager = CastManager.forTesting(
      transportFactory: (_) => _Transport(),
      probe: (url) async =>
          StreamProbeResult(originalUrl: url, finalUrl: url, success: true),
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (MethodCall call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map<Object?, Object?>)['id']! as int;
        final channel = MethodChannel('native_video_player/$id');
        natives.add(channel);
        messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return null;
        });
      }
      return null;
    });
  });

  tearDown(() async {
    await manager.disconnect();
    manager.dispose();
    for (final channel in natives) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    natives.clear();
    calls.clear();
    NativeVideoController.audiblePlayers.debugReset();
    ForegroundPlayback.debugReset();
  });

  Future<void> startCast(WidgetTester tester) async {
    // Une session issue du choix du profil possède réellement son transport.
    // Une reprise SDK orpheline ne constitue plus une autorisation de lecture.
    await manager.castTo(
        const CastDevice(
          id: 'preview-cast',
          name: 'TV fictive',
          kind: CastDeviceKind.googleCast,
          host: '192.0.2.1',
          port: 8009,
          controlUrl: '',
        ),
        streamUrl: 'https://fixture.invalid/cast.ts',
        title: 'Cast fictif');
    await tester.pump();
  }

  Future<void> session(WidgetTester tester, String event) async {
    manager.debugNativeSessionEvent(CastNativeSessionEvent(event));
    await tester.pump();
  }

  Future<void> show(WidgetTester tester, String id) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 470,
              height: 264,
              child: TvLivePreview(
                castManager: manager,
                channel: Channel(
                  id: id,
                  name: 'Chaîne fictive $id',
                  category: 'Info',
                  streamUrl: 'https://fixture.invalid/$id.ts',
                  isLive: true,
                ),
                debounce: const Duration(milliseconds: 1500),
              ),
            ),
          ),
        ),
      );

  testWidgets('Cast conservé au retour : aucun aperçu avant la déconnexion',
      (WidgetTester tester) async {
    await startCast(tester);
    await session(tester, 'resumed');
    expect(manager.hasActiveSession, isTrue);
    await show(tester, 'premiere');
    await tester.pump(const Duration(seconds: 3));
    expect(natives, isEmpty);
    expect(find.byType(NativeVideoView), findsNothing);

    await manager.pause();
    await tester.pump();
    expect(manager.state, CastState.paused);
    await show(tester, 'seconde');
    await tester.pump(const Duration(seconds: 3));
    expect(natives, isEmpty, reason: 'une pause distante reste un Cast actif');

    await session(tester, 'suspended');
    expect(manager.hasActiveSession, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(natives, isEmpty, reason: 'la reprise Wi-Fi ne libère pas le flux');

    await session(tester, 'ended');
    expect(manager.hasActiveSession, isFalse);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(natives, isEmpty, reason: 'le délai normal reste respecté');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(natives, hasLength(1));
    final opens = calls.where((call) => call.method == 'setUrl').toList();
    expect(opens, hasLength(1));
    expect((opens.single.arguments as Map<Object?, Object?>)['url'],
        'https://fixture.invalid/seconde.ts');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('un Cast coupe l’aperçu et aucun écouteur ne survit à Direct',
      (WidgetTester tester) async {
    await show(tester, 'locale');
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(natives, hasLength(1));
    expect(find.byType(NativeVideoView), findsOneWidget);

    await startCast(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NativeVideoView), findsNothing);
    expect(calls.where((call) => call.method == 'dispose'), hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    expect(natives, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await session(tester, 'ended');
    await tester.pump(const Duration(seconds: 3));
    expect(natives, hasLength(1), reason: 'aucun redémarrage après dispose');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
