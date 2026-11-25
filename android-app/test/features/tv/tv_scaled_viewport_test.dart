import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/tv_scaled_viewport.dart';

void main() {
  const double designWidth = 1280;
  const double keyboardHeight = 180;
  const Map<String, Size> screens = <String, Size>{
    'téléphone paysage 800×400': Size(800, 400),
    'TV 1280×720': Size(1280, 720),
  };

  void configureScreen(WidgetTester tester, Size screen) {
    // Un pixel logique = un pixel écran ici : les assertions de visibilité
    // portent sur le résultat APRÈS la transformation du FittedBox.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = screen;
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final MapEntry<String, Size> entry in screens.entries) {
    testWidgets('${entry.key} : tous les insets suivent le canevas',
        (WidgetTester tester) async {
      final Size screen = entry.value;
      configureScreen(tester, screen);
      final double factor = designWidth / screen.width;
      final ValueNotifier<MediaQueryData> metrics =
          ValueNotifier<MediaQueryData>(MediaQueryData(
        size: screen,
        devicePixelRatio: 2,
        padding: const EdgeInsets.fromLTRB(20, 28, 36, 32),
        viewPadding: const EdgeInsets.fromLTRB(20, 28, 36, 32),
        systemGestureInsets: const EdgeInsets.fromLTRB(16, 4, 18, 24),
        textScaler: const TextScaler.linear(1.5),
        platformBrightness: Brightness.dark,
        accessibleNavigation: true,
        navigationMode: NavigationMode.directional,
      ));
      addTearDown(metrics.dispose);
      MediaQueryData? observed;

      void expectLogicalMetrics() {
        final MediaQueryData source = metrics.value;
        final MediaQueryData actual = observed!;
        expect(actual.size, Size(designWidth, screen.height * factor));
        expect(actual.padding, source.padding * factor);
        expect(actual.viewPadding, source.viewPadding * factor);
        expect(actual.viewInsets, source.viewInsets * factor);
        expect(actual.systemGestureInsets, source.systemGestureInsets * factor);
        // Le canevas garde son texte de référence, sans perdre les autres
        // informations système (accessibilité, navigation, densité, thème).
        expect(actual.textScaler, TextScaler.noScaling);
        expect(actual.devicePixelRatio, source.devicePixelRatio);
        expect(actual.platformBrightness, source.platformBrightness);
        expect(actual.accessibleNavigation, source.accessibleNavigation);
        expect(actual.navigationMode, source.navigationMode);
      }

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<MediaQueryData>(
          valueListenable: metrics,
          builder: (BuildContext context, MediaQueryData data, Widget? child) =>
              MediaQuery(
            data: data,
            child: TvScaledViewport(
              child: Builder(builder: (BuildContext context) {
                observed = MediaQuery.of(context);
                return const SizedBox.expand();
              }),
            ),
          ),
        ),
      ));
      expectLogicalMetrics();

      // Les côtés sont volontairement différents : corriger uniquement le
      // bas du clavier ne suffirait pas pour une encoche ou la navigation.
      metrics.value = metrics.value.copyWith(
        viewInsets: const EdgeInsets.fromLTRB(8, 12, 16, keyboardHeight),
        padding: const EdgeInsets.fromLTRB(12, 16, 20, 0),
      );
      await tester.pump();
      expectLogicalMetrics();
      expect(observed!.viewInsets.bottom, keyboardHeight * factor);

      metrics.value = metrics.value.copyWith(
        viewInsets: EdgeInsets.zero,
        padding: metrics.value.viewPadding,
      );
      await tester.pump();
      expectLogicalMetrics();
      expect(observed!.viewInsets, EdgeInsets.zero);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        '${entry.key} : le champ focalisé reste au-dessus du vrai clavier',
        (WidgetTester tester) async {
      final Size screen = entry.value;
      configureScreen(tester, screen);
      final double designHeight = designWidth * screen.height / screen.width;
      final double keyboardTop = screen.height - keyboardHeight;
      final FocusNode focus = FocusNode();
      final TextEditingController text = TextEditingController();
      final ScrollController scroll = ScrollController();
      addTearDown(focus.dispose);
      addTearDown(text.dispose);
      addTearDown(scroll.dispose);
      const Key fieldKey = ValueKey<String>('identifiant');
      const Key viewportKey = ValueKey<String>('formulaire-défilant');

      await tester.pumpWidget(MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            TvScaledViewport(child: child!),
        home: Scaffold(
          resizeToAvoidBottomInset: true,
          body: SingleChildScrollView(
            key: viewportKey,
            controller: scroll,
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                // Le champ commence près du bas de l'écran, mais reste
                // entièrement visible tant que le clavier est fermé.
                SizedBox(height: designHeight - 120),
                TextField(
                  key: fieldKey,
                  focusNode: focus,
                  controller: text,
                  decoration: const InputDecoration(
                    labelText: 'Identifiant',
                    border: OutlineInputBorder(),
                  ),
                  scrollPadding: const EdgeInsets.all(32),
                ),
                const SizedBox(height: 160),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final Finder field = find.byKey(fieldKey);
      final Finder viewport = find.byKey(viewportKey);
      expect(tester.getRect(viewport).bottom, closeTo(screen.height, 0.01));
      expect(tester.getRect(field).bottom, lessThanOrEqualTo(screen.height));

      await tester.tap(field);
      await tester.enterText(field, 'fixture-user');
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(tester.getRect(field).bottom, greaterThan(keyboardTop),
          reason: 'sans adaptation, ce champ serait recouvert par le clavier');
      final State<StatefulWidget> fieldState = tester.state(field);

      // On change la vraie métrique de la vue comme Android à l'ouverture
      // du clavier. Aucun ensureVisible/scroll manuel ne masque la régression.
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
      await tester.pumpAndSettle();
      expect(tester.getRect(viewport).bottom, closeTo(keyboardTop, 0.01),
          reason: '180 pixels de clavier doivent réserver 180 pixels écran');
      final Rect visibleField = tester.getRect(field);
      expect(visibleField.top, greaterThanOrEqualTo(0));
      expect(visibleField.bottom, lessThanOrEqualTo(keyboardTop + 0.01),
          reason:
              'le champ entier doit rester visible, pas seulement sa saisie');
      expect(scroll.offset, greaterThan(0));
      expect(focus.hasFocus, isTrue);
      expect(text.text, 'fixture-user');
      expect(tester.state(field), same(fieldState));
      expect(tester.takeException(), isNull);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.getRect(viewport).bottom, closeTo(screen.height, 0.01));
      expect(tester.state(field), same(fieldState));
      expect(text.text, 'fixture-user');
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
