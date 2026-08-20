// =========================================================
//  apca_test.dart — le contraste APCA contre des vecteurs indépendants
// =========================================================
//  Vecteurs générés par une implémentation Python séparée des mêmes
//  constantes APCA-W3 0.0.98G-4g. L'ancre canonique de l'algorithme :
//  blanc sur noir = Lc −107.88 (négatif = polarité inverse, texte clair
//  sur fond sombre — notre monde TV).
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/color/apca.dart';
import 'package:tv_king/core/color/oklab.dart';

void main() {
  double lc(int tr, int tg, int tb, int br, int bg, int bb) =>
      apcaContrastRgb(
        text: Rgb8(tr, tg, tb),
        background: Rgb8(br, bg, bb),
      );

  test('vecteurs de référence APCA (générés indépendamment)', () {
    // L'ancre canonique de l'algorithme, dans les deux polarités.
    expect(lc(255, 255, 255, 0, 0, 0), closeTo(-107.8847, 0.01));
    expect(lc(0, 0, 0, 255, 255, 255), closeTo(106.0407, 0.01));
    // Nos paires réelles (thème Verre Noir).
    expect(lc(243, 246, 251, 10, 13, 19), closeTo(-101.5036, 0.01),
        reason: 'texte du héros sur encre froide : très confortable');
    expect(lc(151, 160, 174, 11, 14, 20), closeTo(-50.1330, 0.01),
        reason: 'texte secondaire : lisible mais jamais pour de l\'essentiel');
    // Une paire médiocre : APCA la note près de zéro là où le ratio
    // WCAG 2 lui aurait donné un faux air de légitimité.
    expect(lc(136, 136, 136, 119, 119, 119), closeTo(-7.3202, 0.01));
  });

  test('paire identique → contraste nul', () {
    expect(lc(120, 130, 140, 120, 130, 140), 0);
  });

  test('resolveTextL atteint sa cible sur fond sombre, au L le plus doux',
      () {
    const Rgb8 fond = Rgb8(11, 14, 20); // panneau Verre Noir
    final double? l90 = resolveTextL(
      background: fond,
      chroma: 0.005,
      hueDeg: 250,
      targetLc: ApcaTargets.body,
    );
    expect(l90, isNotNull);
    // La couleur résolue atteint bien |Lc| ≥ 90…
    final Rgb8 texte =
        oklabToSrgb(clampChroma(Oklch(l90!, 0.005, 250)).toOklab());
    expect(apcaContrastRgb(text: texte, background: fond).abs(),
        greaterThanOrEqualTo(ApcaTargets.body - 0.05));
    // …sans sur-blanchir : un cran (−0.02 de L) en dessous ne suffit plus.
    final Rgb8 unPeuMoins = oklabToSrgb(
        clampChroma(Oklch(l90 - 0.02, 0.005, 250)).toOklab());
    expect(apcaContrastRgb(text: unPeuMoins, background: fond).abs(),
        lessThan(ApcaTargets.body));
  });

  test('resolveTextL : une cible plus stricte exige un L plus clair', () {
    const Rgb8 fond = Rgb8(21, 26, 36); // surface « verre au repos »
    final double? doux = resolveTextL(
        background: fond, chroma: 0.01, hueDeg: 250, targetLc: 60);
    final double? strict = resolveTextL(
        background: fond, chroma: 0.01, hueDeg: 250, targetLc: 90);
    expect(doux, isNotNull);
    expect(strict, isNotNull);
    expect(strict!, greaterThan(doux!));
  });

  test('resolveTextL rend null quand le fond est trop clair pour du texte '
      'clair — le texte ne triche jamais', () {
    // Fond glacier clair : même du blanc n'atteint pas Lc 90 dessus.
    const Rgb8 fondClair = Rgb8(159, 194, 232);
    expect(
      resolveTextL(
          background: fondClair, chroma: 0.005, hueDeg: 250, targetLc: 90),
      isNull,
    );
  });
}
