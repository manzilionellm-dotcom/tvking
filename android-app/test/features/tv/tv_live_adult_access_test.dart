// Vrai Direct 117 : le périmètre adulte est séparé avant tout aperçu/lecteur.
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
import 'package:tv_king/features/channels/domain/adult_channel_policy.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/data/zuno_pip_service.dart';
import 'package:tv_king/features/tv/presentation/tv_live_preview.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_source_setup.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final natives = <MethodChannel>[];
  final calls = <MethodCall>[];
  Completer<void>? releaseGate;
  final pip = ZunoPipService.forTesting(enabled: false);
  final repo = PlaylistRepository.instance;
  const capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
  const device = MethodChannel('com.manzilionellm.tvking/device');

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(
        {'device.virtual_mac.v1': 'MK:12:34:AB:CD:56'});
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    PlaylistRepository.mergeAllPlaylists = true;
    await FavoritesRepository.instance.initialize();
    await repo.initialize();
    await repo.addM3uPlaylist(
      name: 'Catalogue fixture',
      url: 'https://fixture.invalid/all.m3u',
      httpClient: MockClient((_) async => http.Response(
          '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="a" group-title="Info",Alpha\nhttps://fixture.invalid/a.ts\n'
          '#EXTINF:-1 tvg-id="b" group-title="Info",Bravo\nhttps://fixture.invalid/b.ts\n'
          '#EXTINF:-1 tvg-id="x" group-title="Adult",Adult One\nhttps://fixture.invalid/x.ts\n'
          '#EXTINF:-1 tvg-id="y" group-title="Adult",Adult Two\nhttps://fixture.invalid/y.ts\n',
          200)),
    );
    final hidden = await repo.addM3uPlaylist(
      name: 'Masquée',
      url: 'https://fixture.invalid/hidden.m3u',
      httpClient: MockClient((_) async => http.Response(
          '#EXTM3U\n#EXTINF:-1 tvg-id="hidden" group-title="Adult",Adult Hidden\nhttps://fixture.invalid/hidden.ts\n',
          200)),
    );
    await repo.setPlaylistHidden(hidden.id!, true);
  });

  tearDownAll(() async {
    pip.dispose();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
  });

  setUp(() async {
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    await ParentalControls.instance.load();
    await repo.initialize();
    RemoteSourceRepository.syncing.value =
        true; // pas de deuxième import au montage
    ForegroundPlayback.debugReset();
    NativeVideoController.audiblePlayers.debugReset();
    ZunoPipService.debugOverride = pip;
    messenger.setMockMethodCallHandler(capability, (_) async => false);
    messenger.setMockMethodCallHandler(
        device,
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
    calls.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(capability, null);
    messenger.setMockMethodCallHandler(device, null);
    ZunoPipService.debugOverride = null;
    RemoteSourceRepository.syncing.value = false;
    ForegroundPlayback.debugReset();
    NativeVideoController.audiblePlayers.debugReset();
  });

  Future<AdultAccessGrant> grant() async {
    final access = await authenticateAdultAccess(
        reason: 'Accès fixture', confirmPin: () async => true);
    expect(access, isNotNull);
    addTearDown(access!.dispose);
    return access;
  }

  Future<void> show(WidgetTester tester, {AdultAccessGrant? access}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark()
          .copyWith(extensions: const [TvAppTokens(ghost: true)]),
      home: Scaffold(body: TvLiveScreen(adultAccess: access)),
    ));
    await tester.runAsync(GoogleFonts.pendingFonts);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }

  for (final adult in [false, true]) {
    testWidgets('Direct ${adult ? "adulte" : "normal"} : aperçu et zap séparés',
        (tester) async {
      await http.runWithClient(() async {
        final access = adult ? await tester.runAsync(grant) : null;
        await show(tester, access: access);
        final preview =
            tester.widget<TvLivePreview>(find.byType(TvLivePreview));
        expect(isAdultChannel(preview.channel), adult);
        expect(find.text(adult ? 'Alpha' : 'Adult One'), findsNothing);
        expect(find.text('Adult Hidden'), findsNothing);
        final target = adult ? 'Adult One' : 'Alpha';
        await tester.tap(find.text(target).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final player =
            tester.widget<TvPlayerScreen>(find.byType(TvPlayerScreen));
        expect(player.channels.map((c) => c.name),
            adult ? ['Adult One', 'Adult Two'] : ['Alpha', 'Bravo']);
        expect(
            player.channels.every((c) => isAdultChannel(c) == adult), isTrue);
        expect(player.adultAccess, same(access));
        if (adult) {
          final created = natives.length;
          access!.revoke();
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(NativeVideoView), findsNothing);
          expect(calls.any((c) => c.method == 'dispose'), isTrue);
          expect(natives, hasLength(created),
              reason: 'le lecteur révoqué ne rouvre aucun flux');
        }
        await stop(tester);
      }, () => MockClient((_) async => http.Response('{}', 404)));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('accord déjà révoqué : aucune chaîne, aucun aperçu ni formulaire',
      (tester) async {
    await http.runWithClient(() async {
      final access = (await tester.runAsync(grant))!..revoke();
      await show(tester, access: access);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(TvLivePreview), findsNothing);
      expect(find.byType(TvSourceSetup), findsNothing);
      expect(find.text('Adult One'), findsNothing);
      expect(natives, isEmpty);
      await stop(tester);
    }, () => MockClient((_) async => http.Response('{}', 404)));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final change in ['revoke', 'kids', 'profile']) {
    testWidgets('$change coupe aussi un aperçu adulte déjà ouvert',
        (tester) async {
      await http.runWithClient(() async {
        final access = (await tester.runAsync(grant))!;
        await show(tester, access: access);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(natives, hasLength(1));
        switch (change) {
          case 'revoke':
            access.revoke();
          case 'kids':
            ParentalControls.instance.kidsMode.value = true;
          case 'profile':
            ActiveProfile.instance.set('p2');
        }
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(access.isValid, isFalse);
        expect(find.byType(TvLivePreview), findsNothing);
        expect(find.text('Adult One'), findsNothing);
        expect(natives, hasLength(1),
            reason: 'aucun redémarrage après révocation');
        expect(calls.any((c) => c.method == 'dispose'), isTrue);
        await stop(tester);
      }, () => MockClient((_) async => http.Response('{}', 404)));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets(
      'source retirée pendant la fermeture de l’aperçu : pas de lecteur périmé',
      (tester) async {
    await http.runWithClient(() async {
      final playlistId = repo.currentChannels.first.playlistId!;
      await show(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(natives, hasLength(1));
      releaseGate = Completer<void>();
      await tester.tap(find.text('Alpha').first);
      await tester.pump();
      expect(find.byType(TvPlayerScreen), findsNothing);
      await tester.runAsync(() => repo.setPlaylistHidden(playlistId, true));
      await tester.pump();
      releaseGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(TvPlayerScreen), findsNothing);
      expect(natives, hasLength(1));
      await stop(tester);
      await tester.runAsync(() => repo.setPlaylistHidden(playlistId, false));
    }, () => MockClient((_) async => http.Response('{}', 404)));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
