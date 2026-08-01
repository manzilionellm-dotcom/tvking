// =========================================================
//  optimized_image_client_usage_test.dart
// =========================================================
//  L'appel EXACT écrit par le client doit compiler et s'afficher tel
//  quel — c'est le contrat de son API, mot pour mot.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/widgets/optimized_image.dart';

void main() {
  testWidgets('l\'appel du client fonctionne tel quel',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OptimizedImage(
          imageUrl: 'https://exemple.com/photo.webp',
          blurHash: 'LGF5]+Yk^6#M@-5c,1J5@[or[Q6.',
          width: double.infinity,
          height: 280,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(OptimizedImage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
