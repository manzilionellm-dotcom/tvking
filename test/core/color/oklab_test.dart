// =========================================================
//  oklab_test.dart — les matrices OKLab contre des vecteurs indépendants
// =========================================================
//  Les vecteurs attendus ont été générés par une implémentation Python
//  SÉPARÉE (mêmes formules publiées par B. Ottosson / CSS Color 4) — le
//  rouge sRGB donne L = 0.627955, la valeur publiée par l'auteur. Si une
//  constante de matrice est mal recopiée dans oklab.dart, ces tests
//  échouent : c'est exactement leur raison d'être.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/color/oklab.dart';

void main() {
  test('vecteurs de référence sRGB → OKLab (générés indépendamment)', () {
    final Oklab blanc = srgbToOklab(255, 255, 255);
    expect(blanc.l, closeTo(1.0, 1e-4));
    expect(blanc.a, closeTo(0.0, 1e-4));
    expect(blanc.b, closeTo(0.0, 1e-4));

    final Oklab rouge = srgbToOklab(255, 0, 0);
    expect(rouge.l, closeTo(0.627955, 1e-5));
    expect(rouge.a, closeTo(0.224863, 1e-5));
    expect(rouge.b, closeTo(0.125846, 1e-5));

    final Oklab vert = srgbToOklab(0, 255, 0);
    expect(vert.l, closeTo(0.866440, 1e-5));
    expect(vert.a, closeTo(-0.233888, 1e-5));
    expect(vert.b, closeTo(0.179498, 1e-5));

    final Oklab bleu = srgbToOklab(0, 0, 255);
    expect(bleu.l, closeTo(0.452014, 1e-5));
    expect(bleu.a, closeTo(-0.032457, 1e-5));
    expect(bleu.b, closeTo(-0.311528, 1e-5));

    // L'accent « glacier » du thème Verre Noir, pour ancrer le réel.
    final Oklab glacier = srgbToOklab(159, 194, 232);
    expect(glacier.l, closeTo(0.801643, 1e-5));
    expect(glacier.a, closeTo(-0.021757, 1e-5));
    expect(glacier.b, closeTo(-0.062312, 1e-5));
  });

  test('aller-retour sRGB → OKLab → sRGB : identité à ±1 près par canal',
      () {
    // Grille couvrant tout le cube (pas de 51 → 6³ = 216 couleurs).
    for (int r = 0; r <= 255; r += 51) {
      for (int g = 0; g <= 255; g += 51) {
        for (int b = 0; b <= 255; b += 51) {
          final Rgb8 back = oklabToSrgb(srgbToOklab(r, g, b));
          expect((back.r - r).abs() <= 1, isTrue,
              reason: 'canal R pour ($r,$g,$b) → ${back.r}');
          expect((back.g - g).abs() <= 1, isTrue,
              reason: 'canal G pour ($r,$g,$b) → ${back.g}');
          expect((back.b - b).abs() <= 1, isTrue,
              reason: 'canal B pour ($r,$g,$b) → ${back.b}');
        }
      }
    }
  });

  test('OKLab ⇄ OKLCH : conversion polaire cohérente', () {
    const Oklch source = Oklch(0.7, 0.1, 250);
    final Oklch retour = source.toOklab().toOklch();
    expect(retour.l, closeTo(0.7, 1e-9));
    expect(retour.c, closeTo(0.1, 1e-9));
    expect(retour.h, closeTo(250, 1e-6));
  });

  test('clampChroma : sacrifie la chroma, JAMAIS la clarté ni la teinte',
      () {
    // Bleu à chroma volontairement hors gamut sRGB.
    const Oklch fou = Oklch(0.45, 0.37, 264);
    expect(isInSrgbGamut(fou.toOklab()), isFalse,
        reason: 'le vecteur de test doit être hors gamut pour avoir un sens');
    final Oklch sage = clampChroma(fou);
    expect(isInSrgbGamut(sage.toOklab()), isTrue);
    expect(sage.l, fou.l, reason: 'la hiérarchie lumineuse ne se négocie pas');
    expect(sage.h, fou.h, reason: 'l\'identité de teinte ne se négocie pas');
    expect(sage.c, lessThan(fou.c));
    expect(sage.c, greaterThan(0.05),
        reason: 'la dichotomie doit garder la chroma maximale possible, '
            'pas s\'effondrer vers le gris');

    // Une couleur déjà dans le gamut ressort inchangée.
    const Oklch douce = Oklch(0.8, 0.05, 240);
    final Oklch idem = clampChroma(douce);
    expect(idem.c, douce.c);
  });

  test('lerp OKLab entre bleu et ambre : la clarté ne plonge pas au milieu '
      '(la « zone morte » du lerp sRGB)', () {
    final Oklab bleu = const Oklch(0.70, 0.10, 250).toOklab();
    final Oklab ambre = const Oklch(0.70, 0.10, 60).toOklab();
    for (double t = 0; t <= 1.0001; t += 0.1) {
      final Oklab mid = Oklab.lerp(bleu, ambre, t);
      expect(mid.l, closeTo(0.70, 1e-9),
          reason: 'en cartésien OKLab, L est exactement linéaire — '
              'ici constant entre deux bornes de même clarté');
    }
  });
}
