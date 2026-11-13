// =========================================================
//  tv_focus_budget_test.dart — Le focus reste lisible
// =========================================================
//  Sur une box ≤ 2 Go la lueur (deux flous) n'est pas peinte.
//  Le contour or, lui, est toujours là : c'est le signal que
//  la télécommande doit montrer. Au-dessus de 2 Go, la lueur
//  d'avant est entière. `showGlow: false` continue de gagner,
//  même sur une grande box.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/box_memory_budget.dart';
import 'package:tv_king/features/tv/core/tv_dimens.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';

void main() {
  tearDown(BoxMemoryBudget.resetForTest);

  Future<BoxDecoration> focusDecoration(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final AnimatedContainer box = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(TvFocusable),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return box.decoration! as BoxDecoration;
  }

  Future<void> pumpButton(WidgetTester tester, {bool showGlow = true}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TvFocusable(
              autofocus: true,
              showGlow: showGlow,
              child: const SizedBox(
                width: 120,
                height: 48,
                child: Text('Direct'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('≤ 2 Go : contour or, pas de flou', (WidgetTester tester) async {
    BoxMemoryBudget.debugTier = BoxRamTier.balanced;
    await pumpButton(tester);
    final BoxDecoration deco = await focusDecoration(tester);
    expect(deco.boxShadow, isNull);
    expect(deco.border, isA<Border>());
    final Border border = deco.border! as Border;
    expect(border.top.width, TvDimens.focusOutline);
    expect(find.text('Direct'), findsOneWidget);
  });

  testWidgets('> 2 Go : les deux ombres restent', (WidgetTester tester) async {
    BoxMemoryBudget.debugTier = BoxRamTier.roomy;
    await pumpButton(tester);
    final BoxDecoration deco = await focusDecoration(tester);
    expect(deco.boxShadow, hasLength(2));
    expect(deco.border, isNotNull);
  });

  testWidgets('showGlow false : pas d\'ombre, même au palier large',
      (WidgetTester tester) async {
    BoxMemoryBudget.debugTier = BoxRamTier.roomy;
    await pumpButton(tester, showGlow: false);
    final BoxDecoration deco = await focusDecoration(tester);
    expect(deco.boxShadow, isNull);
    expect(deco.border, isNotNull);
  });

  testWidgets('TvFocusBuilder dit au contenu qu\'il a le focus',
      (WidgetTester tester) async {
    BoxMemoryBudget.debugTier = BoxRamTier.tight;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusBuilder(
            autofocus: true,
            builder: (BuildContext context, bool focused) {
              return Text(focused ? 'vu' : 'cache');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('vu'), findsOneWidget);
    final BoxDecoration deco = await focusDecoration(tester);
    // Le contenu dessine son propre contour (showOutline est faux).
    // La lueur du parent ne s'ajoute pas sur une petite box.
    expect(deco.boxShadow, isNull);
    expect(deco.border, isNull);
  });
}
