// Capture opt-in : mêmes sources de test utilisables sur le vrai 116 et le
// candidat, sans modification de leur code de production. L'horloge civile
// est figée dans flutter_tester par fixed_capture_clock.c ; les délais restent
// monotones. Ce fichier ne fait pas partie de la suite *_test.dart.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/data/recently_watched_repository.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/simple_home/data/announcement_repository.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_type.dart';
import 'package:tv_king/features/tv/presentation/tv_cinematic_home.dart';
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const screen = String.fromEnvironment('ZUNO_CAPTURE_SCREEN');
  const output = String.fromEnvironment('ZUNO_CAPTURE_FILE');
  const sha = String.fromEnvironment('ZUNO_CAPTURE_SOURCE_SHA');
  final instant = DateTime.utc(2026, 11, 11, 17);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final client = MockClient((_) async => http.Response('{}', 404));
  final repo = PlaylistRepository.instance;
  const palette = TvAppTokens(ghost: true);
  const names = ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot'];
  const categories = [
    'Info',
    'Sports',
    'Films',
    'Enfants',
    'Documentaires',
    'Info'
  ];

  setUpAll(() async {
    if (!['hub', 'direct'].contains(screen) ||
        output.isEmpty ||
        sha.length != 40) {
      throw StateError('Écran hub/direct, fichier et SHA source exact requis.');
    }
    expect(DateTime.now().toUtc(), instant,
        reason: 'Refuser une capture dont l’horloge civile n’est pas figée.');
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final font in <String, String>{
      'Inter_regular': 'Inter-Regular.ttf',
      'Inter_500': 'Inter-Medium.ttf',
      'Inter_600': 'Inter-SemiBold.ttf',
      'Inter_700': 'Inter-Bold.ttf',
      'Inter_800': 'Inter-ExtraBold.ttf',
      'JetBrainsMono_regular': 'JetBrainsMono-Regular.ttf',
      'JetBrainsMono_600': 'JetBrainsMono-SemiBold.ttf',
    }.entries) {
      await (FontLoader(font.key)
            ..addFont(rootBundle.load('assets/fonts/${font.value}')))
          .load();
    }
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk == null || sdk.isEmpty) throw StateError('FLUTTER_ROOT requis');
    final icons = await File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons))))
        .load();

    // État synthétique neuf, sans lecture ni effacement d'un appareil client.
    AppPlatform.isZuno = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:12:34:AB:CD:56',
      'security.kids_mode.v1': false,
    });
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    AppPlatform.configureZuno(isAndroidHandset: false);
    await ParentalControls.instance.load();
    expect(ActiveProfile.instance.id, 'p1');
    expect(ParentalControls.instance.kidsMode.value, isFalse);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    PlaylistRepository.mergeAllPlaylists = true;
    await FavoritesRepository.instance.initialize();
    final playlist = StringBuffer('#EXTM3U\n');
    for (var i = 0; i < names.length; i++) {
      playlist.writeln(
          '#EXTINF:-1 tvg-id="capture-$i" group-title="${categories[i]}",${names[i]}');
      playlist.writeln('https://fixture.invalid/capture-$i.ts');
    }
    await repo.addM3uPlaylist(
      name: 'Catalogue de comparaison',
      url: 'https://fixture.invalid/capture.m3u',
      httpClient:
          MockClient((_) async => http.Response(playlist.toString(), 200)),
    );
    expect(repo.currentChannels.map((c) => c.name), names);
    await ChannelPrecompute.run(repo.currentChannels);
    await FavoritesRepository.instance.toggle(repo.currentChannels.first.id);
    await RecentlyWatchedRepository.instance.record(repo.currentChannels[1].id);
    RemoteSourceRepository.syncing.value = true;
    AnnouncementRepository.resetForTesting();
    AnnouncementRepository.client = client;
    AnnouncementRepository.baseUrl = 'https://fixture.invalid';
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.manzilionellm.tvking/device'),
      (call) async =>
          call.method == 'getAndroidId' ? 'fixture-only' : <String, String>{},
    );
  });

  tearDownAll(() async {
    RemoteSourceRepository.syncing.value = false;
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.manzilionellm.tvking/device'), null);
    AnnouncementRepository.resetForTesting();
    AppPlatform.isZuno = false;
  });

  testWidgets('capture $screen ZUNO p1 à 17:00 UTC', (tester) async {
    await http.runWithClient(() async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: child!,
          ),
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: palette.bg,
            colorScheme: ColorScheme.dark(
                surface: palette.card, primary: palette.accent),
            extensions: const [palette],
            useMaterial3: true,
            textTheme: TvType.material(palette.text),
            splashFactory: NoSplash.splashFactory,
          ),
          home: const Scaffold(
              body: screen == 'hub'
                  ? TvHubScreen()
                  : TvShell(child: TvLiveScreen())),
        ),
      ));
      // Douze pas identiques : accès SQLite et assemblages terminés, avant
      // le délai d'aperçu vidéo de 1,5 s. Les pixels vidéo ne sont pas simulés.
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(GoogleFonts.pendingFonts);
      await tester.pump();
      expect(AppPlatform.isZuno, isTrue);
      expect(ActiveProfile.instance.id, 'p1');
      expect(ParentalControls.instance.kidsMode.value, isFalse);
      expect(repo.currentChannels.map((c) => c.name), names);
      expect(DateTime.now().toUtc(), instant);
      if (screen == 'hub') {
        expect(find.byType(TvCinematicHome), findsOneWidget);
        expect(find.text('17:00'), findsOneWidget);
      } else {
        expect(find.text('Alpha'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File(output);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png.buffer.asUint8List());
          await File('$output.json')
              .writeAsString(const JsonEncoder.withIndent('  ').convert({
            'sourceSha': sha,
            'screen': screen,
            'product': 'ZUNO TV',
            'profile': 'p1',
            'kidsMode': false,
            'locale': 'fr',
            'utc': instant.toIso8601String(),
            'size': [1920, 1080],
            'devicePixelRatio': 1,
            'textScale': 1,
            'theme': 'Phantom Black',
            'catalog': names,
            'categories': categories,
            'favorite': 'Alpha',
            'recent': 'Bravo',
            'cache':
                'classification préparée ; préférences et SQLite synthétiques',
            'pumpedMs': 1200,
            'buildType': 'Flutter widget test ; aucun APK',
            'clock':
                'CLOCK_REALTIME figé dans flutter_tester ; CLOCK_MONOTONIC inchangé',
          }));
        } finally {
          image.dispose();
        }
      });
    }, () => client);
  });
}
