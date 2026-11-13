import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';

void main() {
  testWidgets(
      'souris air immobile : le D-pad fait défiler sans perdre le focus', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<FocusNode> rows =
        List<FocusNode>.generate(30, (int i) => FocusNode(debugLabel: 'r$i'));
    for (final FocusNode n in rows) {
      addTearDown(n.dispose);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemExtent: 60,
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int i) => TvFocusable(
              focusNode: rows[i],
              autofocus: i == 0,
              child: Text('ligne $i'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Le pointeur reste posé au milieu de l'écran (curseur caché,
    // télécommande posée) : il ne bouge plus.
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(200, 150));
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    final int start = rows.indexWhere((FocusNode n) => n.hasFocus);
    expect(start, isNot(-1));

    for (int i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(rows.indexWhere((FocusNode n) => n.hasFocus), start + 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('souris air qui bouge : le halo suit le pointeur', (
    WidgetTester tester,
  ) async {
    final FocusNode first = FocusNode();
    final FocusNode second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: <Widget>[
            TvFocusable(
              focusNode: first,
              autofocus: true,
              child: const SizedBox(height: 80, child: Text('un')),
            ),
            TvFocusable(
              focusNode: second,
              child: const SizedBox(height: 80, child: Text('deux')),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(first.hasFocus, isTrue);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: tester.getCenter(find.text('un')));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('deux')));
    await tester.pump();
    expect(second.hasFocus, isTrue);
  });
}
