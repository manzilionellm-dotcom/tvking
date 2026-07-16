// =========================================================
//  tv_focusable_test.dart — Verrouille le contrat focus D-pad du Cinéma
// =========================================================
//  TvFocusable est LA brique de toute la navigation 10-foot (affiches,
//  boutons, rangées). Ces tests verrouillent :
//    - la prise de focus (autofocus + requestFocus) notifie onFocusChange ;
//    - OK (Enter/Select) déclenche onSelect ;
//    - le zoom de focus est appliqué (AnimatedScale > 1) — la réaction
//      visuelle < 16 ms de la mission passe par cette animation GPU.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('autofocus → onFocusChange(true) dès la première frame',
      (WidgetTester tester) async {
    final List<bool> focusLog = <bool>[];
    await tester.pumpWidget(_host(
      TvFocusable(
        autofocus: true,
        onFocusChange: focusLog.add,
        onSelect: () {},
        child: const SizedBox(width: 100, height: 100),
      ),
    ));
    await tester.pump();
    expect(focusLog, contains(true));
  });

  testWidgets('OK (Select/Enter) déclenche onSelect',
      (WidgetTester tester) async {
    int selected = 0;
    await tester.pumpWidget(_host(
      TvFocusable(
        autofocus: true,
        onSelect: () => selected++,
        child: const SizedBox(width: 100, height: 100),
      ),
    ));
    await tester.pump();
    // « OK » télécommande = LogicalKeyboardKey.select ; Enter clavier aussi.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('le focus applique le zoom doux (AnimatedScale)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(
      TvFocusable(
        autofocus: true,
        scale: TvFocusScale.small,
        onSelect: () {},
        child: const SizedBox(width: 100, height: 100),
      ),
    ));
    await tester.pumpAndSettle();
    final Iterable<AnimatedScale> scales =
        tester.widgetList<AnimatedScale>(find.byType(AnimatedScale));
    expect(scales.any((AnimatedScale s) => s.scale > 1.0), isTrue,
        reason: 'l\'affiche focusée doit être agrandie (retour visuel D-pad)');
  });

  testWidgets('deux TvFocusable : les flèches déplacent le focus',
      (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(_host(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TvFocusable(
            autofocus: true,
            onFocusChange: (bool f) => log.add('a:$f'),
            onSelect: () {},
            child: const SizedBox(width: 80, height: 80),
          ),
          TvFocusable(
            onFocusChange: (bool f) => log.add('b:$f'),
            onSelect: () {},
            child: const SizedBox(width: 80, height: 80),
          ),
        ],
      ),
    ));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(log, containsAllInOrder(<String>['a:true', 'a:false', 'b:true']));
  });
}
