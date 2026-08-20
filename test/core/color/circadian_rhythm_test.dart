// =========================================================
//  circadian_rhythm_test.dart — la journée entière, minute par minute
// =========================================================
//  Deux promesses du blueprint Caméléon, verrouillées ici :
//    1. CONTINUITÉ : la température glisse — aucun saut perceptible d'une
//       minute à l'autre, y compris au passage des ancres et à minuit.
//    2. AUCUN VERT : entre le bleu de l'après-midi (250°) et le doré du
//       soir (75°), l'interpolation CARTÉSIENNE passe par le neutre —
//       jamais par un vert saturé (ce que ferait un lerp d'angle).
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/color/circadian_rhythm.dart';
import 'package:tv_king/core/color/oklab.dart';

void main() {
  test('les ancres du matin et du soir répondent aux bonnes températures',
      () {
    final CircadianState aube = circadianStateAt(6.0);
    expect(aube.hueDeg, closeTo(232, 0.5), reason: 'aube : bleu d\'acier');
    final CircadianState soir = circadianStateAt(19.0);
    expect(soir.hueDeg, closeTo(75, 0.5), reason: 'soir : doré');
    expect(soir.glow, greaterThan(aube.glow),
        reason: 'l\'aura s\'intensifie quand la pièce s\'assombrit');
    final CircadianState apresMidi = circadianStateAt(15.0);
    expect(apresMidi.chroma, lessThan(soir.chroma),
        reason: 'le pic d\'attention diurne demande la neutralité');
  });

  test('CONTINUITÉ : 24 h échantillonnées à la minute, aucun saut', () {
    Oklab at(int minuteOfDay) {
      final CircadianState s = circadianStateAt(minuteOfDay / 60 % 24);
      return Oklch(0.5, s.chroma, s.hueDeg).toOklab();
    }

    double maxStep = 0;
    double maxGlowStep = 0;
    for (int m = 0; m < 24 * 60; m++) {
      final double step = at(m).deltaE(at(m + 1));
      if (step > maxStep) maxStep = step;
      final double g1 = circadianStateAt(m / 60 % 24).glow;
      final double g2 = circadianStateAt((m + 1) / 60 % 24).glow;
      if ((g2 - g1).abs() > maxGlowStep) maxGlowStep = (g2 - g1).abs();
    }
    expect(maxStep, lessThan(0.004),
        reason: 'un pas d\'une minute doit rester très en dessous du seuil '
            'de perception (ΔE ≈ 0.01)');
    expect(maxGlowStep, lessThan(0.01));
  });

  test('AUCUN VERT SATURÉ sur 24 h : si la teinte traverse [100°, 200°], '
      'c\'est à chroma quasi nulle (le passage par le neutre)', () {
    for (int m = 0; m < 24 * 60; m++) {
      final CircadianState s = circadianStateAt(m / 60 % 24);
      if (s.hueDeg >= 100 && s.hueDeg <= 200) {
        expect(s.chroma, lessThan(0.03),
            reason: 'à ${(m / 60).toStringAsFixed(2)} h : teinte '
                '${s.hueDeg.toStringAsFixed(1)}° avec chroma ${s.chroma}');
      }
    }
  });

  test('temperByCircadian : le contenu commande (75 %), l\'heure infléchit',
      () {
    const Oklch contenu = Oklch(0.70, 0.10, 20); // rouge d'affiche
    final CircadianState nuit = circadianStateAt(23.0); // ambre profond
    final Oklch tempere = temperByCircadian(contenu, nuit);
    // La clarté du contenu est préservée (le circadien ne touche pas L).
    expect(tempere.l, closeTo(0.70, 1e-9));
    // La teinte a bougé VERS l'ambre, mais reste dominée par le contenu.
    expect(tempere.h, greaterThan(contenu.h));
    expect(tempere.h, lessThan(nuit.hueDeg));
  });
}
