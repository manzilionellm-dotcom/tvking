// =========================================================
//  ambient_engine_test.dart — Briques PURES du moteur ambiant
// =========================================================
//  On teste tout ce qui est déterministe et sans réseau :
//    1. clampSurface : les règles de contraste (S ≤ 0.65, L ∈ [0.15, 0.45])
//       tiennent pour les cas extrêmes du cahier des charges (logo rouge
//       vif, logo blanc, noir pur) ;
//    2. deltaE76 : 0 pour couleurs identiques, grand pour noir/blanc,
//       petit pour deux gris voisins (seuil anti-pompage ΔE < 10) ;
//    3. quantizeRgbaForAmbient : dominante/sombre/luminance correctes sur
//       des frames synthétiques 64×36 (unie, bicolore, transparente) ;
//    4. compose : la palette assemblée respecte les bornes de chaque rôle ;
//    5. débounce + ΔE : au plus une émission par fenêtre, variations
//       imperceptibles retenues, le repli est immédiat.
// =========================================================
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/theme/ambient_engine.dart';

/// Tolérance d'ARRONDI 8 bits : HSLColor.toColor() quantifie chaque canal
/// sur 0..255, donc une luminosité clampée à 0.45 peut ressortir à 0.451
/// (± 1/255 ≈ 0.004). Imperceptible et sans effet sur le contraste — les
/// bornes testées incluent cette tolérance.
const double kEps = 1 / 255;

/// Frame RGBA synthétique 64×36 remplie par [painter] (index de pixel → RGBA).
Uint8List frame(List<int> Function(int i) painter) {
  final Uint8List px = Uint8List(64 * 36 * 4);
  for (int i = 0; i < 64 * 36; i++) {
    final List<int> c = painter(i);
    px[i * 4] = c[0];
    px[i * 4 + 1] = c[1];
    px[i * 4 + 2] = c[2];
    px[i * 4 + 3] = c[3];
  }
  return px;
}

void main() {
  group('clampSurface (règles de contraste des fonds)', () {
    test('un rouge vif est désaturé et assombri dans les bornes', () {
      final HSLColor out = HSLColor.fromColor(
          AmbientEngine.clampSurface(const Color(0xFFFF0000)));
      expect(out.saturation, lessThanOrEqualTo(0.65 + kEps));
      expect(out.lightness, inInclusiveRange(0.15 - kEps, 0.45 + kEps));
    });

    test('un blanc pur devient un fond sombre lisible', () {
      final HSLColor out = HSLColor.fromColor(
          AmbientEngine.clampSurface(const Color(0xFFFFFFFF)));
      expect(out.lightness, lessThanOrEqualTo(0.45 + kEps));
    });

    test('un noir pur est remonté au plancher (pas de trou noir)', () {
      final HSLColor out = HSLColor.fromColor(
          AmbientEngine.clampSurface(const Color(0xFF000000)));
      expect(out.lightness, greaterThanOrEqualTo(0.15 - kEps));
    });
  });

  group('deltaE76 (seuil anti-pompage)', () {
    test('couleurs identiques → 0', () {
      expect(
          AmbientEngine.deltaE76(
              const Color(0xFF336699), const Color(0xFF336699)),
          0);
    });

    test('noir vs blanc → très grand (≈100)', () {
      expect(
          AmbientEngine.deltaE76(
              const Color(0xFF000000), const Color(0xFFFFFFFF)),
          greaterThan(90));
    });

    test('deux gris voisins → sous le seuil de 10 (variation ignorée)', () {
      expect(
          AmbientEngine.deltaE76(
              const Color(0xFF303030), const Color(0xFF343434)),
          lessThan(AmbientEngine.kMinDeltaE));
    });
  });

  group('quantizeRgbaForAmbient (frame 64×36)', () {
    test('frame unie rouge → dominante rouge, luminance basse', () {
      final Int32List r =
          quantizeRgbaForAmbient(frame((_) => <int>[200, 16, 16, 255]));
      final Color dom = Color(r[0]);
      expect((dom.r * 255).round(), inInclusiveRange(190, 210));
      expect((dom.g * 255).round(), lessThan(40));
      // Luminance ≈ 0.2126 × (200/255) ≈ 0.18 (×1000).
      expect(r[3], inInclusiveRange(120, 260));
    });

    test('frame majoritairement sombre + zone vive → sombre ET vibrante', () {
      // 80 % noir-bleuté, 20 % orange vif.
      final Int32List r = quantizeRgbaForAmbient(frame((int i) =>
          i % 5 == 0 ? <int>[240, 130, 20, 255] : <int>[10, 10, 24, 255]));
      final Color dominant = Color(r[0]);
      final Color vibrant = Color(r[1]);
      final Color dark = Color(r[2]);
      // Dominante = l'aplat sombre ; la vibrante attrape l'orange.
      expect((dominant.b * 255).round(), greaterThan((dominant.g * 255).round()));
      expect((vibrant.r * 255).round(), greaterThan(200));
      expect(HSLColor.fromColor(dark).lightness, lessThanOrEqualTo(0.35));
    });

    test('frame 100 % transparente → sentinelle [0,0,0,0]', () {
      final Int32List r =
          quantizeRgbaForAmbient(frame((_) => <int>[255, 255, 255, 0]));
      expect(r, Int32List.fromList(<int>[0, 0, 0, 0]));
    });
  });

  group('compose (rôles de la palette)', () {
    test('chaque rôle respecte ses bornes de luminosité', () {
      final AmbientPalette p = AmbientEngine.compose(
        dominant: const Color(0xFFFF2200),
        vibrant: const Color(0xFFFFAA00),
        dark: const Color(0xFF220000),
      );
      expect(HSLColor.fromColor(p.primary).lightness,
          inInclusiveRange(0.15 - kEps, 0.45 + kEps));
      expect(HSLColor.fromColor(p.scrim).lightness,
          inInclusiveRange(0.08 - kEps, 0.22 + kEps));
      expect(HSLColor.fromColor(p.glow).lightness,
          inInclusiveRange(0.30 - kEps, 0.60 + kEps));
      expect(HSLColor.fromColor(p.accent).lightness,
          inInclusiveRange(0.35 - kEps, 0.65 + kEps));
      for (final Color c in <Color>[p.primary, p.scrim]) {
        expect(HSLColor.fromColor(c).saturation, lessThanOrEqualTo(0.65 + kEps));
      }
    });
  });

  group('débounce (1 palette / 2 s) + seuil ΔE', () {
    // Palettes de test franchement différentes (ΔE >> 10 sur `primary`).
    const AmbientPalette rouge = AmbientPalette(
        primary: Color(0xFF5A1A1A),
        glow: Color(0xFF8A3030),
        scrim: Color(0xFF200808),
        accent: Color(0xFF9A4040));
    const AmbientPalette bleu = AmbientPalette(
        primary: Color(0xFF1A2A5A),
        glow: Color(0xFF30508A),
        scrim: Color(0xFF081020),
        accent: Color(0xFF40609A));
    const AmbientPalette vert = AmbientPalette(
        primary: Color(0xFF1A5A2A),
        glow: Color(0xFF308A50),
        scrim: Color(0xFF082010),
        accent: Color(0xFF409A60));

    test('rafale : émission immédiate, puis la DERNIÈRE gagne après 2 s', () {
      fakeAsync((FakeAsync async) {
        final AmbientEngine e = AmbientEngine.instance;
        e.reset();
        async.elapse(AmbientEngine.kEmitInterval); // fenêtre du reset purgée

        e.debugSubmit(rouge);
        expect(e.palette.value, rouge, reason: '1re palette : immédiate');

        // Rafale dans la fenêtre de 2 s : rien ne sort tout de suite…
        e.debugSubmit(bleu);
        e.debugSubmit(vert);
        expect(e.palette.value, rouge);
        expect(e.debugStats.value?.emitted, isFalse);

        // …et à la fin de la fenêtre, seule la DERNIÈRE (vert) est émise.
        async.elapse(AmbientEngine.kEmitInterval);
        expect(e.palette.value, vert);
        e.reset();
        async.elapse(AmbientEngine.kEmitInterval);
      });
    });

    test('variation imperceptible (ΔE < 10) : jamais émise', () {
      fakeAsync((FakeAsync async) {
        final AmbientEngine e = AmbientEngine.instance;
        e.reset();
        async.elapse(AmbientEngine.kEmitInterval);

        e.debugSubmit(rouge);
        expect(e.palette.value, rouge);
        async.elapse(AmbientEngine.kEmitInterval);

        // Quasi la même teinte de fond → retenue, même hors fenêtre.
        final AmbientPalette rougeVoisin = AmbientPalette(
            primary: const Color(0xFF5C1C1C),
            glow: rouge.glow,
            scrim: rouge.scrim,
            accent: rouge.accent);
        e.debugSubmit(rougeVoisin);
        expect(e.palette.value, rouge, reason: 'anti-pompage');
        expect(e.debugStats.value?.emitted, isFalse);
        e.reset();
        async.elapse(AmbientEngine.kEmitInterval);
      });
    });

    test('reset() ramène immédiatement la palette Maison Noir', () {
      final AmbientEngine e = AmbientEngine.instance;
      e.reset();
      expect(e.palette.value, AmbientPalette.maisonNoir());
      expect(e.videoLuminance.value, isNull);
      expect(e.debugStats.value?.source, 'repli');
    });
  });
}
