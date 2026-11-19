import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/ads/data/startup_ad_repository.dart';
import 'package:tv_king/features/ads/presentation/tv_startup_ad_screen.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/presentation/tv_live_preview.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

// La vraie PlatformView est créée (messages Android simulés) : c'est son
// Focus, posé par PlatformViewLink, qui attirait le D-pad.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final List<MethodChannel> natives = <MethodChannel>[];
  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (MethodCall call) async {
      if (call.method == 'create') {
        final int id = (call.arguments as Map<Object?, Object?>)['id']! as int;
        final MethodChannel channel = MethodChannel('native_video_player/$id');
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
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final MethodChannel channel in natives) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    natives.clear();
    calls.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    NativeVideoController.audiblePlayers.debugReset();
  });

  Future<void> fromNative(
      WidgetTester tester, String method, Object? arguments) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      natives.single.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall(method, arguments)),
      (ByteData? _) {},
    );
    await tester.pump();
  }

  testWidgets('Direct : la vidéo d’aperçu ne prend jamais le focus',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);
    final FocusNode row = FocusNode(debugLabel: 'channel');
    addTearDown(row.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 400,
              height: 74,
              child: TvFocusable(
                focusNode: row,
                autofocus: true,
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(
              width: 470,
              height: 264,
              child: TvLivePreview(
                channel: Channel(
                  id: 'preview',
                  name: 'Aperçu',
                  category: 'Info',
                  streamUrl: 'https://fixture.invalid/live.ts',
                  isLive: true,
                ),
                debounce: Duration(milliseconds: 1),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(PlatformViewLink), findsOneWidget);
    expect(natives, hasLength(1));
    expect(row.hasPrimaryFocus, isTrue);

    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(row.hasPrimaryFocus, isTrue, reason: key.keyLabel);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('pub de démarrage : D-pad pendant la vidéo, OK passe la pub',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);
    int done = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: TvStartupAdScreen(
        config: const AdConfig(
          enabled: true,
          url: 'https://fixture.invalid/ad.mp4',
          skip: 1,
          freq: 'always',
        ),
        onDone: () => done++,
      ),
    ));
    await tester.pumpAndSettle();
    expect(natives, hasLength(1));

    // Impatient : on presse le D-pad avant que « Passer » n'apparaisse.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final MethodCall open =
        calls.lastWhere((MethodCall call) => call.method == 'setUrl');
    await fromNative(
        tester, 'ack', (open.arguments as Map<Object?, Object?>)['epoch']);
    await fromNative(tester, 'firstFrame', null);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsOneWidget);

    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowDown,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(done, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
