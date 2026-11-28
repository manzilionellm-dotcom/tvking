import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';
import 'package:tv_king/features/tv/data/zuno_pip_service.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_vod_player_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

// Le vrai écran conserve sa vraie PlatformView : seule la frontière Android
// est simulée. Cela détecte une recréation ou une seconde ouverture de flux.
class _VideoWire {
  final channels = <MethodChannel>[];
  final calls = <MethodCall>[];

  Future<Object?> platformCall(MethodCall call) async {
    if (call.method == 'create') {
      final id = (call.arguments as Map)['id'] as int;
      final channel = MethodChannel('native_video_player/$id');
      channels.add(channel);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
    }
    return null;
  }

  void close() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  const pipChannel = MethodChannel('com.sevenmotion.zuno/pip-widget-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final pauseOnly in <bool>[false, true]) {
    testWidgets('PiP garde la même vidéo et le même flux, repli pause=$pauseOnly',
        (tester) async {
      // Tout est initialisé dans la zone fakeAsync du scénario : les futures
      // de préférences et leurs timers sont alors purgés par tester.pump.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      NativeVideoController.backendFactory = null;
      NativeVideoController.audiblePlayers.debugReset();
      NativeVideoController.backgroundPauseOnly = pauseOnly;
      NativeVideoController.appInBackground = false;
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      final wire = _VideoWire();
      var snapshot = <String, bool>{'inPip': false, 'visible': true};
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, wire.platformCall);
      messenger.setMockMethodCallHandler(pipChannel, (call) async {
        if (call.method == 'getPipState') return snapshot;
        if (call.method == 'isPipSupported') return true;
        return null;
      });
      final service = ZunoPipService.forTesting(enabled: true, channel: pipChannel);
      ZunoPipService.debugOverride = service;

      Future<void> drain() async {
        for (var n = 0; n < 5; n++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      Future<void> pip({required bool inPip, required bool visible}) async {
        snapshot = <String, bool>{'inPip': inPip, 'visible': visible};
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          pipChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onPipModeChanged', snapshot),
          ),
          (_) => done.complete(),
        );
        await done.future;
        await drain();
      }

      try {
        await tester.pumpWidget(const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('fr'),
          home: TvVodPlayerScreen(item: VodPlayItem(
            id: 'pip-fixture',
            isEpisode: false,
            title: 'Film de test',
            url: 'https://fixture.invalid/movie.mp4',
          )),
        ));
        await drain();
        expect(wire.channels, hasLength(1));
        final opens = wire.calls.where((call) => call.method == 'setUrl').toList();
        expect(opens, hasLength(1));
        final element = tester.element(find.byType(NativeVideoView));
        final controller = tester.widget<NativeVideoView>(find.byType(NativeVideoView)).controller;
        controller.applyBackendEvent('ack', (opens.single.arguments as Map)['epoch']);
        controller.applyBackendEvent('videoFormat', <String, int>{'width': 1920, 'height': 1080});
        controller.applyBackendEvent('firstFrame', null);
        controller.applyBackendEvent('playing', true);
        await drain();
        wire.calls.clear();

        await pip(inPip: true, visible: true);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.view.physicalSize = const Size(320, 180);
        await drain();
        expect(tester.element(find.byType(NativeVideoView)), same(element));
        expect(wire.channels, hasLength(1));
        expect(tester.takeException(), isNull);

        // Le callback natif peut précéder « resumed ». Il ne doit pas faire
        // croire que l'activité vient d'être réellement masquée.
        await pip(inPip: false, visible: true);
        tester.view.physicalSize = const Size(1280, 720);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await drain();
        expect(tester.element(find.byType(NativeVideoView)), same(element));
        expect(wire.channels, hasLength(1));
        expect(wire.calls.map((call) => call.method),
            isNot(anyOf(contains('setUrl'), contains('pause'), contains('suspend'),
                contains('resume'), contains('play'))));
        expect(controller.isPlaying, isTrue);
        expect(tester.takeException(), isNull);

        // Une reconnexion déjà armée ne doit pas rouvrir le flux une seconde
        // après avoir fermé la fenêtre, même avec le repli « pause » activé.
        controller.applyBackendEvent('error', null);
        await tester.pump();
        await pip(inPip: true, visible: false);
        expect(wire.calls.where((call) => call.method == 'suspend'), hasLength(1));
        await tester.pump(const Duration(seconds: 3));
        expect(wire.calls.where((call) => call.method == 'setUrl'), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await drain();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        ZunoPipService.debugOverride = null;
        service.dispose();
        wire.close();
        messenger.setMockMethodCallHandler(pipChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        NativeVideoController.backgroundPauseOnly = false;
        NativeVideoController.appInBackground = false;
        NativeVideoController.backendFactory = null;
        NativeVideoController.audiblePlayers.debugReset();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }


  testWidgets('la reprise démarre avant la fiche série et reconnecte le bon épisode',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cinema.pref.audio': 'sv',
      'cinema.pref.text': 'fr',
    });
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PlaylistDatabase.debugFilePath = ':memory:';
      await DownloadsRepository.instance.initialize();
    });
    final wire = _VideoWire();
    final metadata = Completer<SeriesDetails?>();
    var requests = 0;
    final episodes = List.generate(2, (i) => CinemaEpisode(
      id: 'ep-$i', remoteId: '$i', seriesId: 'serie', season: 1, number: i + 1,
      title: 'Test', streamUrl: 'https://fixture.invalid/ep-$i.mp4', containerExt: 'mp4',
    ));
    const series = CinemaTitle(id: 'serie', kind: CinemaKind.series, sourceKey: 'test',
        remoteId: 'serie', name: 'Série', categoryKey: 'test', searchKey: 'serie');
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    NativeVideoController.appInBackground = false;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, wire.platformCall);
    final service = ZunoPipService.forTesting(enabled: false, channel: pipChannel);
    ZunoPipService.debugOverride = service;
    Future<void> drain() async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }
    List<Map> opens() => [
      for (final call in wire.calls)
        if (call.method == 'setUrl') call.arguments as Map,
    ];
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: TvVodPlayerScreen(
          item: VodPlayItem.episode(episodes.first, series), seriesTitle: series,
          localPath: '/storage/episode-offline.mp4', startAt: const Duration(minutes: 2),
          loadSeries: () { requests++; return metadata.future; },
        ),
      ));
      await drain();
      final first = opens().single;
      expect(first['url'], '/storage/episode-offline.mp4');
      expect(first['startMs'], 120000);
      expect(first['preferredAudio'], 'sv');
      expect(first['preferredText'], 'fr');
      expect(requests, 0);
      final video = tester.widget<NativeVideoView>(find.byType(NativeVideoView)).controller;
      video.applyBackendEvent('ack', first['epoch']);
      video.applyBackendEvent('firstFrame', null);
      video.applyBackendEvent('playing', true);
      await tester.pump(const Duration(seconds: 4));
      expect(metadata.isCompleted, isFalse);
      expect(requests, 1);
      metadata.complete(SeriesDetails(
        details: CinemaDetails.empty,
        seasons: const [CinemaSeason(number: 1, name: '1')], episodes: {1: episodes},
      ));
      await drain();
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await drain();
      final second = opens().last;
      expect(second['url'], episodes.last.streamUrl);
      video.applyBackendEvent('ack', second['epoch']);
      video.applyBackendEvent('error', null);
      await tester.pump(const Duration(seconds: 2));
      await drain();
      final attempts = opens();
      expect(attempts, hasLength(3));
      expect(attempts.last['url'], episodes.last.streamUrl);
      expect(attempts.last['startMs'], isNull);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await drain();
      wire.close();
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      ZunoPipService.debugOverride = null;
      service.dispose();
      NativeVideoController.audiblePlayers.debugReset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.runAsync(() => PlaylistDatabase.instance.closeForTesting());
      PlaylistDatabase.debugFilePath = null;
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('un film fini en PiP attend le vrai retour visible avant de fermer',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    NativeVideoController.appInBackground = false;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    final wire = _VideoWire();
    final navigator = GlobalKey<NavigatorState>();
    var snapshot = <String, bool>{'inPip': false, 'visible': true};
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, wire.platformCall);
    messenger.setMockMethodCallHandler(pipChannel, (call) async {
      if (call.method == 'getPipState') return snapshot;
      return null;
    });
    final service = ZunoPipService.forTesting(enabled: true, channel: pipChannel);
    ZunoPipService.debugOverride = service;

    Future<void> drain() async {
      for (var n = 0; n < 5; n++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> pip({required bool inPip, required bool visible}) async {
      snapshot = <String, bool>{'inPip': inPip, 'visible': visible};
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        pipChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onPipModeChanged', snapshot),
        ),
        (_) => done.complete(),
      );
      await done.future;
      await drain();
    }

    try {
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: const SizedBox(key: ValueKey<String>('catalogue')),
      ));
      var returnedToCatalogue = false;
      unawaited(navigator.currentState!.push<void>(MaterialPageRoute<void>(
        builder: (_) => const TvVodPlayerScreen(item: VodPlayItem(
          id: 'pip-ended-fixture',
          isEpisode: false,
          title: 'Film terminé',
          url: 'https://fixture.invalid/ended.mp4',
        )),
      )).then((_) => returnedToCatalogue = true));
      await drain();
      await tester.pump(const Duration(milliseconds: 400));
      final open = wire.calls.singleWhere((call) => call.method == 'setUrl');
      final controller = tester.widget<NativeVideoView>(find.byType(NativeVideoView)).controller;
      controller.applyBackendEvent('ack', (open.arguments as Map)['epoch']);
      controller.applyBackendEvent('firstFrame', null);
      controller.applyBackendEvent('playing', true);
      await pip(inPip: true, visible: true);

      controller.applyBackendEvent('playing', false);
      controller.applyBackendEvent('ended', null);
      await drain();
      expect(returnedToCatalogue, isFalse);
      expect(find.byType(TvVodPlayerScreen), findsOneWidget);

      // Certains appareils retirent le drapeau PiP alors que l'activité est
      // encore arrêtée : ne pas découvrir le catalogue sous cette fenêtre.
      await pip(inPip: false, visible: false);
      expect(returnedToCatalogue, isFalse);
      expect(find.byType(TvVodPlayerScreen), findsOneWidget);

      await pip(inPip: false, visible: true);
      await tester.pump(const Duration(milliseconds: 400));
      expect(returnedToCatalogue, isTrue);
      expect(find.byType(TvVodPlayerScreen), findsNothing);
      expect(find.byKey(const ValueKey<String>('catalogue')), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await drain();
      ZunoPipService.debugOverride = null;
      service.dispose();
      wire.close();
      messenger.setMockMethodCallHandler(pipChannel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      NativeVideoController.appInBackground = false;
      NativeVideoController.audiblePlayers.debugReset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
