// =========================================================
//  zuno_ring_carousel_test.dart — Rendu de l'anneau 3D
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tv_king/features/carousel/domain/carousel_item.dart';
import 'package:tv_king/features/carousel/presentation/carousel_poster_card.dart';
import 'package:tv_king/features/carousel/presentation/zuno_ring_carousel.dart';

List<CarouselItem> _items(int n) => <CarouselItem>[
      for (int i = 0; i < n; i++)
        CarouselItem(
          id: 'id$i',
          title: 'Titre $i',
          category: CarouselCategory.values[i % 6],
        ),
    ];

Future<void> _pump(WidgetTester tester, List<CarouselItem> items) async {
  // Pas de téléchargement de police pendant les tests (police par défaut).
  GoogleFonts.config.allowRuntimeFetching = false;
  await tester.pumpWidget(
    MaterialApp(home: Center(child: ZunoRingCarousel(items: items))),
  );
}

void main() {
  testWidgets('12 affiches : seules les visibles sont construites (3 + 1 + 3)',
      (WidgetTester tester) async {
    await _pump(tester, _items(12));
    // Règle : |écart| < visibleSide + 1. À l'arrêt les écarts sont entiers,
    // donc −3…+3 → 7 cartes ; les 5 autres ne coûtent rien.
    expect(find.byType(CarouselPosterCard), findsNWidgets(7));
  });

  testWidgets('liste courte : chaque affiche apparaît une seule fois',
      (WidgetTester tester) async {
    await _pump(tester, _items(3));
    expect(find.byType(CarouselPosterCard), findsNWidgets(3));
  });

  testWidgets('liste vide : rien n\'est dessiné', (WidgetTester tester) async {
    await _pump(tester, const <CarouselItem>[]);
    expect(find.byType(CarouselPosterCard), findsNothing);
  });
}
