// Vrai lecteur 117, vraie PlatformView à frontière Android simulée : le doigt
// change l'URL sans recréer le lecteur, y compris avant la première image.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:native_video_player/playback_lease.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/tv/core/tv_activity.dart';
import 'package:tv_king/features/tv/core/tv_zap.dart';
import 'package:tv_king/features/tv/data/zuno_pip_service.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const _capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
const _device = MethodChannel('com.manzilionellm.tvking/device');

Channel _channel(String id) => Channel(
      id: id,
      name: 'Chaîne $id',
      category: 'Info',
      streamUrl: 'https://fixture.invalid/$id.ts',
      isLive: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final natives = <MethodChannel>[];
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final pip = ZunoPipService.forTesting(enabled: false);

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    await PlaylistDatabase.instance.database;
    await FavoritesRepository.instance.initialize();
  });
  tearDownAll(() async {
    pip.dispose();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:12:34:AB:CD:56',
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    RepairFlags.debugReset();
    ZunoPipService.debugOverride = pip;
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    ForegroundPlayback.debugReset();
    messenger.setMockMethodCallHandler(_capability, (_) async => true);
    messenger.setMockMethodCallHandler(
        _device,
        (call) async => call.method == 'getAndroidId'
            ? 'fixture-only'
            : <String, String>{});
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'] as int;
        final channel = MethodChannel('native_video_player/$id');
        natives.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
      }
      return null;
    });
  });
  tearDown(() {
    for (final channel in natives) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(_capability, null);
    messenger.setMockMethodCallHandler(_device, null);
    ZunoPipService.debugOverride = null;
    natives.clear();
    calls.clear();
    ForegroundPlayback.debugReset();
    NativeVideoController.audiblePlayers.debugReset();
  });

  test('geste vertical : lent, rapide, tremblement et sens', () {
    expect(tvSwipeZapDelta(distance: -80, velocity: 0), 1);
    expect(tvSwipeZapDelta(distance: 80, velocity: 0), -1);
    expect(tvSwipeZapDelta(distance: -20, velocity: -800), 1);
    expect(tvSwipeZapDelta(distance: 20, velocity: 800), -1);
    expect(tvSwipeZapDelta(distance: -24, velocity: -100), 0);
    expect(tvSwipeZapDelta(distance: 0, velocity: 0), 0);
  });

  for (final count in <int>[3, 1]) {
    testWidgets('lecteur mobile : glissés et retour, $count chaîne(s)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await CastPlatform.initializeZuno();
      final navigator = GlobalKey<NavigatorState>();
      final channels = List<Channel>.generate(count, (i) => _channel('c$i'));
      final client = MockClient((_) async => http.Response(
          '{"exists":true,"status":"active","paid":true,"plan":"lifetime",'
          '"frozen":false,"expired":false,"source_rev":0}',
          200));
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('fr'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: Text('Accueil fixture')),
        ));
        navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => TvPlayerScreen(channels: channels, startIndex: 0),
        ));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(natives, hasLength(1));
        final video = tester.element(find.byType(NativeVideoView));
        List<MethodCall> opens() =>
            calls.where((c) => c.method == 'setUrl').toList();
        String lastUrl() => (opens().last.arguments as Map)['url'] as String;
        expect(opens(), hasLength(1));
        expect(lastUrl(), 'https://fixture.invalid/c0.ts');
        expect(TvActivity.isBusy, isTrue);

        final gestureArea = find.descendant(
          of: find.byType(TvPlayerScreen),
          matching: find.byWidgetPredicate((widget) =>
              widget is GestureDetector && widget.onVerticalDragEnd != null),
        ).first;
        // Toujours en attente d'image : le chargement ne doit pas capter le geste.
        await tester.timedDrag(gestureArea,
            const Offset(0, -180), const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 220));
        expect(lastUrl(), 'https://fixture.invalid/c${count > 1 ? 1 : 0}.ts');
        expect(opens(), hasLength(count > 1 ? 2 : 1));
        expect(tester.element(find.byType(NativeVideoView)), same(video));
        expect(TvActivity.isBusy, isTrue);

        await tester.timedDrag(gestureArea,
            const Offset(0, 180), const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 220));
        expect(lastUrl(), 'https://fixture.invalid/c0.ts');

        await tester.fling(
            gestureArea, const Offset(0, -100), 800);
        await tester.pump(const Duration(milliseconds: 220));
        expect(lastUrl(), 'https://fixture.invalid/c${count > 1 ? 1 : 0}.ts');
        final beforeJitter = opens().length;
        await tester.timedDrag(gestureArea,
            const Offset(0, -24), const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 220));
        expect(opens(), hasLength(beforeJitter));
        expect(natives, hasLength(1));
        expect(tester.takeException(), isNull);
        navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(find.text('Accueil fixture'), findsOneWidget);
        expect(TvActivity.isBusy, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull);
      }, () => client);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
