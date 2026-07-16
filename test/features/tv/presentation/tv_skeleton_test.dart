// =========================================================
//  tv_skeleton_test.dart — « AUCUN spinner central » (règle de la mission)
// =========================================================
//  Les chargements Cinéma passent par des SQUELETTES (structure de page
//  fantôme) — jamais par une roue. Verrouille le composant partagé.
// =========================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/tv_components.dart';

void main() {
  testWidgets('TvSkeletonRails : hero + rangées, zéro spinner',
      (WidgetTester tester) async {
    // Surface 10-foot : le squelette est dimensionné pour un écran TV,
    // la surface de test par défaut (800×600) le ferait déborder.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TvSkeletonRails(withHero: true, rails: 2)),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'le Cinéma ne montre JAMAIS de roue centrale');
    // Structure présente : le squelette dessine des blocs (Containers).
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('TvEmptyState : icône + titre + sous-titre, zéro spinner',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TvEmptyState(
          icon: Icons.movie_outlined,
          title: 'Aucun film',
          subtitle: 'Cette source ne propose pas de VOD.',
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Aucun film'), findsOneWidget);
    expect(find.text('Cette source ne propose pas de VOD.'), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
