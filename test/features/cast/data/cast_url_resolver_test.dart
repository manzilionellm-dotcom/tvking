// =========================================================
//  cast_url_resolver_test.dart — URL de cast = URL du lecteur
// =========================================================
//  Terrain 2026-07-10 (panel thekung, « /live/ requis ») : le lecteur
//  jouait via le format mémorisé `live:ts` mais le cast partait avec
//  l'URL brute `host/U/P/ID.ts` → pré-vol 404 → 8/8 échecs. Le
//  résolveur applique le même format mémorisé, avec les mêmes gardes.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_url_resolver.dart';
import 'package:tv_king/features/player/data/xtream_url_variants.dart';

void main() {
  group('CastUrlResolver.resolveWith', () {
    const String naked = 'http://panel.example/USER/PASS/127302.ts';

    test('format mémorisé live:ts → préfixe /live/ appliqué (cas thekung)',
        () {
      expect(
        CastUrlResolver.resolveWith(
          rawUrl: naked,
          type: XtreamContentType.live,
          memorizedCode: 'live:ts',
        ),
        'http://panel.example/live/USER/PASS/127302.ts',
      );
    });

    test('aucun format mémorisé → URL brute inchangée', () {
      expect(
        CastUrlResolver.resolveWith(
          rawUrl: naked,
          type: XtreamContentType.live,
          memorizedCode: null,
        ),
        naked,
      );
    });

    test('format HLS mémorisé pour du LIVE → ignoré (anti-saturation '
        'compte 1-connexion, même garde que le lecteur)', () {
      expect(
        CastUrlResolver.resolveWith(
          rawUrl: naked,
          type: XtreamContentType.live,
          memorizedCode: 'live:m3u8',
        ),
        naked,
      );
    });

    test('URL non-Xtream → jamais réécrite, même avec un code', () {
      const String odd = 'http://cdn.example/stream/abc.ts';
      expect(
        CastUrlResolver.resolveWith(
          rawUrl: odd,
          type: XtreamContentType.live,
          memorizedCode: 'live:ts',
        ),
        odd,
        reason: 'applyFormat renvoie null hors schéma Xtream → brute',
      );
    });

    test('VOD : le format mémorisé s\'applique (pas de garde HLS)', () {
      expect(
        CastUrlResolver.resolveWith(
          rawUrl: 'http://panel.example/USER/PASS/9.mp4',
          type: XtreamContentType.movie,
          memorizedCode: 'movie:',
        ),
        'http://panel.example/movie/USER/PASS/9.mp4',
      );
    });
  });
}
