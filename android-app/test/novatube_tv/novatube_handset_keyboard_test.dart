import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/features/playlists/domain/open_source_input.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_scaled_viewport.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

import 'ahem_fonts.dart';

const _landscape = Size(768, 355);

Finder _field(String id) => find.descendant(
      of: find.byKey(ValueKey<String>('tv-source-$id')),
      matching: find.byType(TextField),
    );

Future<void> _open(
  WidgetTester tester,
  OpenEntryMode mode, {
  bool handset = true,
}) async {
  final previousTv = AppPlatform.isTv;
  final previousZuno = AppPlatform.isZuno;
  AppPlatform.configureZuno(isAndroidHandset: handset);
  addTearDown(() {
    AppPlatform.isTv = previousTv;
    AppPlatform.isZuno = previousZuno;
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = handset ? _landscape : const Size(1280, 720);
  if (handset) {
    // La barre d'état et le geste de navigation restent visibles sur la photo.
    tester.view.viewPadding = const FakeViewPadding(top: 18, bottom: 10);
    tester.view.padding = const FakeViewPadding(top: 18, bottom: 10);
  }
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (_, child) => TvScaledViewport(child: child!),
    home: TvShell(child: TvAddSourceScreen(initialMode: mode)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(installAhemFonts);
  tearDownAll(removeAhemFonts);
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('téléphone : le champ M3U touché reste hors du clavier flottant',
      (tester) async {
    final orientations = <List<String>>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientations.add((call.arguments as List<Object?>).cast<String>());
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _open(tester, OpenEntryMode.m3u);
    expect(orientations.last, contains('DeviceOrientation.portraitUp'));
    final url = _field('m3u');
    final controller = tester.widget<TextField>(url).controller!;
    expect(tester.widget<TextField>(url).focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);

    // Le téléphone de la capture est en paysage. À l'échelle de la fenêtre
    // du test, son clavier flottant occupe ce rectangle sans réserver d'inset.
    const floatingKeyboard = Rect.fromLTRB(222, 82, 489, 310);
    await tester.ensureVisible(url);
    await tester.tap(url);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.view.viewInsets.bottom, 0);
    expect(tester.widget<TextField>(url).focusNode!.hasFocus, isTrue);
    final rect = tester.getRect(url);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(_landscape.height));
    expect(rect.overlaps(floatingKeyboard), isFalse,
        reason: 'la zone de frappe doit être lisible pendant la saisie');

    // Une URL privée reste identique en mémoire et est masquée à l'écran.
    const privateUrl = 'https://fixture.invalid/get.php?username=demo&password=exemple';
    tester.testTextInput.enterText(privateUrl);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(url).obscureText, isTrue);
    expect(controller.text, privateUrl);

    tester.view.physicalSize = const Size(355, 768);
    tester.view.viewInsets = const FakeViewPadding(bottom: 270);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(url).controller, same(controller));
    expect(controller.text, privateUrl);
    expect(tester.getRect(url).bottom, lessThanOrEqualTo(498.1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(orientations.last, unorderedEquals(<String>[
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]));
  }, skip: !kNovatubeTv);

  testWidgets('téléphone : Suivant garde chaque champ Xtream au-dessus du clavier',
      (tester) async {
    await _open(tester, OpenEntryMode.xtream);
    final server = _field('server');
    final user = _field('user');
    final password = _field('password');
    expect(tester.widget<TextField>(server).focusNode!.hasFocus, isFalse);

    await tester.ensureVisible(server);
    await tester.tap(server);
    tester.view.viewInsets = const FakeViewPadding(bottom: 185);
    await tester.pumpAndSettle();
    void expectVisibleFocus(Finder target) {
      final box = tester.getRect(target);
      expect(tester.widget<TextField>(target).focusNode!.hasFocus, isTrue);
      expect(box.top, greaterThanOrEqualTo(0));
      expect(box.bottom, lessThanOrEqualTo(_landscape.height - 185 + 0.1));
    }

    expectVisibleFocus(server);
    tester.testTextInput.enterText('https://fixture.invalid:8080');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expectVisibleFocus(user);
    tester.testTextInput.enterText('utilisateur');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expectVisibleFocus(password);
    tester.testTextInput.enterText('secret-factice');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(server).controller!.text, 'https://fixture.invalid:8080');
    expect(tester.widget<TextField>(user).controller!.text, 'utilisateur');
    expect(tester.widget<TextField>(password).controller!.text, 'secret-factice');
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    expect(tester.takeException(), isNull);
  }, skip: !kNovatubeTv);

  testWidgets('TV : la télécommande garde le focus initial sur l’URL M3U',
      (tester) async {
    await _open(tester, OpenEntryMode.m3u, handset: false);
    expect(tester.widget<TextField>(_field('m3u')).focusNode!.hasFocus, isTrue);
  }, skip: !kNovatubeTv);
}
