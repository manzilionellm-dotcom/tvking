// Parcours réels de l’espace privé : visibilité, consentement et code parental.
// Le même fichier vérifie le build Play puis l’APK privé selon le dart-define.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/novatube_private_features.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/core/i18n/locale_repository.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/app_pin_settings.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';
import 'package:tv_king/features/tv/presentation/tv_adult_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_profile_picker.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

final _android = TargetPlatformVariant.only(TargetPlatform.android);
const bool _private = NovatubePrivateFeatures.adultCatalogs;
const _adultTile = ValueKey<String>('zuno-touch-hub-adult');
const _adultArea = ValueKey<String>('novatube-adult-area');
const _pinScreen = ValueKey<String>('zuno-touch-pin-scroll');

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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
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
  await _settle(tester);
  await tester.runAsync(GoogleFonts.pendingFonts);
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
}

void _expectNoCatalog() {
  expect(find.byType(TvLiveScreen), findsNothing);
  expect(find.byType(TvCinemaScreen), findsNothing);
  expect(find.byType(NativeVideoView), findsNothing);
}

void _expectCoreTiles() {
  for (final String name in <String>[
    'live', 'films', 'series', 'sources', 'settings',
  ]) {
    expect(find.byKey(ValueKey<String>('zuno-touch-hub-$name')), findsOneWidget);
  }
}

Future<void> _openAdultTile(WidgetTester tester) async {
  await _scrollHubTo(tester, find.byKey(_adultTile));
  await tester.tap(find.byKey(_adultTile));
  await _settle(tester);
}

Future<void> _scrollHubTo(WidgetTester tester, Finder target) async {
  // Le titre et l’aide peuvent remplir le petit écran à grande police.
  // Le ListView construit alors les tuiles seulement après défilement.
  await tester.scrollUntilVisible(target, 200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('zuno-touch-hub-root')),
        matching: find.byType(Scrollable),
      ).first);
  await _settle(tester);
}

Future<void> _enterPin(WidgetTester tester, {String pin = '4826'}) async {
  for (final String digit in pin.split('')) {
    final Finder button = find.byKey(ValueKey<String>('zuno-touch-pin-$digit'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await _settle(tester);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ProfileRepository profiles = ProfileRepository.instance;
  final AdultAccess access = AdultAccess.instance;

  setUpAll(() async {
    await _installTestFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    await PlaylistDatabase.instance.database;
  });
  setUp(() async {
    FlavorConfig.setCurrent(FlavorConfig.novatube);
    CastPlatform.configureZuno(ZunoEdition.touch);
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app.locale.v1': 'fr',
      'zuno.flag.followed': false,
    });
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('playlists');
    await db.delete('deleted_sources');
    await profiles.resetForTesting();
    await profiles.load();
    await profiles.setAskOnStartup(false);
    StartupPickerSession.shown = true;
    PlaylistRepository.mergeAllPlaylists = true;
    await PlaylistRepository.instance.reloadForActiveProfile();
    await SubscriptionState.instance.resetForTesting();
    await LocaleRepository.instance.initialize();
    await ParentalControls.instance.load();
    await access.disable();
    await access.load();
  });
  tearDown(CastPlatform.resetForTesting);
  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  for (final ({Size size, double scale}) viewport in <({Size size, double scale})>[
    (size: const Size(390, 844), scale: 1),
    (size: const Size(320, 568), scale: 1.5),
  ]) {
    testWidgets('accueil ${_private ? "privé : six" : "Play : cinq"} tuiles '
        'à ${viewport.size.width}dp, texte ${viewport.scale}', (tester) async {
      await _pump(tester, const TvHubScreen(),
          size: viewport.size, scale: viewport.scale);
      await _scrollHubTo(tester,
          find.byKey(const ValueKey<String>('zuno-touch-hub-live')));
      _expectCoreTiles();
      expect(find.byKey(_adultTile), _private ? findsOneWidget : findsNothing);
      expect(find.byKey(_adultArea), findsNothing);
      final Finder last = find.byKey(_private
          ? _adultTile
          : const ValueKey<String>('zuno-touch-hub-settings'));
      await _scrollHubTo(tester, last);
      expect(last.hitTestable(), findsOneWidget);
      _expectNoCatalog();
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }, variant: _android);
  }

  testWidgets('le profil enfants ne propose jamais la tuile +18', (tester) async {
    await tester.runAsync(() async {
      final FamilyProfile kids =
          (await profiles.addProfile(name: 'Enfants', isKids: true))!;
      await profiles.activate(kids.id, leaveAllowed: true);
      await ParentalControls.instance.load();
      await access.load();
    });
    await _pump(tester, const TvHubScreen());
    expect(profiles.activeIsKids, isTrue);
    expect(access.blockedForKids, isTrue);
    _expectCoreTiles();
    expect(find.byKey(_adultTile), findsNothing);
    expect(find.byKey(_adultArea), findsNothing);
    _expectNoCatalog();
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  testWidgets('accès direct verrouillé : aucun catalogue ni lecteur', (tester) async {
    // Même une autorisation déjà enregistrée ne vaut pas ouverture de session.
    await tester.runAsync(() async {
      await AppPinSettings.instance.setPin('4826');
      expect(await access.enableWithPin('4826'), _private);
      access.lock();
    });
    await _pump(tester, const TvAdultScreen(),
        size: const Size(320, 568), scale: 1.5);
    final AppLocalizations words = AppLocalizations.of(
      tester.element(find.byType(TvAdultScreen)),
    )!;
    expect(find.byKey(_adultArea), findsOneWidget);
    expect(access.canAccess, isFalse);
    expect(find.text(words.tvAdultLocked), findsOneWidget);
    // Les trois entrées du catalogue ne sont pas construites lorsque verrouillé.
    expect(find.text(words.tvNavLive), findsNothing);
    expect(find.text(words.tvNavFilms), findsNothing);
    expect(find.text(words.tvNavSeries), findsNothing);
    _expectNoCatalog();
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  // Le code de l’APK privé est compilé dans le second passage de validation.
  // Aucun test d’autorisation n’est annoncé comme exécuté dans le build Play.
  if (_private) {
    testWidgets('créer le PIN 0000 reste sur le formulaire sans autorisation',
        (tester) async {
      await _pump(tester, const TvHubScreen(),
          size: const Size(320, 568), scale: 1.3);
      final AppLocalizations words = AppLocalizations.of(
        tester.element(find.byType(TvHubScreen)),
      )!;
      await _openAdultTile(tester);
      await tester.ensureVisible(find.text(words.tvAdultConsent));
      await tester.tap(find.text(words.tvAdultConsent));
      await _settle(tester);
      expect(find.byKey(_pinScreen), findsOneWidget);
      expect(find.text(words.tvNewPin), findsOneWidget);
      await _enterPin(tester, pin: '0000');
      expect(find.text(words.tvConfirmCode), findsOneWidget);
      await _enterPin(tester, pin: '0000');
      expect(find.byKey(_pinScreen), findsOneWidget);
      expect(find.text(words.tvChooseSecurePin), findsOneWidget);
      expect(await tester.runAsync(AppPinSettings.instance.hasCustomPin), isFalse);
      expect(access.enabled.value, isFalse);
      expect(access.canAccess, isFalse);
      expect(find.byKey(_adultArea), findsNothing);
      _expectNoCatalog();
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }, variant: _android);

    testWidgets('consentement avant PIN : annuler ne crée aucune autorisation',
        (tester) async {
      await tester.runAsync(() => AppPinSettings.instance.setPin('4826'));
      await _pump(tester, const TvHubScreen(),
          size: const Size(320, 568), scale: 1.3);
      final AppLocalizations words = AppLocalizations.of(
        tester.element(find.byType(TvHubScreen)),
      )!;
      await _openAdultTile(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(words.tvAdultConsent), findsOneWidget);
      expect(find.byKey(_pinScreen), findsNothing);
      expect(find.byKey(_adultArea), findsNothing);
      _expectNoCatalog();
      await tester.ensureVisible(find.text(words.buttonCancel));
      await tester.tap(find.text(words.buttonCancel));
      await _settle(tester);
      expect(access.enabled.value, isFalse);
      expect(access.canAccess, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(_pinScreen), findsNothing);
      expect(find.byKey(_adultArea), findsNothing);
      _expectNoCatalog();

      await _openAdultTile(tester);
      await tester.ensureVisible(find.text(words.tvAdultConsent));
      await tester.tap(find.text(words.tvAdultConsent));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(_pinScreen), findsOneWidget);
      expect(find.text(words.tvAdultEnable), findsOneWidget);
      expect(access.enabled.value, isFalse);
      expect(find.byKey(_adultArea), findsNothing);
      _expectNoCatalog();
      final Finder cancelPin = find.byKey(
          const ValueKey<String>('zuno-touch-pin-done'));
      await tester.ensureVisible(cancelPin);
      await tester.tap(cancelPin);
      await _settle(tester);
      expect(find.byType(TvHubScreen), findsOneWidget);
      expect(find.byKey(_adultArea), findsNothing);
      expect(access.enabled.value, isFalse);
      expect(access.canAccess, isFalse);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }, variant: _android);

    testWidgets('le bon PIN ouvre la section et chaque nouvelle visite la reverrouille',
        (tester) async {
      await tester.runAsync(() => AppPinSettings.instance.setPin('4826'));
      await _pump(tester, const TvHubScreen());
      final AppLocalizations words = AppLocalizations.of(
        tester.element(find.byType(TvHubScreen)),
      )!;
      await _openAdultTile(tester);
      await tester.tap(find.text(words.tvAdultConsent));
      await _settle(tester);
      expect(find.byKey(_adultArea), findsNothing);
      await _enterPin(tester);
      expect(access.canAccess, isTrue);
      expect(find.byType(TvAdultScreen), findsOneWidget);
      expect(find.text(words.tvNavLive), findsOneWidget);
      expect(find.text(words.tvNavFilms), findsOneWidget);
      expect(find.text(words.tvNavSeries), findsOneWidget);
      _expectNoCatalog();

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(access.enabled.value, isTrue);
      expect(access.canAccess, isFalse);
      await _openAdultTile(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(_pinScreen), findsOneWidget);
      expect(find.text(words.tvAdultOpen), findsOneWidget);
      expect(find.byKey(_adultArea), findsNothing);
      _expectNoCatalog();
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }, variant: _android);
  }
}
