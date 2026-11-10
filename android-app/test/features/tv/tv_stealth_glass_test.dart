// Le thème peut repeindre les panneaux Direct, pas déplacer leur contenu.
// Ces tests comparent le verre au vrai Container utilisé dans le build 117
// et vérifient le repli sans flou sur une petite box / animations réduites.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/theme/app_colors.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_glass.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';

const Key _panel = Key('panel');
const Key _content = Key('content');

Future<void> _show(
  WidgetTester tester,
  Widget panel, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[
          TvAppTokens(ghost: true),
        ],
      ),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: _panel,
              width: 300,
              height: 180,
              child: panel,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => TvGlassPolicy.debugSetCapable(false));
  tearDown(() => TvGlassPolicy.debugSetCapable(false));

  for (final double inset in <double>[8, 16]) {
    testWidgets('panneau 117 à marge $inset : mêmes rectangles avec le verre',
        (WidgetTester tester) async {
      const palette = TvAppTokens(ghost: true);
      // Container ajoute implicitement l'épaisseur du bord à sa marge.
      // Retirer cet inset au changement de décoration déplacerait les lignes.
      await _show(
        tester,
        Container(
          padding: EdgeInsets.all(inset),
          decoration: BoxDecoration(
            color: palette.card.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(TvTokens.rCard),
            border: Border.all(color: palette.lineSoft),
          ),
          child: const SizedBox.expand(key: _content),
        ),
      );
      final Rect oldPanel = tester.getRect(find.byKey(_panel));
      final Rect oldContent = tester.getRect(find.byKey(_content));
      expect(oldContent.topLeft - oldPanel.topLeft,
          Offset(inset + 1, inset + 1));

      for (final bool blur in <bool>[false, true]) {
        TvGlassPolicy.debugSetCapable(blur);
        await _show(
          tester,
          TvGlass(
            padding: EdgeInsets.all(inset),
            insetBorder: true,
            ambientColor: AppColors.stealthIce,
            child: const SizedBox.expand(key: _content),
          ),
        );
        expect(tester.getRect(find.byKey(_panel)), oldPanel);
        expect(tester.getRect(find.byKey(_content)), oldContent,
            reason: 'le flou ne change ni les marges ni les dimensions');
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('le flou dépend de la capacité et des animations réduites',
      (WidgetTester tester) async {
    for (final bool capable in <bool>[false, true]) {
      TvGlassPolicy.debugSetCapable(capable);
      for (final bool reduce in <bool>[false, true]) {
        await _show(
          tester,
          const TvGlass(child: SizedBox.expand()),
          disableAnimations: reduce,
        );
        expect(find.byType(BackdropFilter),
            capable && !reduce ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('le verre garde son filet et un halo borné au panneau',
      (WidgetTester tester) async {
    await _show(
      tester,
      const TvGlass(
        insetBorder: true,
        ambientColor: AppColors.stealthSport,
        child: SizedBox.expand(key: _content),
      ),
    );
    final boxes = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(TvGlass),
          matching: find.byType(DecoratedBox),
        ))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .toList();
    final glass = boxes.singleWhere((box) => box.border != null);
    expect(glass.color, AppColors.stealthGlass);
    expect((glass.border! as Border).top.width, 1);
    final ambient = boxes.singleWhere((box) => box.gradient != null);
    final gradient = ambient.gradient! as RadialGradient;
    expect(gradient.colors.first.a, lessThanOrEqualTo(0.09));
    expect(gradient.colors.last.a, 0);
    expect(tester.getSize(find.byKey(_panel)), const Size(300, 180));
    expect(tester.takeException(), isNull);
  });

  testWidgets('les anciens usages sans inset gardent leur marge explicite',
      (WidgetTester tester) async {
    await _show(
      tester,
      const TvGlass(
        padding: EdgeInsets.all(8),
        child: SizedBox.expand(key: _content),
      ),
    );
    final offset = tester.getTopLeft(find.byKey(_content)) -
        tester.getTopLeft(find.byKey(_panel));
    expect(offset, const Offset(8, 8));
  });
}
