// L1-05 : tests du vrai écran, utilisables aussi sur le commit 116.
// Aucun nouveau symbole de production n'est nécessaire au scénario rouge.
import 'dart:async';

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
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';
import 'package:tv_king/features/tv/data/zuno_pip_service.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

class _BeforePlayerBuild extends NavigatorObserver {
  _BeforePlayerBuild(this.changeProfile);

  final VoidCallback changeProfile;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) changeProfile();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final repo = PlaylistRepository.instance;
  final natives = <MethodChannel>[];
  final pip = ZunoPipService.forTesting(enabled: false);
  const capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
  const device = MethodChannel('com.manzilionellm.tvking/device');
  late int primaryPlaylist;
  late int replacementPlaylist;
  Completer<void>? releaseGate;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({
      'device.virtual_mac.v1': 'MK:12:34:AB:CD:56',
    });
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    PlaylistRepository.mergeAllPlaylists = true;
    await FavoritesRepository.instance.initialize();
    await repo.initialize();
    primaryPlaylist = (await repo.addM3uPlaylist(
      name: 'Source initiale fixture',
      url: 'https://fixture.invalid/initial.m3u',
      httpClient: MockClient(
        (_) async => http.Response(
          '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="a" group-title="Info",Alpha\nhttps://fixture.invalid/a.ts\n'
          '#EXTINF:-1 tvg-id="b" group-title="Info",Bravo\nhttps://fixture.invalid/b.ts\n'
          '#EXTINF:-1 tvg-id="x" group-title="Adult",Adult Hidden\nhttps://fixture.invalid/x.ts\n',
          200,
        ),
      ),
    ))
        .id!;
    replacementPlaylist = (await repo.addM3uPlaylist(
      name: 'Source de remplacement fixture',
      url: 'https://fixture.invalid/replacement.m3u',
      httpClient: MockClient(
        (_) async => http.Response(
          '#EXTM3U\n#EXTINF:-1 tvg-id="g" group-title="Info",Gamma\nhttps://fixture.invalid/g.ts\n',
          200,
        ),
      ),
    ))
        .id!;
    await repo.setPlaylistHidden(replacementPlaylist, true);
  });

  tearDownAll(() async {
    pip.dispose();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
  });

  setUp(() async {
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    await ParentalControls.instance.load();
    await repo.setPlaylistHidden(primaryPlaylist, false);
    await repo.setPlaylistHidden(replacementPlaylist, true);
    await repo.initialize();
    RemoteSourceRepository.syncing.value = true;
    ForegroundPlayback.debugReset();
    NativeVideoController.audiblePlayers.debugReset();
    ZunoPipService.debugOverride = pip;
    messenger.setMockMethodCallHandler(capability, (_) async => false);
    messenger.setMockMethodCallHandler(
      device,
      (call) async =>
          call.method == 'getAndroidId' ? 'fixture-only' : <String, String>{},
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'] as int;
        final channel = MethodChannel('native_video_player/$id');
        natives.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'dispose') await releaseGate?.future;
          return null;
        });
      }
      return null;
    });
    await CastPlatform.initializeZuno();
  });

  tearDown(() {
    if (releaseGate?.isCompleted == false) releaseGate!.complete();
    releaseGate = null;
    for (final channel in natives) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    natives.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(capability, null);
    messenger.setMockMethodCallHandler(device, null);
    ZunoPipService.debugOverride = null;
    RemoteSourceRepository.syncing.value = false;
    ForegroundPlayback.debugReset();
    NativeVideoController.audiblePlayers.debugReset();
  });

  Future<void> show(WidgetTester tester, {NavigatorObserver? observer}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Le nettoyage précède le retrait des faux canaux natifs même si une
    // assertion échoue : aucune erreur de dispose ne pollue le test suivant.
    addTearDown(() async {
      if (releaseGate?.isCompleted == false) releaseGate!.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: observer == null ? const [] : [observer],
        theme: ThemeData.dark().copyWith(
          extensions: const [TvAppTokens(ghost: true)],
        ),
        home: const Scaffold(body: TvLiveScreen()),
      ),
    );
    await tester.runAsync(GoogleFonts.pendingFonts);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  VoidCallback selectAlpha(WidgetTester tester) => tester
      .widget<TvFocusBuilder>(
        find
            .ancestor(
              of: find.text('Alpha').first,
              matching: find.byType(TvFocusBuilder),
            )
            .first,
      )
      .onSelect!;

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }

  testWidgets('L1-05 chaîne autorisée : ouverture et ordre de zap conservés', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await show(tester);
      await tester.tap(find.text('Alpha').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final player = tester.widget<TvPlayerScreen>(find.byType(TvPlayerScreen));
      expect(player.channels.map((c) => c.name), ['Alpha', 'Bravo']);
      expect(player.channels[player.startIndex].name, 'Alpha');
      await stop(tester);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('L1-05 index ancien : remplacement du catalogue refusé', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await show(tester);
      // Le callback de la ligne Alpha a été choisi AVANT le changement.
      // Le vrai 116 relit ensuite la liste courante et ouvre Gamma à sa place.
      final staleSelection = selectAlpha(tester);
      await tester.runAsync(
        () => repo.setPlaylistHidden(primaryPlaylist, true),
      );
      await tester.runAsync(
        () => repo.setPlaylistHidden(replacementPlaylist, false),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Gamma'), findsWidgets);
      staleSelection();
      await tester.idle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byType(TvPlayerScreen),
        findsNothing,
        reason: 'un ancien choix ne doit jamais ouvrir la nouvelle case',
      );
      await stop(tester);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('L1-05 profil changé avant le premier build du lecteur', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await show(
        tester,
        observer: _BeforePlayerBuild(
          () => ActiveProfile.instance.set('p2', playlistIds: const []),
        ),
      );
      selectAlpha(tester)();
      await tester.idle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(TvPlayerScreen), findsNothing);
      await stop(tester);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final change in ['profile', 'restrictions', 'catalogue']) {
    testWidgets('L1-05 $change modifié pendant la fermeture de l’aperçu', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await show(tester);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(natives, hasLength(1));
        releaseGate = Completer<void>();
        selectAlpha(tester)();
        await tester.pump();
        expect(find.byType(TvPlayerScreen), findsNothing);
        switch (change) {
          case 'profile':
            ActiveProfile.instance.set('p2', playlistIds: const []);
          case 'restrictions':
            ParentalControls.instance.kidsMode.value = true;
          case 'catalogue':
            await tester.runAsync(
              () => repo.setPlaylistHidden(primaryPlaylist, true),
            );
        }
        await tester.pump();
        releaseGate!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(TvPlayerScreen), findsNothing);
        await stop(tester);
      }, () => MockClient((_) async => http.Response('{}', 404)));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
