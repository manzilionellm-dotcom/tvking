// Tests de la vitesse de lecture VOD (n°18) : paliers proposés et
// libellés compacts affichés dans la feuille « Pistes ».

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/tv/presentation/tv_player_screen.dart';

void main() {
  group('kPlaybackSpeeds', () {
    test('contient la vitesse normale et reste ordonné', () {
      expect(kPlaybackSpeeds, contains(1.0));
      final List<double> sorted = List<double>.from(kPlaybackSpeeds)..sort();
      expect(kPlaybackSpeeds, sorted);
    });

    test('bornes raisonnables (0.5× à 2×, convention Netflix/YouTube)', () {
      expect(kPlaybackSpeeds.first, 0.5);
      expect(kPlaybackSpeeds.last, 2.0);
    });
  });

  group('speedLabel', () {
    test('entiers sans décimale', () {
      expect(speedLabel(1.0), '1×');
      expect(speedLabel(2.0), '2×');
    });

    test('décimales conservées telles quelles', () {
      expect(speedLabel(0.5), '0.5×');
      expect(speedLabel(0.75), '0.75×');
      expect(speedLabel(1.25), '1.25×');
      expect(speedLabel(1.5), '1.5×');
    });
  });
}
