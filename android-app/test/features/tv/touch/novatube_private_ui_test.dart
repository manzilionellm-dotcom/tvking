// Parcours réels de l’espace privé : visibilité, consentement et biométrie obligatoire.
// Le même fichier vérifie le build Play puis l’APK privé selon le dart-define.
import 'dart:async';
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
import 'package:tv_king/features/security/data/adult_biometric_auth.dart';
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
const _biometricPrompt = ValueKey<String>('novatube-adult-biometric-prompt');
const _biometricCancel = ValueKey<String>('novatube-adult-biometric-cancel');

Future<void> _installTestFonts() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) throw StateError('FLUTTER_ROOT nécessaire pour Ahem');
  final ByteData fallback = ByteData.sublistView(
    File('$root/packages/flutter_tools/static/Ahem.ttf').readAsBytesSync(),
  );
  final String? fontDir = Platform.environment['ZUNO_TOUCH_FONT_DIR'];
  if (fontDir != null) {
    final FontLoader icons = FontLoader('MaterialIcons')
      ..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
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
    final String key = utf8.decode(
      message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes),
    );
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{
        for (final String asset in fonts.keys)
          asset: <Map<String, String>>[
            <String, String>{'asset': asset},
          ],
      });
    }
    if (key == 'AssetManifest.json') {
      return ByteData.sublistView(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, List<String>>{
              for (final String asset in fonts.keys) asset: <String>[asset],
            }),
          ),
        ),
      );
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

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: TvShell(child: child)),
    ),
  );
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
    'live',
    'films',
    'series',
    'sources',
    'settings',
  ]) {
    expect(
      find.byKey(ValueKey<String>('zuno-touch-hub-$name')),
      findsOneWidget,
    );
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
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey<String>('zuno-touch-hub-root')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await _settle(tester);
}

class _FakeBiometrics implements AdultBiometricAuthenticator {
  AdultBiometricResult result = AdultBiometricResult.authenticated;
  Completer<AdultBiometricResult>? pending;
  int calls = 0;
  int cancellations = 0;

  @override
  Future<AdultBiometricResult> authenticate({required String reason}) async {
    calls++;
    if (pending != null) return pending!.future;
    return result;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ProfileRepository profiles = ProfileRepository.instance;
  final AdultAccess access = AdultAccess.instance;
  late _FakeBiometrics biometrics;

  setUpAll(() async {
    await _installTestFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    await PlaylistDatabase.instance.database;
  });
  setUp(() async {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    biometrics = _FakeBiometrics();
    access.setBiometricsForTesting(biometrics);
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
  tearDown(() async {
    access.lock();
    if (biometrics.pending != null && !biometrics.pending!.isCompleted) {
      biometrics.pending!.complete(AdultBiometricResult.cancelled);
    }
    for (int i = 0; i < 20 && access.authenticating; i++) {
      await Future<void>.value();
    }
    access.setBiometricsForTesting(null);
    CastPlatform.resetForTesting();
  });
  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  for (final ({Size size, double scale}) viewport
      in <({Size size, double scale})>[
        (size: const Size(390, 844), scale: 1),
        (size: const Size(320, 568), scale: 1.5),
      ]) {
    testWidgets('accueil ${_private ? "privé : six" : "Play : cinq"} tuiles '
        'à ${viewport.size.width}dp, texte ${viewport.scale}', (tester) async {
      await _pump(
        tester,
        const TvHubScreen(),
        size: viewport.size,
        scale: viewport.scale,
      );
      await _scrollHubTo(
        tester,
        find.byKey(const ValueKey<String>('zuno-touch-hub-live')),
      );
      _expectCoreTiles();
      expect(find.byKey(_adultTile), _private ? findsOneWidget : findsNothing);
      expect(find.byKey(_adultArea), findsNothing);
      final Finder last = find.byKey(
        _private
            ? _adultTile
            : const ValueKey<String>('zuno-touch-hub-settings'),
      );
      await _scrollHubTo(tester, last);
      expect(last.hitTestable(), findsOneWidget);
      _expectNoCatalog();
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }, variant: _android);
  }

  testWidgets('le profil enfants ne propose jamais la tuile +18', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final FamilyProfile kids = (await profiles.addProfile(
        name: 'Enfants',
        isKids: true,
      ))!;
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

  testWidgets('accès direct verrouillé : aucun catalogue ni lecteur', (
    tester,
  ) async {
    // Même une autorisation déjà enregistrée ne vaut pas ouverture de session.
    await tester.runAsync(() async {
      expect(
        await access.enableWithBiometrics(consent: true, reason: 'fixture'),
        _private,
      );
      access.lock();
    });
    await _pump(
      tester,
      const TvAdultScreen(),
      size: const Size(320, 568),
      scale: 1.5,
    );
    final AppLocalizations words = AppLocalizations.of(
      tester.element(find.byType(TvAdultScreen)),
    );
    expect(find.byKey(_adultArea), findsOneWidget);
    expect(access.canAccess, isFalse);
    // À 320 px avec texte agrandi, l'aide précède l'état verrouillé dans
    // le ListView ; on parcourt réellement l'écran pour l'atteindre.
    await tester.scrollUntilVisible(
      find.text(words.tvAdultLocked),
      150,
      scrollable: find.descendant(of: find.byKey(_adultArea),
          matching: find.byType(Scrollable)).first,
    );
    await _settle(tester);
    expect(find.text(words.tvAdultLocked), findsOneWidget);
    // Les trois entrées du catalogue ne sont pas construites lorsque verrouillé.
    expect(find.text(words.tvNavLive), findsNothing);
    expect(find.text(words.tvNavFilms), findsNothing);
    expect(find.text(words.tvNavSeries), findsNothing);
    _expectNoCatalog();
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  }, variant: _android);

  // Les parcours biométriques de l'APK privé sont vérifiés avec un second
  // passage explicite. Ils ne sont pas annoncés comme exécutés en mode Play.
  if (_private) {
    testWidgets('consentement avant biométrie ; annuler ne crée aucun accès', (
      tester,
    ) async {
      biometrics.pending = Completer<AdultBiometricResult>();
      await _pump(
        tester,
        const TvHubScreen(),
        size: const Size(320, 568),
        scale: 1.3,
      );
      final AppLocalizations words = AppLocalizations.of(
        tester.element(find.byType(TvHubScreen)),
      );
      await _openAdultTile(tester);
      expect(find.text(words.tvAdultConsent), findsOneWidget);
      expect(find.byKey(_pinScreen), findsNothing);
      expect(biometrics.calls, 0);
      await tester.ensureVisible(find.text(words.buttonCancel));
      await tester.tap(find.text(words.buttonCancel));
      await _settle(tester);
      expect(access.enabled.value, isFalse);
      expect(access.canAccess, isFalse);
      expect(biometrics.calls, 0);
      _expectNoCatalog();

      await _openAdultTile(tester);
      await tester.ensureVisible(find.text(words.tvAdultConsent));
      await tester.tap(find.text(words.tvAdultConsent));
      await _settle(tester);
      expect(find.byKey(_biometricPrompt), findsOneWidget);
      expect(find.text(words.tvAdultBiometricPrompt), findsOneWidget);
      expect(find.byKey(_pinScreen), findsNothing);
      expect(biometrics.calls, 1);
      expect(
        await tester.runAsync(AppPinSettings.instance.hasCustomPin),
        isFalse,
      );
      await tester.tap(find.byKey(_biometricCancel));
      await _settle(tester);
      // Même un succès système reçu après Annuler est définitivement caduc.
      biometrics.pending!.complete(AdultBiometricResult.authenticated);
      await _settle(tester);
      expect(access.enabled.value, isFalse);
      expect(access.canAccess, isFalse);
      expect(find.byKey(_adultArea), findsNothing);
      expect(find.byKey(_pinScreen), findsNothing);
      expect(biometrics.cancellations, greaterThan(0));
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }, variant: _android);

    testWidgets(
      'biométrie sans PIN : chaque nouvelle visite redemande le système',
      (tester) async {
        await _pump(tester, const TvHubScreen());
        final AppLocalizations words = AppLocalizations.of(
          tester.element(find.byType(TvHubScreen)),
        );
        await _openAdultTile(tester);
        await tester.tap(find.text(words.tvAdultConsent));
        await _settle(tester);
        expect(access.canAccess, isTrue);
        expect(biometrics.calls, 1);
        expect(
          await tester.runAsync(AppPinSettings.instance.hasCustomPin),
          isFalse,
        );
        expect(find.byType(TvAdultScreen), findsOneWidget);
        expect(find.text(words.tvNavLive), findsOneWidget);
        expect(find.text(words.tvNavFilms), findsOneWidget);
        expect(find.text(words.tvNavSeries), findsOneWidget);
        expect(find.byKey(_pinScreen), findsNothing);
        _expectNoCatalog();

        await tester.tap(find.byType(BackButton));
        await _settle(tester);
        expect(access.enabled.value, isTrue);
        expect(access.canAccess, isFalse);
        biometrics.pending = Completer<AdultBiometricResult>();
        await _openAdultTile(tester);
        expect(find.text(words.tvAdultConsent), findsNothing);
        expect(find.byKey(_biometricPrompt), findsOneWidget);
        expect(biometrics.calls, 2);
        expect(find.byKey(_adultArea), findsNothing);
        expect(access.canAccess, isFalse);
        biometrics.pending!.complete(AdultBiometricResult.authenticated);
        await _settle(tester);
        expect(access.canAccess, isTrue);
        expect(find.byType(TvAdultScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
        expect(access.canAccess, isFalse);
      },
      variant: _android,
    );

    testWidgets(
      'retour arrière pendant le prompt invalide le résultat asynchrone',
      (tester) async {
        biometrics.pending = Completer<AdultBiometricResult>();
        await _pump(tester, const TvHubScreen());
        final AppLocalizations words = AppLocalizations.of(
          tester.element(find.byType(TvHubScreen)),
        );
        await _openAdultTile(tester);
        await tester.tap(find.text(words.tvAdultConsent));
        await _settle(tester);
        expect(find.byKey(_biometricPrompt), findsOneWidget);
        await tester.binding.handlePopRoute();
        await _settle(tester);
        biometrics.pending!.complete(AdultBiometricResult.authenticated);
        await _settle(tester);
        expect(find.byKey(_biometricPrompt), findsNothing);
        expect(find.byKey(_adultArea), findsNothing);
        expect(access.canAccess, isFalse);
        expect(access.enabled.value, isFalse);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      },
      variant: _android,
    );

    for (final AdultBiometricResult failure in <AdultBiometricResult>[
      AdultBiometricResult.unavailable,
      AdultBiometricResult.notEnrolled,
      AdultBiometricResult.rejected,
      AdultBiometricResult.cancelled,
      AdultBiometricResult.lockedOut,
      AdultBiometricResult.error,
    ]) {
      testWidgets('biométrie $failure : message clair et aucun repli PIN', (
        tester,
      ) async {
        biometrics.result = failure;
        await _pump(
          tester,
          const TvHubScreen(),
          size: const Size(320, 568),
          scale: 1.3,
        );
        final AppLocalizations words = AppLocalizations.of(
          tester.element(find.byType(TvHubScreen)),
        );
        await _openAdultTile(tester);
        await tester.ensureVisible(find.text(words.tvAdultConsent));
        await tester.tap(find.text(words.tvAdultConsent));
        await _settle(tester);
        final String message = switch (failure) {
          AdultBiometricResult.unavailable => words.tvAdultBiometricUnavailable,
          AdultBiometricResult.notEnrolled => words.tvAdultBiometricSetup,
          AdultBiometricResult.lockedOut => words.tvAdultBiometricLockedOut,
          AdultBiometricResult.cancelled ||
          AdultBiometricResult.rejected => words.tvAdultBiometricCancelled,
          _ => words.tvAdultBiometricError,
        };
        expect(find.text(message), findsOneWidget);
        expect(find.byKey(_biometricPrompt), findsOneWidget);
        expect(find.byKey(_pinScreen), findsNothing);
        expect(find.byKey(_adultArea), findsNothing);
        expect(access.enabled.value, isFalse);
        expect(access.canAccess, isFalse);
        expect(biometrics.calls, 1);
        _expectNoCatalog();
        await tester.ensureVisible(find.byKey(_biometricCancel));
        await tester.tap(find.byKey(_biometricCancel));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      }, variant: _android);
    }

    testWidgets(
      'inactive du prompt accepté ; arrière-plan reverrouille la visite',
      (tester) async {
        biometrics.pending = Completer<AdultBiometricResult>();
        await _pump(tester, const TvHubScreen());
        final AppLocalizations words = AppLocalizations.of(
          tester.element(find.byType(TvHubScreen)),
        );
        await _openAdultTile(tester);
        await tester.tap(find.text(words.tvAdultConsent));
        await _settle(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        expect(biometrics.cancellations, 0);
        biometrics.pending!.complete(AdultBiometricResult.authenticated);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _settle(tester);
        expect(access.canAccess, isTrue);
        expect(find.byType(TvAdultScreen), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(access.canAccess, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _settle(tester);
        expect(access.canAccess, isFalse);
        _expectNoCatalog();
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      },
      variant: _android,
    );
  }
}
