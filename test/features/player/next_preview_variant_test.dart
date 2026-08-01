// =========================================================
//  next_preview_variant_test.dart — Seconde chance de l'aperçu
// =========================================================
//  TERRAIN 2026-08-01 (preuve en main) : TF1 JOUE en plein écran pendant
//  que l'aperçu reçoit « HTTP 404 » sur la MÊME chaîne. Raison : le plein
//  écran déroule la cascade d'URL Xtream, l'aperçu s'arrêtait à la
//  première forme. Or ce panel ne sert le live que sous
//  `live/USER/PASS/ID.ts` — la forme NUE renvoie 404 → aperçu mort sur
//  toutes les chaînes, à vie.
//
//  Contrat de nextPreviewVariant (fonction pure) :
//    1. après la forme d'origine, propose `live/…/….ts` ;
//    2. puis le HLS `live/…/….m3u8` ;
//    3. plus rien à proposer → null (l'aperçu abandonne proprement) ;
//    4. URL hors schéma Xtream → aucune invention.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/xtream_url_variants.dart';

void main() {
  // La forme NUE qui renvoyait 404 chez le client.
  const String nue = 'http://thekung.801802.com/USER/PASS/861325.ts';

  test('1re seconde chance : la forme préfixée « live/…/….ts »', () {
    final XtreamUrlCandidate? c = nextPreviewVariant(
      url: nue,
      type: XtreamContentType.live,
      tried: <String>{'original', 'none:ts'},
    );
    expect(c, isNotNull);
    expect(c!.url, 'http://thekung.801802.com/live/USER/PASS/861325.ts');
    expect(c.formatCode, 'live:ts');
  });

  test('2e seconde chance : le HLS, seulement APRÈS le .ts', () {
    final XtreamUrlCandidate? c = nextPreviewVariant(
      url: nue,
      type: XtreamContentType.live,
      tried: <String>{'original', 'none:ts', 'live:ts'},
    );
    expect(c, isNotNull);
    expect(c!.url, endsWith('.m3u8'));
    expect(c.formatCode, 'live:m3u8');
  });

  test('tout essayé → null (l\'aperçu abandonne, pas de boucle)', () {
    final XtreamUrlCandidate? c = nextPreviewVariant(
      url: nue,
      type: XtreamContentType.live,
      tried: <String>{
        'original', 'none:ts', 'live:ts', 'live:m3u8', 'none:m3u8',
      },
    );
    expect(c, isNull);
  });

  test('URL hors schéma Xtream : on n\'invente RIEN', () {
    final XtreamUrlCandidate? c = nextPreviewVariant(
      url: 'http://exemple.com/flux.m3u8',
      type: XtreamContentType.live,
      tried: <String>{'original'},
    );
    // Seule l'originale existe, et elle est déjà essayée.
    expect(c, isNull);
  });

  test('rien d\'essayé → on repart de la forme d\'origine', () {
    final XtreamUrlCandidate? c = nextPreviewVariant(
      url: nue,
      type: XtreamContentType.live,
      tried: <String>{},
    );
    expect(c!.url, nue);
  });
}
