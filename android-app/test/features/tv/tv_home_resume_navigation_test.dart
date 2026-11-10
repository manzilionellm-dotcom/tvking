// Clic sur le vrai héros de l'accueil 117 : le lecteur reçoit le catalogue
// accessible et l'index de la chaîne choisie, pas une liste d'un seul élément.
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
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/channels/data/recently_watched_repository.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/data/home_shelves.dart';
import 'package:tv_king/features/tv/data/zuno_pip_service.dart';
import 'package:tv_king/features/tv/presentation/tv_cinematic_home.dart';
import 'package:tv_king/features/tv/presentation/tv_home_rails.dart';
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final natives = <MethodChannel>[];
  final pip = ZunoPipService.forTesting(enabled: false);
  final repo = PlaylistRepository.instance;
  late Channel target;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:12:34:AB:CD:56',
      'security.kids_mode.v1': true,
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    PlaylistRepository.mergeAllPlaylists = true;
    await FavoritesRepository.instance.initialize();
    await repo.addM3uPlaylist(
        name: 'Visible',
        url: 'http://fixture.invalid/all.m3u',
        httpClient: MockClient((_) async => http.Response(
            '#EXTM3U\n'
            '#EXTINF:-1 tvg-id="a" group-title="Info",Alpha\nhttp://fixture.invalid/a.ts\n'
            '#EXTINF:-1 tvg-id="b" group-title="Info",Bravo\nhttp://fixture.invalid/b.ts\n'
            '#EXTINF:-1 tvg-id="c" group-title="Info",Charlie\nhttp://fixture.invalid/c.ts\n'
            '#EXTINF:-1 tvg-id="adult" group-title="Adult",Adult fixture\nhttp://fixture.invalid/adult.ts\n',
            200)));
    final hidden = await repo.addM3uPlaylist(
        name: 'Masquée',
        url: 'http://fixture.invalid/hidden.m3u',
        httpClient: MockClient((_) async => http.Response(
            '#EXTM3U\n#EXTINF:-1 tvg-id="hidden",Masquée\nhttp://fixture.invalid/hidden.ts\n',
            200)));
    await repo.setPlaylistHidden(hidden.id!, true);
    target = repo.currentChannels.singleWhere((c) => c.name == 'Bravo');
    await RecentlyWatchedRepository.instance.record(target.id);
  });

  tearDownAll(() async {
    pip.dispose();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
  });

  setUp(() {
    ParentalControls.instance.kidsMode.value = true;
    ZunoPipService.debugOverride = pip;
    ForegroundPlayback.debugReset();
    NativeVideoController.audiblePlayers.debugReset();
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.sevenmotion.zuno/cast-capability'),
        (_) async => true);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.manzilionellm.tvking/device'),
        (call) async => call.method == 'getAndroidId'
            ? 'fixture-only'
            : <String, String>{});
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'] as int;
        final channel = MethodChannel('native_video_player/$id');
        natives.add(channel);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      return null;
    });
  });

  tearDown(() {
    for (final channel in natives) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    natives.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.sevenmotion.zuno/cast-capability'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.manzilionellm.tvking/device'), null);
    ZunoPipService.debugOverride = null;
    ParentalControls.instance.kidsMode.value = false;
    ForegroundPlayback.debugReset();
    NativeVideoController.audiblePlayers.debugReset();
  });

  Widget app(Widget child) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark()
            .copyWith(extensions: const [TvAppTokens(ghost: true)]),
        home: Scaffold(body: child),
      );

  for (final kids in <bool>[false, true]) {
  testWidgets(
      'clic héros Reprendre : catalogue public, index exact, enfants=$kids',
      (tester) async {
    ParentalControls.instance.kidsMode.value = kids;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await CastPlatform.initializeZuno();
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const TvHubScreen()));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }
      final home = find.byType(TvCinematicHome);
      expect(home, findsOneWidget);
      expect(tester.widget<TvCinematicHome>(home).board.hero!.channel!.id,
          target.id);
      await tester.tap(find
          .descendant(of: home, matching: find.byIcon(Icons.play_arrow_rounded))
          .first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final player = tester.widget<TvPlayerScreen>(find.byType(TvPlayerScreen));
      expect(player.channels.map((c) => c.name), ['Alpha', 'Bravo', 'Charlie']);
      expect(player.startIndex, 1);
      expect(player.channels[player.startIndex].streamUrl, target.streamUrl);
      expect(natives, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets(
      'ancienne rangée Reprendre : même catalogue et carte sélectionnée',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<Channel>? received;
    int? selected;
    await tester.pumpWidget(app(TvHomeRails(
      model: HomeShelfModel(resume: [target]),
      nowMs: 0,
      onPlayChannel: (channels, index) {
        received = channels;
        selected = index;
      },
      onPlayContinue: (_) {},
      onPlayReminder: (_) {},
    )));
    await tester.pump();
    await tester.tap(find.text(target.cleanName));
    expect(received!.map((c) => c.name), ['Alpha', 'Bravo', 'Charlie']);
    expect(selected, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
