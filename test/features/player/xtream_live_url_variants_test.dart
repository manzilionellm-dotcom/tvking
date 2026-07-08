// =========================================================
//  xtream_live_url_variants_test.dart — Cascade de variantes live Xtream
// =========================================================
//  Garantit l'ORDRE exact de la cascade décidée (original →
//  /live/….m3u8 → /live/….ts → ….m3u8 sans préfixe), la
//  déduplication, la préservation de la query (tokens), et le
//  refus de réécrire ce qui ne ressemble pas à du live Xtream.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/xtream_live_url_variants.dart';

void main() {
  group('XtreamLiveUrlVariants.cascade', () {
    test('forme courte .ts (le cas France 2 / 404) → 4 variantes ordonnées',
        () {
      final List<String> v = XtreamLiveUrlVariants.cascade(
          'http://host.tv:8080/USER/PASS/1234.ts');
      expect(v, <String>[
        'http://host.tv:8080/USER/PASS/1234.ts', //      a) original
        'http://host.tv:8080/live/USER/PASS/1234.m3u8', // b)
        'http://host.tv:8080/live/USER/PASS/1234.ts', //   c)
        'http://host.tv:8080/USER/PASS/1234.m3u8', //      d)
      ]);
    });

    test('forme /live/….ts : l\'original absorbe la variante c', () {
      final List<String> v = XtreamLiveUrlVariants.cascade(
          'http://host.tv/live/USER/PASS/42.ts');
      expect(v, <String>[
        'http://host.tv/live/USER/PASS/42.ts',
        'http://host.tv/live/USER/PASS/42.m3u8',
        'http://host.tv/USER/PASS/42.m3u8',
      ]);
    });

    test('forme /live/….m3u8 : l\'original absorbe la variante b', () {
      final List<String> v = XtreamLiveUrlVariants.cascade(
          'http://host.tv/live/USER/PASS/42.m3u8');
      expect(v, <String>[
        'http://host.tv/live/USER/PASS/42.m3u8',
        'http://host.tv/live/USER/PASS/42.ts',
        'http://host.tv/USER/PASS/42.m3u8',
      ]);
    });

    test('forme courte .m3u8 : l\'original absorbe la variante d', () {
      final List<String> v = XtreamLiveUrlVariants.cascade(
          'http://host.tv/USER/PASS/42.m3u8');
      expect(v, <String>[
        'http://host.tv/USER/PASS/42.m3u8',
        'http://host.tv/live/USER/PASS/42.m3u8',
        'http://host.tv/live/USER/PASS/42.ts',
      ]);
    });

    test('la query (token) est préservée sur toutes les variantes', () {
      final List<String> v = XtreamLiveUrlVariants.cascade(
          'http://host.tv/USER/PASS/7.ts?token=abc&x=1');
      expect(v, hasLength(4));
      for (final String url in v) {
        expect(url, contains('token=abc'));
        expect(url, contains('x=1'));
      }
    });

    test('ID sans extension : variantes générées quand même', () {
      final List<String> v =
          XtreamLiveUrlVariants.cascade('http://host.tv/USER/PASS/99');
      expect(v, <String>[
        'http://host.tv/USER/PASS/99',
        'http://host.tv/live/USER/PASS/99.m3u8',
        'http://host.tv/live/USER/PASS/99.ts',
        'http://host.tv/USER/PASS/99.m3u8',
      ]);
    });

    test('extension inconnue (.php) → URL intacte, aucune variante', () {
      expect(
        XtreamLiveUrlVariants.cascade(
            'http://host.tv/get/PASS/player_api.php'),
        <String>['http://host.tv/get/PASS/player_api.php'],
      );
    });

    test('nombre de segments non-Xtream → URL intacte', () {
      expect(
        XtreamLiveUrlVariants.cascade('http://cdn.tv/stream.m3u8'),
        <String>['http://cdn.tv/stream.m3u8'],
      );
      expect(
        XtreamLiveUrlVariants.cascade('http://cdn.tv/a/b/c/d/e.ts'),
        <String>['http://cdn.tv/a/b/c/d/e.ts'],
      );
    });

    test('préfixe non-live à 4 segments → URL intacte', () {
      expect(
        XtreamLiveUrlVariants.cascade('http://host.tv/movie/U/P/9.ts'),
        <String>['http://host.tv/movie/U/P/9.ts'],
      );
    });

    test('entrée non parsable → renvoyée telle quelle', () {
      expect(
        XtreamLiveUrlVariants.cascade('::pas une url::'),
        <String>['::pas une url::'],
      );
    });
  });
}
