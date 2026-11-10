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
import 'package:tv_king/features/cast/data/google_cast_api.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/presentation/tv_live_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<MethodChannel> natives = <MethodChannel>[];
  final List<MethodCall> calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    ForegroundPlayback.debugReset();
    CastManager.instance.debugNativeSessionEvent(
      const CastNativeSessionEvent('ended'),
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

  tearDown(() {
    CastManager.instance.debugNativeSessionEvent(
      const CastNativeSessionEvent('ended'),
    );
    for (final channel in natives) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    natives.clear();
    calls.clear();
    NativeVideoController.audiblePlayers.debugReset();
    ForegroundPlayback.debugReset();
  });

  Future<void> nativeCastEvent(
    WidgetTester tester,
    String method,
    Map<String, Object> arguments,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'com.manzilionellm.tvking/cast',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      (ByteData? _) {},
    );
    await tester.pump();
  }

  Future<void> session(WidgetTester tester, String event) async {
    // L'entrée de test existante place l'événement dans l'horloge du widget.
    // Le singleton a été créé avant FakeAsync : son abonnement au stream
    // natif garderait sinon une autre horloge pour le délai de l'aperçu.
    CastManager.instance.debugNativeSessionEvent(CastNativeSessionEvent(event));
    await tester.pump();
  }

  Future<void> show(WidgetTester tester, String id) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 470,
              height: 264,
              child: TvLivePreview(
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
    await session(tester, 'resumed_at_boot');
    expect(CastManager.instance.hasActiveSession, isTrue);
    await show(tester, 'premiere');
    await tester.pump(const Duration(seconds: 3));
    expect(natives, isEmpty);
    expect(find.byType(NativeVideoView), findsNothing);

    await nativeCastEvent(tester, 'onMediaStateChanged', <String, Object>{
      'playerState': 'paused', 'isPaused': true,
    });
    expect(CastManager.instance.state, CastState.paused);
    await show(tester, 'seconde');
    await tester.pump(const Duration(seconds: 3));
    expect(natives, isEmpty, reason: 'une pause distante reste un Cast actif');

    await session(tester, 'suspended');
    expect(CastManager.instance.hasActiveSession, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(natives, isEmpty, reason: 'la reprise Wi-Fi ne libère pas le flux');

    await session(tester, 'ended');
    expect(CastManager.instance.hasActiveSession, isFalse);
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

    await session(tester, 'resumed');
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
