// Données locales constantes pour comparer l'accueil du 116 et L1-06.
// Cette préparation n'utilise aucun nouveau symbole de production : les
// régressions de reconstruction s'exécutent aussi sur le commit de référence.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/data/recently_watched_repository.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/presentation/tv_cinematic_home.dart';
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

class HubTickFixture {
  static final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  static final client = MockClient((_) async => http.Response('{}', 404));

  static Future<void> setUpAll() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final font in <String, String>{
      'Inter_regular': 'Inter-Regular.ttf',
      'Inter_500': 'Inter-Medium.ttf',
      'Inter_700': 'Inter-Bold.ttf',
      'JetBrainsMono_regular': 'JetBrainsMono-Regular.ttf',
      'JetBrainsMono_600': 'JetBrainsMono-SemiBold.ttf',
    }.entries) {
      final loader = FontLoader(font.key)
        ..addFont(rootBundle.load('assets/fonts/${font.value}'));
      await loader.load();
    }
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:12:34:AB:CD:56',
      'security.kids_mode.v1': false,
    });
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    PlaylistRepository.mergeAllPlaylists = true;
    await FavoritesRepository.instance.initialize();
    final repo = PlaylistRepository.instance;
    await repo.addM3uPlaylist(
      name: 'Catalogue de comparaison',
      url: 'http://fixture.invalid/hub.m3u',
      httpClient: MockClient(
        (_) async => http.Response(
          '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="hub-a" group-title="Info",Alpha\nhttp://fixture.invalid/a.ts\n'
          '#EXTINF:-1 tvg-id="hub-b" group-title="Info",Bravo\nhttp://fixture.invalid/b.ts\n',
          200,
        ),
      ),
    );
    await RecentlyWatchedRepository.instance.record(
      repo.currentChannels.last.id,
    );
  }

  static void setUp() {
    ParentalControls.instance.kidsMode.value = false;
    AnnouncementRepository.resetForTesting();
    AnnouncementRepository.client = client;
    AnnouncementRepository.baseUrl = 'https://fixture.invalid';
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.manzilionellm.tvking/device'),
      (call) async =>
          call.method == 'getAndroidId' ? 'fixture-only' : <String, String>{},
    );
  }

  static Future<void> tearDownAll() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.manzilionellm.tvking/device'),
      null,
    );
    AnnouncementRepository.resetForTesting();
  }

  static Widget app(Widget child) => MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark().copyWith(
      extensions: const [TvAppTokens(ghost: true)],
    ),
    home: Scaffold(body: child),
  );

  static Future<void> mount(
    WidgetTester tester, {
    Widget child = const TvHubScreen(),
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      AnnouncementRepository.resetForTesting();
    });
    await tester.pumpWidget(app(child));
    // Attend les vrais accès SQLite et isolates, puis les pauses 150/400 ms
    // d'assemblage. L'horloge de vingt secondes n'a pas encore sonné.
    for (int i = 0; i < 12; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(GoogleFonts.pendingFonts);
    await tester.pump();
    expect(find.byType(TvCinematicHome), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  static TvCinematicHome home(WidgetTester tester) =>
      tester.widget<TvCinematicHome>(find.byType(TvCinematicHome));

  static Announcement notice(int id, String title) => Announcement(
    id: id,
    title: title,
    body: 'Message de comparaison',
    url: '',
    kind: 'info',
    cta: '',
    createdAt: 0,
  );
}
