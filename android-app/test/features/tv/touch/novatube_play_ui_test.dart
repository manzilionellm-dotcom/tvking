// Parcours NOVATUBE Play : aucune attribution distante ni offre commerciale.
// Ces tests utilisent les vrais widgets et des données fictives hors réseau.
// Ils seront exécutés par la CI uniquement après l’accord de compilation.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/core/i18n/locale_repository.dart';
import 'package:tv_king/features/box_extras/presentation/tv_extras_screen.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_common.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_detail_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_vod_player_screen.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/panel_board/presentation/tv_featured_card.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/pricing/presentation/pricing_banner.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';
import 'package:tv_king/features/subscription/presentation/subscription_card.dart';
import 'package:tv_king/features/tv/presentation/tv_activation_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_app.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_phone_source_qr.dart';
import 'package:tv_king/features/tv/presentation/tv_profile_picker.dart';
import 'package:tv_king/features/tv/presentation/tv_settings_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

final _android = TargetPlatformVariant.only(TargetPlatform.android);

Future<void> _installTestFonts() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) throw StateError('FLUTTER_ROOT nécessaire pour Ahem');
  final ByteData fallback = ByteData.sublistView(
    File('$root/packages/flutter_tools/static/Ahem.ttf').readAsBytesSync(),
  );
  final String? fontDir = Platform.environment['ZUNO_TOUCH_FONT_DIR'];
  if (fontDir != null) {
    final FontLoader icons = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytesSync())));
    await icons.load();
  }
  final Map<String, ByteData> fonts = <String, ByteData>{};
  for (final String family in <String>['Inter', 'Oswald', 'JetBrainsMono']) {
    final File? real = fontDir == null ? null : File('$fontDir/$family.ttf');
    final ByteData bytes = real?.existsSync() == true
        ? ByteData.sublistView(real!.readAsBytesSync())
        : fallback;
    for (final String weight in <String>[
      'Thin',
      'ExtraLight',
      'Light',
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ]) {
      fonts['fonts/$family-$weight.ttf'] = bytes;
    }
  }
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (ByteData? message) async {
    final String key = utf8.decode(message!.buffer.asUint8List(
      message.offsetInBytes,
      message.lengthInBytes,
    ));
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{
        for (final String asset in fonts.keys)
          asset: <Map<String, String>>[
            <String, String>{'asset': asset}
          ],
      });
    }
    if (key == 'AssetManifest.json') {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(
        <String, List<String>>{
          for (final String asset in fonts.keys) asset: <String>[asset],
        },
      ))));
    }
    if (fonts.containsKey(key)) return fonts[key];
    return messenger.delegate.send('flutter/assets', message);
  });
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(390, 844), double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: TvShell(child: child)),
  ));
  await tester.pumpAndSettle();
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _installTestFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    await PlaylistDatabase.instance.database;
  });
  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
  setUp(() async {
    FlavorConfig.setCurrent(FlavorConfig.novatube);
    CastPlatform.configureZuno(ZunoEdition.touch);
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app.locale.v1': 'fr',
      // Même des préférences publicitaires allumées ne réactivent rien.
      'zuno.flag.panel_notice': true,
      'zuno.flag.featured': true,
      'zuno.flag.promo_banner': true,
      'zuno.flag.followed': false,
    });
    await SubscriptionState.instance.resetForTesting();
    await LocaleRepository.instance.initialize();
    await ProfileRepository.instance.load();
    await ProfileRepository.instance.setAskOnStartup(false);
    StartupPickerSession.shown = true;
  });
  tearDown(CastPlatform.resetForTesting);

  testWidgets('premier lancement sans licence : accueil et sources accessibles',
      (tester) async {
    final List<Uri> requests = <Uri>[];
    await http.runWithClient(() async {
      await _pump(tester, const TvGate());
      expect(SubscriptionState.instance.status, SubscriptionStatus.unknown);
      expect(find.byType(TvHubScreen), findsOneWidget);
      expect(find.byType(TvActivationScreen), findsNothing);
      expect(find.byType(TvWhatsAppQr), findsNothing);
      expect(find.byType(TvPhoneSourceQr), findsNothing);
      final BuildContext context = tester.element(find.byType(TvHubScreen));
      final AppLocalizations words = AppLocalizations.of(context)!;
      expect(find.text(words.tvActivationCodeLabel), findsNothing);
      expect(find.text(words.tvPickOfDay), findsNothing);
      expect(find.text(words.tvTrending), findsNothing);
      expect(CastPlatform.canSend, isTrue);
      final Finder sources = find.byKey(
          const ValueKey<String>('zuno-touch-hub-sources'));
      await tester.ensureVisible(sources);
      await tester.tap(sources);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }, () => MockClient((request) async {
      requests.add(request.url);
      return http.Response('{}', 503);
    }));
    expect(requests, isEmpty, reason: 'Aucun appel de panel lors du parcours local');
  }, variant: _android);

  for (final Size size in <Size>[const Size(390, 844), const Size(320, 568)]) {
    testWidgets('Direct vide ouvre les vrais imports M3U/Xtream à ${size.width}dp',
        (tester) async {
      final List<Uri> requests = <Uri>[];
      await http.runWithClient(() async {
        await _pump(tester, const TvLiveScreen(), size: size);
        expect(find.byKey(const ValueKey<String>('novatube-manual-source-prompt')),
            findsOneWidget);
        final Finder add = find.byKey(
            const ValueKey<String>('novatube-add-manual-source'));
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(find.byType(TvAddSourceScreen), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(3));
        final AppLocalizations words = AppLocalizations.of(
            tester.element(find.byType(TvAddSourceScreen)))!;
        await tester.ensureVisible(find.text(words.playlistTypeM3u));
        await tester.tap(find.text(words.playlistTypeM3u));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        await tester.enterText(find.byType(TextField),
            'https://example.test/playlist.m3u');
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'https://example.test/playlist.m3u');
        expect(find.byType(TvWhatsAppQr), findsNothing);
        expect(find.byType(TvPhoneSourceQr), findsNothing);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      }, () => MockClient((request) async {
        requests.add(request.url);
        return http.Response('{}', 503);
      }));
      expect(requests, isEmpty);
    }, variant: _android);
  }

  testWidgets('ancienne route activation ouvre seulement la saisie manuelle',
      (tester) async {
    await _pump(tester, const TvActivationScreen());
    expect(find.byType(TvAddSourceScreen), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byType(TvWhatsAppQr), findsNothing);
    expect(find.byType(TvPhoneSourceQr), findsNothing);
    expect(find.byType(TvPricePill), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('widgets commerciaux restent invisibles même montés directement',
      (tester) async {
    await _pump(tester, Column(children: <Widget>[
      const TvWhatsAppQr(mac: 'MK:00:00:00:00:01'),
      const TvPhoneSourceQr(mac: 'MK:00:00:00:00:01'),
      const SubscriptionCard(),
      const PricingBanner(),
      TvFeaturedCard(
        channel: const Channel(id: 'fixture', name: 'Sentinelle publicité',
            category: 'Démo', streamUrl: 'https://example.test/legal.m3u8',
            isLive: true),
        note: 'Sentinelle offre',
        onWatch: () => fail('Une publicité ne doit pas être activable'),
      ),
    ]));
    expect(find.byType(Text), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('Réglages garde profils/sources et retire état MAC et installateur',
      (tester) async {
    await _pump(tester, const TvSettingsScreen());
    final AppLocalizations words = AppLocalizations.of(
        tester.element(find.byType(TvSettingsScreen)))!;
    expect(find.text(words.tvDeviceCard), findsNothing);
    expect(find.text(words.tvUpdateTitle), findsNothing);
    expect(find.text(words.tvVoiceRemoteAi), findsNothing);
    final Finder source = find.text(words.tvMySources);
    await tester.scrollUntilVisible(source, 200);
    expect(source, findsOneWidget);
    final Finder profiles = find.text(words.tvProfiles);
    await tester.scrollUntilVisible(profiles, 200);
    expect(profiles, findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('En plus ne peut pas réactiver publicité ou envoi au panel',
      (tester) async {
    await _pump(tester, const TvExtrasScreen());
    final AppLocalizations words = AppLocalizations.of(
        tester.element(find.byType(TvExtrasScreen)))!;
    expect(find.text(words.tvServiceNotices), findsNothing);
    expect(find.text(words.tvPickOfDay), findsNothing);
    expect(find.text(words.tvBanners), findsNothing);
    expect(find.text(words.tvLogToSupport), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('logo NOVATUBE entier sans teinte, cadre conservé', (tester) async {
    await _pump(tester, const TvLogo(width: 180));
    final Image logo = tester.widget<Image>(find.byType(Image));
    expect((logo.image as AssetImage).assetName,
        'assets/branding/novatube_logo.jpg');
    expect(logo.fit, BoxFit.contain);
    expect(logo.color, isNull);
    expect(logo.semanticLabel, 'NOVATUBE');
    expect(logo.height, closeTo(180 * 768 / 1246, 0.01));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('routes adultes directes : aucun lecteur ni téléchargement',
      (tester) async {
    const CinemaTitle title = CinemaTitle(
      id: 'fixture:m:blocked', kind: CinemaKind.movie, sourceKey: 'fixture',
      remoteId: 'blocked', name: 'Sentinelle de test', categoryKey: 'adult xxx',
      searchKey: 'sentinelle de test', streamUrl: 'https://example.test/blocked',
    );
    const Channel channel = Channel(
      id: 'fixture:blocked', name: 'Sentinelle de test', category: 'adult xxx',
      streamUrl: 'https://example.test/blocked', isLive: true,
    );
    final List<Uri> requests = <Uri>[];
    await http.runWithClient(() async {
      for (final Widget route in <Widget>[
        const TvPlayerScreen(channels: <Channel>[channel], startIndex: 0),
        TvVodPlayerScreen(item: VodPlayItem.movie(title)),
        const TvMovieDetailScreen(title: title),
        const TvSeriesScreen(title: title),
      ]) {
        await _pump(tester, route);
        expect(find.byKey(const ValueKey<String>('novatube-content-unavailable')),
            findsOneWidget);
        expect(find.byType(NativeVideoView), findsNothing);
        expect(find.text(title.name), findsNothing);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      }
    }, () => MockClient((request) async {
      requests.add(request.url);
      return http.Response('{}', 503);
    }));
    expect(requests, isEmpty);
  }, variant: _android);

}
