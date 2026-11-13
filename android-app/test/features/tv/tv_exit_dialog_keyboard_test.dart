import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/tv/presentation/tv_app.dart';
import 'package:tv_king/features/tv/presentation/tv_scaled_viewport.dart';
import 'package:tv_king/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const List<String> labels = <String>['Stay', 'Restart', 'Exit'];
  const List<String?> outcomes = <String?>[null, 'restart', 'quit'];

  for (int downs = 0; downs < labels.length; downs++) {
    testWidgets('${labels[downs]} : $downs Bas puis OK sur le vrai dialogue',
        (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Le contrôle de démarrage active aussi les sémantiques via UiAutomator.
      final semantics = tester.ensureSemantics();
      try {
        // Les fontes sont maintenant des assets réels. Attendre leur lecture
        // hors FakeAsync avant de mesurer le dialogue et ses cibles de focus.
        await tester.runAsync(() => GoogleFonts.pendingFonts(<TextStyle>[
              GoogleFonts.oswald(fontWeight: FontWeight.w600),
              GoogleFonts.inter(fontWeight: FontWeight.w400),
              GoogleFonts.inter(fontWeight: FontWeight.w700),
            ]));

        late BuildContext dialogContext;
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (BuildContext context, Widget? child) =>
              TvScaledViewport(child: child!),
          home: Builder(builder: (BuildContext context) {
            dialogContext = context;
            return const SizedBox.expand();
          }),
        ));
        await tester.pumpAndSettle();

        bool completed = false;
        String? result;
        unawaited(showExitDialog(dialogContext).then((String? action) {
          completed = true;
          result = action;
        }));
        await tester.pumpAndSettle();

        bool hasPrimaryFocus(String label) => tester
            .widgetList<Focus>(find.ancestor(
              of: find.text(label),
              matching: find.byType(Focus),
            ))
            .any((Focus widget) => widget.focusNode?.hasPrimaryFocus ?? false);

        expect(hasPrimaryFocus('Stay'), isTrue);
        for (int step = 0; step < downs; step++) {
          // Aucun requestFocus de test : seul le vrai D-pad déplace la cible.
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown,
              platform: 'android');
          await tester.pumpAndSettle();
          expect(hasPrimaryFocus(labels[step + 1]), isTrue);
          expect(completed, isFalse);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.select,
            platform: 'android');
        await tester.pumpAndSettle();

        expect(completed, isTrue);
        expect(result, outcomes[downs]);
        expect(find.text('Exit Zuno?'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    });
  }
}
