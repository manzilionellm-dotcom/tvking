// Régression du téléphone : le véritable TvApp ne doit plus réduire un
// canevas TV de 1280 dp dans une fenêtre de 390 dp. On mesure les boutons
// APRÈS transformation, puis on les utilise au toucher, sans appeler leurs
// callbacks directement. Les données et la MAC ci-dessous sont fictives.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/app/zuno_edition.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/core/i18n/locale_repository.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/cinema/data/catalog_disk.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/subscription/data/subscription_state.dart';
import 'package:tv_king/features/tv/presentation/tv_activation_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_app.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';
import 'package:tv_king/features/tv/presentation/tv_cinema_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_live_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_parental_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_profile_picker.dart';
import 'package:tv_king/features/tv/presentation/tv_search_screen.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

const _mac = 'MK:12:34:AB:CD:56';
const _displayMac = '12:34:AB:CD:56';
const _paintKey = ValueKey<String>('touch-test-frame');
final _android = TargetPlatformVariant.only(TargetPlatform.android);
const _scenarios = <({String name, Size size, double scale})>[
  (name: 'portrait', size: Size(390, 844), scale: 1),
  (name: 'petit', size: Size(320, 568), scale: 1),
  (name: 'paysage', size: Size(844, 390), scale: 1),
  (name: 'tablette', size: Size(800, 1280), scale: 1),
  (name: 'texte-2x', size: Size(390, 844), scale: 2),
];

Finder _key(String name) => find.byKey(ValueKey<String>(name));

Future<void> _revealIn(
    WidgetTester tester, Finder target, String pageKey) async {
  // ListView construit ses enfants à la demande : avec Ahem et texte 2x,
  // une action peut être au-delà du cache tant qu'on n'a pas défilé.
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find
            .descendant(of: _key(pageKey), matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

// WidgetTester.getSize mesure la boîte logique. Cette mesure inclut au
// contraire tous les FittedBox/Transform ancêtres : c'est la taille que le
// doigt reçoit réellement sur l'écran, celle qui régressait dans l'APK.
Rect _screenRect(WidgetTester tester, Finder finder) {
  final RenderBox box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

void _expectInside(Rect rect, Size screen, {double keyboard = 0}) {
  expect(rect.left, greaterThanOrEqualTo(-0.5));
  expect(rect.right, lessThanOrEqualTo(screen.width + 0.5));
  expect(rect.top, greaterThanOrEqualTo(-0.5));
  expect(rect.bottom, lessThanOrEqualTo(screen.height - keyboard + 0.5));
}

// CI reste hors réseau avec la police Ahem du SDK, comme le test MAC RTL.
// Pour la vérification visuelle, ZUNO_TOUCH_FONT_DIR fournit les trois
// polices libres réelles : Inter.ttf, Oswald.ttf et JetBrainsMono.ttf.
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

Future<void> _capture(WidgetTester tester, String name) async {
  final String? directory = Platform.environment['ZUNO_TOUCH_CAPTURE_DIR'];
  if (directory == null) return;
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_paintKey));
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    try {
      final ByteData? bytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Capture PNG vide');
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
  ZunoEdition edition = ZunoEdition.touch,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  CastPlatform.configureZuno(edition);
  await tester
      .pumpWidget(const RepaintBoundary(key: _paintKey, child: TvApp()));
  await tester.pumpAndSettle();
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
  // Le QR « Mon espace » peut terminer son repli réseau (HTTP400 imposé par
  // le binding de test). Aucun serveur réel n'est contacté.
  await tester.pump(const Duration(seconds: 9));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _installTestFonts();
    // Vrai SQLite en mémoire pour les favoris/historiques consultés par
    // l’accueil. Aucun plugin Android ni dossier utilisateur n’est requis.
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
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': _mac,
      'app.locale.v1': 'fr',
      'zuno.flag.panel_notice': false,
      'zuno.flag.featured': false,
      'zuno.flag.promo_banner': false,
      'zuno.flag.followed': false,
    });
    await SubscriptionState.instance.resetForTesting();
    await LocaleRepository.instance.initialize();
    RepairFlags.debugReset();
    AppPlatform.isTv = true; // L'identité panel ne décide pas du rendu.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.manzilionellm.tvking/device'),
      (MethodCall call) async => call.method == 'getAndroidId'
          ? 'test-device-only'
          : <String, String>{},
    );
  });
  tearDown(() {
    CastPlatform.resetForTesting();
    AppPlatform.isTv = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.manzilionellm.tvking/device'), null);
  });

  for (final scenario in _scenarios) {
    testWidgets(
        'activation ${scenario.name} : vrais boutons lisibles et tactiles',
        (WidgetTester tester) async {
      await _pumpApp(tester, scenario.size, textScale: scenario.scale);
      expect(find.byType(TvActivationScreen), findsOneWidget);
      final BuildContext context =
          tester.element(find.byType(TvActivationScreen));
      expect(MediaQuery.sizeOf(context).width, scenario.size.width);
      expect(MediaQuery.textScalerOf(context).scale(16), 16 * scenario.scale);
      expect(find.text(_displayMac), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'activation-${scenario.name}');

      for (final String action in <String>[
        'zuno-touch-activation-check',
        'zuno-touch-activation-copy',
        'zuno-touch-source-xtream',
        'zuno-touch-source-m3u',
        'zuno-touch-source-player',
      ]) {
        final Finder button = _key(action);
        expect(button, findsOneWidget);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final Rect rect = _screenRect(tester, button);
        expect(rect.height, greaterThanOrEqualTo(48));
        _expectInside(rect, scenario.size);
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(CastPlatform.canSend, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, variant: _android);
  }

  testWidgets('copier le code copie la MAC complète, sans petit bouton TV',
      (WidgetTester tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _pumpApp(tester, const Size(390, 844));
    final Finder copy = _key('zuno-touch-activation-copy');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    expect(copied, _displayMac);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: _android);

  for (final String mode in <String>['xtream', 'm3u']) {
    testWidgets(
        'toucher $mode ouvre la vraie saisie, clavier et validation accessibles',
        (WidgetTester tester) async {
      const Size size = Size(390, 844);
      await _pumpApp(tester, size);
      final Finder source = _key('zuno-touch-source-$mode');
      await tester.ensureVisible(source);
      await tester.tap(source);
      await tester.pumpAndSettle();
      expect(find.byType(TvAddSourceScreen), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(mode == 'xtream' ? 3 : 1));
      final BuildContext context =
          tester.element(find.byType(TvAddSourceScreen));
      final AppLocalizations words = AppLocalizations.of(context)!;
      expect(MediaQuery.sizeOf(context).width, size.width);
      const double keyboard = 300;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(find.byType(TextField).last);
      await tester.pumpAndSettle();
      final Finder validate = find.byType(TvCtaButton);
      await tester.ensureVisible(validate);
      await tester.pumpAndSettle();
      _expectInside(_screenRect(tester, validate), size, keyboard: keyboard);
      expect(_screenRect(tester, validate).height, greaterThanOrEqualTo(44));
      expect(validate.hitTestable(), findsOneWidget);
      await tester.tap(validate);
      await tester.pumpAndSettle();
      if (mode == 'xtream')
        expect(find.text(words.tvSourceNeedXtream), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await _capture(tester, 'source-$mode');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, variant: _android);
  }

  testWidgets(
      'la télévision conserve le canevas 1280 et ses contrôles d’origine',
      (WidgetTester tester) async {
    await _pumpApp(tester, const Size(1920, 1080),
        textScale: 2, edition: ZunoEdition.television);
    final BuildContext context =
        tester.element(find.byType(TvActivationScreen));
    expect(MediaQuery.sizeOf(context), const Size(1280, 720));
    expect(MediaQuery.textScalerOf(context).scale(16), 16);
    expect(find.byType(TvCtaButton), findsOneWidget);
    expect(_key('zuno-touch-activation-scroll'), findsNothing);
    expect(CastPlatform.canSend, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: _android);

  for (final scenario in _scenarios) {
    testWidgets(
        'accueil ${scenario.name} : les cinq destinations restent accessibles',
        (WidgetTester tester) async {
      // Essai local fictif : passe par TvGate sans modifier les règles d’accès.
      await SubscriptionState.instance.initialize();
      await _pumpApp(tester, scenario.size, textScale: scenario.scale);
      expect(find.byType(TvHubScreen), findsOneWidget);
      expect(_key('zuno-touch-hub-root'), findsOneWidget);
      await _capture(tester, 'accueil-${scenario.name}');
      for (final String destination in <String>[
        'live',
        'films',
        'series',
        'sources',
        'settings',
      ]) {
        final Finder tile = _key('zuno-touch-hub-$destination');
        expect(tile, findsOneWidget);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        _expectInside(_screenRect(tester, tile), scenario.size);
        expect(_screenRect(tester, tile).height, greaterThanOrEqualTo(48));
        expect(tile.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, variant: _android);
  }

  testWidgets('recherche tactile : clavier et effacement à 320 dp, texte 2x',
      (WidgetTester tester) async {
    const Size size = Size(320, 568);
    await SubscriptionState.instance.initialize();
    await _pumpApp(tester, size, textScale: 2);
    final AppLocalizations words =
        AppLocalizations.of(tester.element(find.byType(TvHubScreen)))!;
    final Finder search = find.text(words.tvNavSearch);
    await _revealIn(tester, search, 'zuno-touch-hub-root');
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(find.byType(TvSearchScreen), findsOneWidget);
    final Finder input = _key('zuno-touch-search-input');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.enterText(input, 'Camille');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    _expectInside(_screenRect(tester, input), size, keyboard: 260);
    expect(tester.widget<TextField>(input).controller!.text, 'Camille');
    final Finder clear = _key('zuno-touch-search-clear');
    await _revealIn(tester, clear, 'zuno-touch-search-scroll');
    await tester.pumpAndSettle();
    _expectInside(_screenRect(tester, clear), size, keyboard: 260);
    expect(_screenRect(tester, clear).height, greaterThanOrEqualTo(48));
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await _capture(tester, 'recherche-petit-texte-2x');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: _android);

  testWidgets('Sources, Réglages et Films depuis le hub à 320 dp, texte 2x',
      (WidgetTester tester) async {
    const Size size = Size(320, 568);
    await SubscriptionState.instance.initialize();
    await _pumpApp(tester, size, textScale: 2);
    for (final destination in <({String hub, String page})>[
      (hub: 'sources', page: 'sources'),
      (hub: 'settings', page: 'settings'),
      (hub: 'films', page: 'cinema'),
    ]) {
      final Finder tile = _key('zuno-touch-hub-${destination.hub}');
      await _revealIn(tester, tile, 'zuno-touch-hub-root');
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final Finder page = _key('zuno-touch-${destination.page}');
      expect(page, findsOneWidget);
      expect(MediaQuery.sizeOf(tester.element(page)).width, size.width);
      expect(tester.takeException(), isNull);
      await _capture(tester, '${destination.page}-petit-texte-2x');
      final Finder back = find.byType(BackButton).first;
      await tester.ensureVisible(back);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byType(TvHubScreen), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: _android);

  testWidgets('PIN tactile : saisie et double confirmation à 320 dp, texte 2x',
      (WidgetTester tester) async {
    const Size size = Size(320, 568);
    await SubscriptionState.instance.initialize();
    await _pumpApp(tester, size, textScale: 2);
    final BuildContext context = tester.element(find.byType(TvHubScreen));
    final AppLocalizations words = AppLocalizations.of(context)!;
    final Future<String?> result = pickNewParentalPin(context);
    await tester.pumpAndSettle();
    expect(_key('zuno-touch-pin-scroll'), findsOneWidget);
    Future<void> enter(String digits) async {
      for (final String digit in digits.split('')) {
        final Finder button = _key('zuno-touch-pin-$digit');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        _expectInside(_screenRect(tester, button), size);
        expect(_screenRect(tester, button).height, greaterThanOrEqualTo(48));
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
    }

    await enter('1234');
    await enter('1235');
    expect(find.text(words.tvPinMismatch), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'pin-petit-texte-2x');
    await enter('1234');
    await enter('1234');
    expect(await result, '1234');
    expect(find.byType(TvHubScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: _android);

  testWidgets(
    'Direct sans source : la capture reste lisible sur cinq formats et rotations',
    (WidgetTester tester) async {
      // On suit le vrai parcours accueil → Direct. La licence locale d’essai
      // permet d’ouvrir l’accueil ; le serveur simulé n’assigne AUCUNE liste.
      // Cette réponse déclenche l’état exact « Code pas encore actif » de
      // la capture utilisateur, indépendamment de l’écran d’activation.
      int sourceReads = 0;
      await http.runWithClient(() async {
        await SubscriptionState.instance.initialize();
        await _pumpApp(tester, _scenarios.first.size);
        final Finder live = _key('zuno-touch-hub-live');
        await tester.ensureVisible(live);
        await tester.tap(live);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 9));
        await tester.pumpAndSettle();
        expect(find.byType(TvLiveScreen), findsOneWidget);
        for (final scenario in _scenarios) {
          tester.view.physicalSize = scenario.size;
          tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
          await tester.pumpAndSettle();
          final BuildContext context =
              tester.element(find.byType(TvLiveScreen));
          final AppLocalizations words = AppLocalizations.of(context)!;
          expect(_key('zuno-touch-live'), findsOneWidget);
          expect(find.text(words.tvCodeInactive), findsOneWidget);
          expect(find.text(words.tvCodeInactiveHelp), findsOneWidget);
          expect(find.text(_displayMac), findsOneWidget);
          expect(RemoteSourceRepository.lastReport?.result, 'noSource');
          expect(MediaQuery.sizeOf(context).width, scenario.size.width);
          expect(
              MediaQuery.textScalerOf(context).scale(16), 16 * scenario.scale);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text(words.tvCodeInactive));
          await tester.pumpAndSettle();
          await _capture(tester, 'direct-sans-source-${scenario.name}');

          Finder action(String label) => find.ancestor(
                of: find.text(label),
                matching:
                    find.byWidgetPredicate((Widget w) => w is FilledButton),
              );
          final Finder retry = action(words.tvRetry);
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          _expectInside(_screenRect(tester, retry), scenario.size);
          expect(_screenRect(tester, retry).height, greaterThanOrEqualTo(48));
          final int beforeRetry = sourceReads;
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(sourceReads, greaterThan(beforeRetry));

          final Finder add = action(words.tvAddOwnList);
          await tester.ensureVisible(add);
          await tester.pumpAndSettle();
          _expectInside(_screenRect(tester, add), scenario.size);
          expect(_screenRect(tester, add).height, greaterThanOrEqualTo(48));
          await tester.tap(add);
          await tester.pumpAndSettle();
          expect(find.byType(TvAddSourceScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
          Navigator.of(tester.element(find.byType(TvAddSourceScreen))).pop();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
          () => MockClient((http.Request request) async {
                if (request.url.path.startsWith('/api/device-source/')) {
                  sourceReads++;
                  return http.Response('{"source":null}', 200);
                }
                // Aucune requête réelle, aucun code ni appareil réel enregistré.
                return http.Response('{}', 503);
              }));
    },
    variant: _android,
  );

  testWidgets(
      'profils tactiles : choix et prénom au clavier à 320 dp, texte 2x',
      (WidgetTester tester) async {
    const Size size = Size(320, 568);
    final ProfileRepository profiles = ProfileRepository.instance;
    await profiles.load();
    await profiles.setAskOnStartup(false);
    final FamilyProfile? camille =
        await profiles.addProfile(name: 'Camille', isKids: false);
    final FamilyProfile? alexandre =
        await profiles.addProfile(name: 'Alexandre', isKids: false);
    expect(camille, isNotNull);
    expect(alexandre, isNotNull);
    await SubscriptionState.instance.initialize();
    await _pumpApp(tester, size, textScale: 2);
    final Finder chip = find.text('Profil 1');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(_key('zuno-touch-profile-picker-scroll'), findsOneWidget);
    await _capture(tester, 'profils-petit-texte-2x');
    for (final FamilyProfile profile in profiles.catalog.profiles) {
      final Finder card = _key('zuno-touch-profile-${profile.id}');
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      _expectInside(_screenRect(tester, card), size);
      expect(_screenRect(tester, card).height, greaterThanOrEqualTo(48));
    }
    final Finder chosen = _key('zuno-touch-profile-${camille!.id}');
    await tester.ensureVisible(chosen);
    await tester.tap(chosen);
    await tester.pumpAndSettle();
    expect(profiles.active.id, camille.id);
    final BuildContext context = tester.element(find.byType(TvHubScreen));
    final Future<String?> name = askProfileName(context, title: 'Prénom');
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    final Finder input = _key('zuno-touch-profile-name');
    await tester.ensureVisible(input);
    await tester.enterText(input, 'Nouveau prénom');
    await tester.pumpAndSettle();
    final Finder save = _key('zuno-touch-profile-save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    _expectInside(_screenRect(tester, save), size, keyboard: 260);
    expect(_screenRect(tester, save).height, greaterThanOrEqualTo(48));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(await name, 'Nouveau prénom');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await profiles.activate(ProfileIds.origin, leaveAllowed: true);
    await profiles.remove(camille.id, leaveAllowed: true);
    await profiles.remove(alexandre!.id, leaveAllowed: true);
  }, variant: _android);

  testWidgets(
      'recherche Cinéma en paysage : le clavier laisse le champ accessible',
      (WidgetTester tester) async {
    const Size size = Size(844, 390);
    const String server = 'https://catalogue.invalid';
    final CinemaRepository cinema = CinemaRepository.instance;
    final Database database = await PlaylistDatabase.instance.database;
    final Directory directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('zuno-touch-catalogue-')))!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => directory.path,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null));
    int? playlistId;
    try {
      await tester.runAsync(() async {
        // Un seul film fictif dans le vrai cache : aucun serveur, aucune
        // lecture vidéo et aucun compte utilisateur ne sont nécessaires.
        playlistId = await database.insert('playlists', <String, Object?>{
          'name': 'Catalogue de test',
          'type': 'xtream',
          'xtream_server': server,
          'xtream_username': 'fixture',
          'xtream_password': 'fixture-only',
          'created_at': 1,
        });
        final String signature =
            catalogFolderName('$playlistId|$server|fixture');
        final String sourceKey = 'p$playlistId';
        final CatalogDisk disk =
            CatalogDisk(Directory('${directory.path}/zuno_catalog'));
        await disk
            .beginStaging(signature, CinemaKind.movie, <CatalogCategoryRecord>[
          CatalogCategoryRecord(
              key: 'test',
              name: 'Films de test',
              fileId: '',
              parts: <CatalogPartRecord>[CatalogPartRecord(sourceKey, '1')]),
        ]);
        expect(
            await disk.addChunk(
                signature, CinemaKind.movie, 'test', <CatalogTitleRecord>[
              CatalogTitleRecord(
                  id: '$sourceKey:m:1',
                  kind: CinemaKind.movie,
                  sourceKey: sourceKey,
                  remoteId: '1',
                  name: 'Film de démonstration',
                  categoryKey: 'test',
                  searchKey: 'film de demonstration',
                  addedAt: 1,
                  containerExt: 'mp4'),
            ]),
            isTrue);
        expect(
            await disk.commit(
                signature: signature,
                kind: CinemaKind.movie,
                updatedAt: DateTime.now()),
            isTrue);
        final List<CinemaCategory> categories =
            await cinema.categories(CinemaKind.movie);
        expect(categories, hasLength(1));
        await cinema.loadTitles(CinemaKind.movie, categories.single);
        await cinema.ensureIndex(CinemaKind.movie);
      });
      await SubscriptionState.instance.initialize();
      await _pumpApp(tester, size);
      final Finder films = _key('zuno-touch-hub-films');
      await _revealIn(tester, films, 'zuno-touch-hub-root');
      await tester.tap(films);
      await tester.pumpAndSettle();
      await tester.runAsync(() => cinema.categories(CinemaKind.movie));
      await tester.pumpAndSettle();
      expect(find.byType(TvCinemaScreen), findsOneWidget);
      final AppLocalizations words =
          AppLocalizations.of(tester.element(find.byType(TvCinemaScreen)))!;
      // La catégorie ouvre la feuille réelle ; choisir Recherche conserve
      // le même index et le même moteur de recherche que sur télévision.
      final Finder category = find.text('Films de test').first;
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text(words.tvCinemaSearch));
      await tester.pumpAndSettle();
      final Finder input = _key('zuno-touch-cinema-search');
      expect(input, findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await _revealIn(tester, input, 'zuno-touch-cinema');
      await tester.tap(input);
      await tester.enterText(input, 'Film');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final Finder editing =
          find.descendant(of: input, matching: find.byType(EditableText));
      await tester.ensureVisible(editing);
      await tester.pumpAndSettle();
      // Avec90dp restants au-dessus du clavier, le caret et la ligne saisie
      // doivent rester visibles, même si la bordure/étiquette défile.
      _expectInside(_screenRect(tester, editing), size, keyboard: 300);
      expect(input.hitTestable(), findsOneWidget);
      expect(
          tester
              .widget<EditableText>(find.descendant(
                  of: input, matching: find.byType(EditableText)))
              .controller
              .text,
          'Film');
      expect(tester.takeException(), isNull);
      await _capture(tester, 'cinema-paysage-clavier');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        if (playlistId != null) {
          await database.delete('playlists',
              where: 'id = ?', whereArgs: <Object>[playlistId!]);
        }
        cinema.clear();
        await directory.delete(recursive: true);
      });
    }
  }, variant: _android);
}
