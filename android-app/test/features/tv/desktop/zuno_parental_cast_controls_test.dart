import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cast/domain/zuno_cast_media.dart';
import 'package:tv_king/features/tv/desktop/desktop_cast_controls.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import '../../cast/data/cast_parental_fixture.dart';

class _LocalPlayer extends NativeVideoController {
  Completer<void>? release;
  int suspends = 0;
  int resumes = 0;
  @override
  Future<void> suspendForCast() async {
    suspends++;
    await release?.future;
  }

  @override
  Future<void> resumeAfterCast() async {
    resumes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
  const url = 'https://fixture.invalid/film.mp4';
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(capability, (_) async => true);
    await prepareCastProfile();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(capability, null);
    AppPlatform.isZuno = false;
    AppPlatform.isTv = false;
  });

  for (final classified in [true, false]) {
    testWidgets(
        classified
            ? 'Enfants : passation VOD classée et session conservée après fermeture'
            : 'Enfants : controls refuse la passation VOD non classée',
        (tester) async {
      await CastPlatform.initializeZuno();
      final receiver = ParentalTransport();
      final manager = parentalManager(receiver)..selectDevice(parentalDevice);
      final local = _LocalPlayer();
      try {
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: DesktopCastControls(
            controller: local,
            manager: manager,
            streamUrl: url,
            title: 'Film de test',
            castOnOpen: true,
            zunoMedia: ZunoCastMedia(
                id: 'vod-fixture',
                streamUrl: url,
                playlistId: 7,
                isAdult: classified ? false : null),
          )),
        ));
        await tester.pumpAndSettle();
        expect(receiver.played.length, classified ? 1 : 0);
        expect(local.suspends, classified ? greaterThan(0) : 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (classified) expect(manager.hasActiveSession, isTrue);
        expect(local.resumes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await manager.disconnect();
        manager.dispose();
        local.dispose();
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('réponse de passation après changement de profil : aucun Cast',
      (tester) async {
    await CastPlatform.initializeZuno();
    final receiver = ParentalTransport();
    final manager = parentalManager(receiver)..selectDevice(parentalDevice);
    final release = Completer<void>();
    final local = _LocalPlayer()..release = release;
    try {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: DesktopCastControls(
          controller: local,
          manager: manager,
          streamUrl: url,
          title: 'Film de test',
          castOnOpen: true,
          zunoMedia: const ZunoCastMedia(
              id: 'vod-fixture', streamUrl: url, playlistId: 7, isAdult: false),
        )),
      ));
      await tester.pump();
      expect(local.suspends, greaterThan(0));
      await prepareCastProfile(kids: false, sources: null);
      release.complete();
      await tester.pumpAndSettle();
      expect(receiver.played, isEmpty);
      expect(local.resumes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      if (!release.isCompleted) release.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await manager.disconnect();
      manager.dispose();
      local.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
