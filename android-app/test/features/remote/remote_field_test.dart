// =========================================================
//  remote_field_test.dart — Le clavier du téléphone dans un champ
// =========================================================
//  « Ajouter une source » est un vrai champ. Le texte du téléphone
//  doit le remplacer, pas se perdre dans une recherche invisible.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/remote/presentation/remote_actions.dart';

void main() {
  testWidgets('le texte du téléphone remplace le champ focalisé',
      (WidgetTester tester) async {
    final TextEditingController controller =
        TextEditingController(text: 'ancien');
    final FocusNode node = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TextField(controller: controller, focusNode: node)),
    ));
    node.requestFocus();
    await tester.pump();

    expect(tryApplyRemoteTextToFocusedField('http://exemple'), isTrue);
    expect(controller.text, 'http://exemple');

    node.unfocus();
    await tester.pump();
    expect(tryApplyRemoteTextToFocusedField('ailleurs'), isFalse);
    expect(controller.text, 'http://exemple');
  });
}
