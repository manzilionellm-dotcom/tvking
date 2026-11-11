// Scénario portable : affiche le vrai aperçu EPG du 116 et du candidat.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/tv/presentation/tv_epg_preview_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final entry in <String, String>{
      'Inter_regular': 'Inter-Regular.ttf',
      'Inter_500': 'Inter-Medium.ttf',
      'Inter_600': 'Inter-SemiBold.ttf',
      'Inter_700': 'Inter-Bold.ttf',
    }.entries) {
      await (FontLoader(entry.key)
            ..addFont(rootBundle.load('assets/fonts/${entry.value}')))
          .load();
    }
  });
  setUp(() async {
    AppPlatform.isZuno = false;
    SharedPreferences.setMockInitialValues(
        <String, Object>{'security.kids_mode.v1': true});
    ProfileRepository.instance.resetForTesting(ProfileCatalog.fresh());
    AppPlatform.configureZuno(isAndroidHandset: false);
    await ParentalControls.instance.load();
  });
  tearDown(() {
    AppPlatform.isZuno = false;
  });

  testWidgets(
      'première image Enfants : ni titre, miniature, aperçu ou EPG non classé',
      (tester) async {
    const channel = Channel(
        id: 'l103-widget-unknown',
        name: 'Quenovar',
        category: '',
        streamUrl: 'https://fixture.invalid/unknown',
        logoUrl: 'https://fixture.invalid/private-thumbnail',
        isLive: true);
    expect(channel.genre, ChannelGenre.other);
    var loads = 0;
    var previews = 0;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: TvEpgPreviewScreen(
        channels: const <Channel>[channel],
        loadWindow: (_) async {
          loads++;
          return const TvEpgWindow();
        },
        preview: (_) {
          previews++;
          return const Text('miniature privée');
        },
      )),
    ));
    expect(find.text('Quenovar'), findsNothing);
    expect(find.text('miniature privée'), findsNothing);
    expect(loads, 0);
    expect(previews, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
