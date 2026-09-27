// =========================================================
//  carousel_controller_test.dart — Logique de l'anneau (boucle)
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/carousel/domain/carousel_config.dart';
import 'package:tv_king/features/carousel/presentation/carousel_controller.dart';

void main() {
  test('boucle : après la dernière carte vient la première, et inversement',
      () {
    final ZunoCarouselController c = ZunoCarouselController(count: 12);
    c.previous();
    expect(c.index, 11);
    c.next();
    expect(c.index, 0);
    c.jumpTo(25);
    expect(c.index, 1);
  });

  test('écart le plus court sur l\'anneau (pour placer les cartes)', () {
    final ZunoCarouselController c = ZunoCarouselController(count: 12);
    expect(c.offsetOf(1), 1);
    expect(c.offsetOf(11), -1, reason: 'la 11 est juste à gauche de la 0');
    expect(c.offsetOf(6).abs(), 6);
  });

  test('notifie seulement quand la carte change', () {
    final ZunoCarouselController c = ZunoCarouselController(count: 12);
    int n = 0;
    c.addListener(() => n++);
    c.jumpTo(0);
    expect(n, 0);
    c.next();
    expect(n, 1);
  });

  test('réglages par défaut : aucune carte ne montre son dos', () {
    expect(const CarouselConfig().isGeometrySafe, isTrue);
  });
}
