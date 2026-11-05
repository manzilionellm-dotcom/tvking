import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/tv/presentation/tv_source_entry_form.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

/// Touches envoyées comme un boîtier infrarouge : flèche = code Android
/// DPAD, Entrée = ENTER, pavé = NUMPAD_ENTER.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Finder field(String name) => find.descendant(
        of: find.byKey(ValueKey<String>('tv-source-$name')),
        matching: find.byType(TextField),
      );

  bool hasFocus(WidgetTester tester, Finder target) =>
      tester.widget<TextField>(target).focusNode!.hasFocus;

  bool buttonFocused(WidgetTester tester) {
    final Element element = tester.element(
      find.byKey(const ValueKey<String>('tv-source-submit')),
    );
    return Focus.of(element).hasFocus;
  }

  Future<void> show(WidgetTester tester) async {
    RemoteSourceRepository.resetImportQueueForTesting();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: TvSourceEntryForm(autofocus: true)),
      ),
    );
    await tester.pump();
  }

  Future<void> down(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }

  testWidgets('Bas et Entrée passent Serveur, nom, mot de passe, Connexion', (
    WidgetTester tester,
  ) async {
    await show(tester);
    expect(hasFocus(tester, field('server')), isTrue);

    await down(tester);
    expect(hasFocus(tester, field('user')), isTrue, reason: 'Bas quitte le serveur');

    await down(tester);
    expect(
      hasFocus(tester, field('password')),
      isTrue,
      reason: 'Bas quitte le nom d\'utilisateur',
    );

    await down(tester);
    expect(buttonFocused(tester), isTrue, reason: 'Bas atteint Connexion');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(hasFocus(tester, field('password')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(hasFocus(tester, field('user')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(hasFocus(tester, field('password')), isTrue, reason: 'Entrée = suivant');

    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();
    expect(buttonFocused(tester), isTrue, reason: 'Pavé Entrée = suivant');
  });
}
