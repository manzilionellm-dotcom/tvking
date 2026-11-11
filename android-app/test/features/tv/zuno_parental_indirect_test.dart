import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:native_video_player/playback_lease.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/data/zuno_pip_service.dart';
import 'package:tv_king/features/tv/presentation/tv_channel_guide_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_detail_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_vod_player_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const channel = Channel(
    id: 'l103-indirect',
    name: 'Quenovar',
    category: '',
    streamUrl: 'https://fixture.invalid/live',
    isLive: true,
    logoUrl: 'https://fixture.invalid/private-thumbnail');
const movie = CinemaTitle(
    id: 'p99:m:123',
    kind: CinemaKind.movie,
    sourceKey: 'p99',
    remoteId: '123',
    name: 'Quenovar',
    categoryKey: 'unknown',
    searchKey: 'quenovar',
    streamUrl: 'https://fixture.invalid/movie',
    posterUrl: 'https://fixture.invalid/private-thumbnail');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controls = ParentalControls.instance;
  final pip = ZunoPipService.forTesting(enabled: false);
  setUp(() async {
    AppPlatform.isZuno = false;
    controls.resetProtectionForTesting();
    SharedPreferences.setMockInitialValues(
        <String, Object>{'security.kids_mode.v1': true});
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    AppPlatform.configureZuno(isAndroidHandset: false);
    await controls.loadBeforeFirstFrame();
    CinemaRepository.instance.clear();
    ZunoPipService.debugOverride = pip;
    ForegroundPlayback.debugReset();
    NativeVideoController.audiblePlayers.debugReset();
  });
  tearDown(() {
    AppPlatform.isZuno = false;
    controls.resetProtectionForTesting();
    ZunoPipService.debugOverride = null;
    ForegroundPlayback.debugReset();
    NativeVideoController.audiblePlayers.debugReset();
  });
  tearDownAll(pip.dispose);

  Future<void> check(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ));
    expect(find.textContaining('Quenovar'), findsNothing);
    expect(find.byType(NativeVideoView), findsNothing);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('accès direct au guide ne montre aucun titre non classé',
      (tester) async {
    await check(tester, const TvChannelGuideScreen(channel: channel));
  });
  testWidgets('accès direct au lecteur live ne crée aucune vue vidéo interdite',
      (tester) async {
    await check(
        tester, const TvPlayerScreen(channels: [channel], startIndex: 0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets('accès direct à la fiche film ne montre aucun poster inconnu',
      (tester) async {
    await check(tester, const TvMovieDetailScreen(title: movie));
  });
  testWidgets('accès direct à la fiche série ne montre aucun poster inconnu',
      (tester) async {
    await check(tester, const TvSeriesScreen(title: movie));
  });
  testWidgets(
      'accès direct au lecteur film conserve la classification inconnue',
      (tester) async {
    await check(tester,
        TvVodPlayerScreen(item: VodPlayItem.movie(movie, isAdult: false)));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
