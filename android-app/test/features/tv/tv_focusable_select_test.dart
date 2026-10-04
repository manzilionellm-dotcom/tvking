// =========================================================
//  tv_focusable_select_test.dart — OK relâché sur un bouton qui n'a pas
//  reçu l'appui ne l'active pas
// =========================================================
//  Cas réel : un écran traite OK à l'APPUI (ouvre un panneau dont le
//  premier bouton prend le focus) ; le RELÂCHEMENT du même appui arrivait
//  sur ce bouton et l'activait aussi (double action). Un appui complet
//  (appui + relâchement) sur le bouton reste une seule activation.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/core/tv_focusable.dart';

void main() {
  testWidgets('relâchement orphelin ignoré, appui complet = une activation',
      (WidgetTester tester) async {
    int selected = 0;
    final FocusNode opener = FocusNode();
    final FocusNode button = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: <Widget>[
            // L'« écran » qui traite OK à l'appui et passe le focus au bouton.
            Focus(
              focusNode: opener,
              autofocus: true,
              onKeyEvent: (FocusNode n, KeyEvent e) {
                if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.select) {
                  button.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: const SizedBox(width: 10, height: 10),
            ),
            TvFocusable(
              focusNode: button,
              onSelect: () => selected++,
              child: const SizedBox(width: 50, height: 50),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(opener.hasFocus, isTrue);

    // Appui sur l'écran, relâchement sur le bouton (focus déplacé entre).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(button.hasFocus, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected, 0, reason: 'le relâchement n\'a pas commencé sur ce bouton');

    // Un vrai appui sur le bouton : une seule activation.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected, 1);

    opener.dispose();
    button.dispose();
  });
}
