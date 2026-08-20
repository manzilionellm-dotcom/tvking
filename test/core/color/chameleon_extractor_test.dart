// =========================================================
//  chameleon_extractor_test.dart — l'affiche propose, le Gouverneur dispose
// =========================================================
//  Vérité à verrouiller : sur des images synthétiques dont on CONNAÎT la
//  bonne réponse, l'extracteur trouve la couleur du SUJET (pas du fond),
//  le Gouverneur borne le résultat (jamais d'enseigne de casino, jamais
//  de gris teinté douteux), et tout est DÉTERMINISTE (même affiche →
//  même ambiance, à l'octet près — graine fixe).
// =========================================================

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/color/chameleon_extractor.dart';
import 'package:tv_king/core/color/oklab.dart';

/// Fabrique une image RGBA unie de [w]×[h] pixels.
Uint8List uniform(int w, int h, int r, int g, int b, {int a = 255}) {
  final Uint8List bytes = Uint8List(w * h * 4);
  for (int i = 0; i < w * h; i++) {
    bytes[i * 4] = r;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = b;
    bytes[i * 4 + 3] = a;
  }
  return bytes;
}

/// Peint un rectangle plein dans une image RGBA existante.
void fillRect(Uint8List bytes, int imgW, int x0, int y0, int x1, int y1,
    int r, int g, int b) {
  for (int y = y0; y < y1; y++) {
    for (int x = x0; x < x1; x++) {
      final int i = (y * imgW + x) * 4;
      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
      bytes[i + 3] = 255;
    }
  }
}

void main() {
  test('affiche unie rouge → la couleur extraite EST le rouge, gouverné',
      () {
    final ChameleonExtraction x =
        extractDominantColor(uniform(12, 12, 255, 0, 0), 12, 12);
    // Dominante brute : le rouge sRGB (teinte ≈ 29.2° en OKLCH).
    expect(x.dominant.h, closeTo(29.2, 1.0));
    expect(x.dominant.l, closeTo(0.628, 0.01));
    // Gouverné : chroma plafonnée (0.115), clarté ramenée dans la bande
    // ambiance [0.62, 0.82] — teinte INTACTE (l'identité ne se négocie pas).
    expect(x.governed, isNotNull);
    expect(x.governed!.c, closeTo(ChameleonGovernor.maxChroma, 1e-9));
    expect(x.governed!.h, closeTo(29.2, 1.0));
    expect(x.governed!.l, inInclusiveRange(
        ChameleonGovernor.minL, ChameleonGovernor.maxL));
  });

  test('le SUJET central coloré gagne contre un fond gris majoritaire', () {
    // 24×24 : fond gris sombre, pavé bleu 12×12 au centre (le « sujet »).
    final Uint8List img = uniform(24, 24, 60, 60, 60);
    fillRect(img, 24, 6, 6, 18, 18, 0, 0, 255);
    final ChameleonExtraction x = extractDominantColor(img, 24, 24);
    expect(x.governed, isNotNull,
        reason: 'un sujet aussi saturé mérite une ambiance');
    expect(x.governed!.h, inInclusiveRange(254, 274),
        reason: 'la teinte du bleu sRGB est ≈ 264° — le fond gris, même '
            'majoritaire en surface, ne doit pas gagner');
    expect(x.governed!.l,
        greaterThanOrEqualTo(ChameleonGovernor.minL),
        reason: 'le bleu pur (L 0.45) est éclairci dans la bande ambiance');
  });

  test('affiche terne (gris) → PAS d\'ambiance : le Gouverneur rend null',
      () {
    final ChameleonExtraction x =
        extractDominantColor(uniform(16, 16, 128, 128, 128), 16, 16);
    expect(x.dominant.c, lessThan(ChameleonGovernor.minChroma));
    expect(x.governed, isNull,
        reason: 'mieux vaut l\'ambiance neutre de l\'univers qu\'un gris '
            'teinté douteux');
  });

  test('image transparente → neutre assumé, jamais d\'erreur', () {
    final ChameleonExtraction x =
        extractDominantColor(uniform(8, 8, 200, 40, 40, a: 0), 8, 8);
    expect(x.governed, isNull);
  });

  test('DÉTERMINISME : même affiche → même couleur, à l\'octet près', () {
    final Uint8List img = uniform(32, 18, 20, 24, 30);
    fillRect(img, 32, 8, 4, 24, 14, 214, 58, 48); // pavé « ember »
    fillRect(img, 32, 26, 12, 32, 18, 0, 120, 90); // coin vert parasite
    final ChameleonExtraction a = extractDominantColor(img, 32, 18);
    final ChameleonExtraction b = extractDominantColor(img, 32, 18);
    expect(a.dominant.l, b.dominant.l);
    expect(a.dominant.c, b.dominant.c);
    expect(a.dominant.h, b.dominant.h);
    expect(a.governed?.h, b.governed?.h);
    // Et le pavé ember central l'emporte sur le coin vert excentré.
    expect(a.governed, isNotNull);
    expect(a.governed!.h, inInclusiveRange(15, 45),
        reason: 'l\'ember (≈ 29°) domine : plus massif ET central');
  });

  test('le coût est BORNÉ : une « affiche » 400×600 passe par la grille '
      '48×27, pas par ses 240 000 pixels', () {
    final Stopwatch chrono = Stopwatch()..start();
    final Uint8List img = uniform(400, 600, 30, 60, 120);
    extractDominantColor(img, 400, 600);
    chrono.stop();
    // Généreux ×10 pour l'aléa CI : la vraie cible terrain est < 8 ms.
    expect(chrono.elapsedMilliseconds, lessThan(80));
  });
}
