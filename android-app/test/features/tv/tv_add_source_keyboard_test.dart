import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/tv/presentation/tv_add_source_screen.dart';
import 'package:tv_king/features/tv/presentation/tv_scaled_viewport.dart';
import 'package:tv_king/features/tv/presentation/tv_shell.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const double keyboardHeight = 180;
  const Map<String, Size> screens = <String, Size>{
    'téléphone paysage': Size(800, 400),
    'TV': Size(1280, 720),
  };

  Finder field(String label) => find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );

  for (final MapEntry<String, Size> screen in screens.entries) {
    testWidgets(
        '${screen.key} : les vrais identifiants restent visibles avec le clavier',
        (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screen.value;
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final double keyboardTop = screen.value.height - keyboardHeight;

      // C'est le vrai chemin utilisé par l'activation, Mes sources et le
      // message de liste retirée : aucune feuille de connexion mobile, et
      // surtout aucun Scaffold ajouté artificiellement par le test.
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (BuildContext context, Widget? child) =>
            TvScaledViewport(child: child!),
        home: const TvShell(child: TvAddSourceScreen()),
      ));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(TvAddSourceScreen)),
      );
      final Finder server = field(l10n.tvFieldServer);
      final Finder username = field(l10n.tvFieldUser);
      final Finder password = field(l10n.tvFieldPass);
      expect(server, findsOneWidget);
      expect(username, findsOneWidget);
      expect(password, findsOneWidget);

      // Ces valeurs sont fictives ; aucune validation, aucun import et aucun
      // appel fournisseur ne sont déclenchés pendant ce test de disposition.
      await tester.enterText(server, 'http://fixture.invalid:8080');
      await tester.enterText(username, 'fixture-user');
      await tester.enterText(password, 'fixture-password');
      await tester.showKeyboard(username);
      await tester.pumpAndSettle();
      final State<StatefulWidget> initialState =
          tester.state(find.byType(TvAddSourceScreen));
      final Rect initialUsername = tester.getRect(username);
      final Rect initialPassword = tester.getRect(password);

      EditableText editable(Finder target) => tester.widget<EditableText>(
            find.descendant(of: target, matching: find.byType(EditableText)),
          );

      void expectDraftUnchanged() {
        expect(tester.widget<TextField>(server).controller!.text,
            'http://fixture.invalid:8080');
        expect(tester.widget<TextField>(username).controller!.text,
            'fixture-user');
        expect(tester.widget<TextField>(password).controller!.text,
            'fixture-password');
        expect(tester.widget<TextField>(password).obscureText, isTrue);
        expect(
            tester.state(find.byType(TvAddSourceScreen)), same(initialState));
      }

      void expectFocusedFieldAboveKeyboard(Finder target) {
        expect(editable(target).focusNode.hasFocus, isTrue);
        final Rect rect = tester.getRect(target);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(keyboardTop + 0.01),
            reason: 'le champ complet doit rester au-dessus du clavier réel');
        expectDraftUnchanged();
        expect(tester.takeException(), isNull);
      }

      // Ouverture réelle du clavier : le champ déjà focalisé doit remonter.
      // Aucun ensureVisible ni mouvement manuel du ScrollController.
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
      await tester.pumpAndSettle();
      expectFocusedFieldAboveKeyboard(username);

      // Un changement de focus avec le clavier déjà ouvert doit également
      // révéler le mot de passe puis permettre de revenir à l'identifiant.
      await tester.showKeyboard(password);
      await tester.pumpAndSettle();
      expectFocusedFieldAboveKeyboard(password);
      await tester.showKeyboard(username);
      await tester.pumpAndSettle();
      expectFocusedFieldAboveKeyboard(username);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expectDraftUnchanged();
      expect(tester.getRect(username), initialUsername,
          reason: 'clavier fermé, la disposition initiale doit être retrouvée');
      expect(tester.getRect(password), initialPassword);
      expect(editable(username).focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
