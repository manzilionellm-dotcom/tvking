// =========================================================
//  zuno_ring_carousel_test.dart — Rendu de l'anneau 3D
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
      'télécommande : ▶ / ◀ tournent l\'anneau (boucle), OK sélectionne',
      (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final List<int> focused = <int>[];
    final List<int> chosen = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: ZunoRingCarousel.builder(
          itemCount: 5,
          autofocus: true,
          semanticLabel: (int i) => 'carte $i',
          cardBuilder: (BuildContext c, int i, bool sel) =>
              const SizedBox.expand(),
          onFocusIndex: focused.add,
          onSelectedIndex: chosen.add,
        ),
      ),
    ));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(focused.last, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(focused.last, 4, reason: 'avant la 1re carte vient la dernière');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(chosen, <int>[4]);
    // Laisse expirer le compte à rebours de respiration puis démonte.
    await tester.pumpWidget(const SizedBox());
  });
}
