import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/tv/data/zuno_pip_service.dart';
import 'package:tv_king/features/tv/desktop/desktop_cast_controls.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_vod_player_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'la VOD téléchargée garde le fichier local et son URL Cast réseau',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    NativeVideoController.backendFactory = null;
    NativeVideoController.audiblePlayers.debugReset();
    NativeVideoController.appInBackground = false;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
    final nativeChannels = <MethodChannel>[];
    final nativeCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(capability, (_) async => true);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final int id = (call.arguments as Map)['id'] as int;
        final channel = MethodChannel('native_video_player/$id');
        nativeChannels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          return null;
        });
      }
      return null;
    });
    final pip = ZunoPipService.forTesting(enabled: false);
    ZunoPipService.debugOverride = pip;
    await CastPlatform.initializeZuno();
    await CastManager.instance.disconnect();

    Future<void> drain() async {
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    const remote = 'https://fixture.invalid/movie.mp4';
    const local = '/data/user/0/app/files/movie.mp4';
    try {
      // Vrai écran et vraie PlatformView : seule la frontière Android est
      // simulée, pour observer quelle source arrive à chaque destination.
      await tester.pumpWidget(const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('fr'),
        home: TvVodPlayerScreen(
          item: VodPlayItem(
              id: 'download-fixture',
              isEpisode: false,
              title: 'Film téléchargé',
              url: remote),
          localPath: local,
        ),
      ));
      await drain();
      final opens =
          nativeCalls.where((call) => call.method == 'setUrl').toList();
      expect(opens, hasLength(1));
      expect((opens.single.arguments as Map)['url'], local);
      final controls =
          tester.widget<DesktopCastControls>(find.byType(DesktopCastControls));
      expect(controls.streamUrl, remote);
      expect(controls.castOnOpen, isTrue);
      expect(nativeCalls.where((call) => call.method == 'suspendForCast'),
          isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await drain();
      await CastManager.instance.disconnect();
      ZunoPipService.debugOverride = null;
      pip.dispose();
      for (final channel in nativeChannels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      messenger.setMockMethodCallHandler(capability, null);
      NativeVideoController.appInBackground = false;
      NativeVideoController.backendFactory = null;
      NativeVideoController.audiblePlayers.debugReset();
      tester.view.reset();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
