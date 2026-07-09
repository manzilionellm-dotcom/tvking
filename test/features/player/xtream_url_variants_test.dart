// =========================================================
//  xtream_url_variants_test.dart — Variantes d'URL Xtream
// =========================================================
//  Garantit : l'ORDRE exact des cascades (live / movie / series),
//  la déduplication, la préservation de la query (tokens), le refus
//  de réécrire ce qui ne ressemble pas à du Xtream, le codage du
//  format gagnant (formatCodeOf) et son application (applyFormat)
//  utilisée par la mémorisation par source.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/xtream_url_variants.dart';

void main() {
  group('cascade LIVE', () {
    test('forme courte .ts (le cas France 2 / 404) → 4 variantes ordonnées',
        () {
      final List<String> v = XtreamUrlVariants.cascade(
          'http://host.tv:8080/USER/PASS/1234.ts');
      expect(v, <String>[
        'http://host.tv:8080/USER/PASS/1234.ts', //      a) original
        'http://host.tv:8080/live/USER/PASS/1234.ts', //   b) TS d'abord
        'http://host.tv:8080/live/USER/PASS/1234.m3u8', // c) HLS ensuite
        'http://host.tv:8080/USER/PASS/1234.m3u8', //      d)
      ]);
    });

    test('forme /live/….ts : l\'original absorbe la variante c', () {
      final List<String> v = XtreamUrlVariants.cascade(
          'http://host.tv/live/USER/PASS/42.ts');
      expect(v, <String>[
        'http://host.tv/live/USER/PASS/42.ts',
        'http://host.tv/live/USER/PASS/42.m3u8',
        'http://host.tv/USER/PASS/42.m3u8',
      ]);
    });

    test('forme /live/….m3u8 : l\'original absorbe la variante b', () {
      final List<String> v = XtreamUrlVariants.cascade(
          'http://host.tv/live/USER/PASS/42.m3u8');
      expect(v, <String>[
        'http://host.tv/live/USER/PASS/42.m3u8',
        'http://host.tv/live/USER/PASS/42.ts',
        'http://host.tv/USER/PASS/42.m3u8',
      ]);
    });

    test('la query (token) est préservée sur toutes les variantes', () {
      final List<String> v = XtreamUrlVariants.cascade(
          'http://host.tv/USER/PASS/7.ts?token=abc&x=1');
      expect(v, hasLength(4));
      for (final String url in v) {
        expect(url, contains('token=abc'));
        expect(url, contains('x=1'));
      }
    });

    test('ID sans extension : variantes générées quand même', () {
      final List<String> v =
          XtreamUrlVariants.cascade('http://host.tv/USER/PASS/99');
      expect(v, <String>[
        'http://host.tv/USER/PASS/99',
        'http://host.tv/live/USER/PASS/99.ts',
        'http://host.tv/live/USER/PASS/99.m3u8',
        'http://host.tv/USER/PASS/99.m3u8',
      ]);
    });

    test('extension non-live (.mp4) en cascade LIVE → URL intacte', () {
      expect(
        XtreamUrlVariants.cascade('http://host.tv/USER/PASS/9.mp4'),
        <String>['http://host.tv/USER/PASS/9.mp4'],
      );
    });

    test('formes non-Xtream → URL intacte', () {
      for (final String url in <String>[
        'http://cdn.tv/stream.m3u8',
        'http://cdn.tv/a/b/c/d/e.ts',
        'http://host.tv/get/PASS/player_api.php',
        '::pas une url::',
        '/data/user/0/app/rec/film.ts', // fichier local
      ]) {
        expect(XtreamUrlVariants.cascade(url), <String>[url],
            reason: url);
      }
    });

    test('les codes de format des candidates live sont corrects', () {
      final List<XtreamUrlCandidate> v = XtreamUrlVariants.cascadeFor(
        'http://host.tv/USER/PASS/1.ts',
        XtreamContentType.live,
      );
      expect(
        v.map((XtreamUrlCandidate c) => c.formatCode),
        // TS préfixé AVANT le HLS (1 connexion continue, compte max-1).
        <String>['none:ts', 'live:ts', 'live:m3u8', 'none:m3u8'],
      );
    });
  });

  group('cascade MOVIE / SERIES (extension du conteneur conservée)', () {
    test('film avec préfixe → variante nue en repli', () {
      final List<XtreamUrlCandidate> v = XtreamUrlVariants.cascadeFor(
        'http://host.tv/movie/USER/PASS/77.mp4',
        XtreamContentType.movie,
      );
      expect(v.map((XtreamUrlCandidate c) => c.url), <String>[
        'http://host.tv/movie/USER/PASS/77.mp4',
        'http://host.tv/USER/PASS/77.mp4',
      ]);
      expect(v.last.formatCode, 'none:');
    });

    test('film SANS préfixe → variante /movie/ en tête de repli', () {
      final List<XtreamUrlCandidate> v = XtreamUrlVariants.cascadeFor(
        'http://host.tv/USER/PASS/77.mkv',
        XtreamContentType.movie,
      );
      expect(v.map((XtreamUrlCandidate c) => c.url), <String>[
        'http://host.tv/USER/PASS/77.mkv',
        'http://host.tv/movie/USER/PASS/77.mkv',
      ]);
      expect(v[1].formatCode, 'movie:');
    });

    test('épisode de série avec préfixe → variante nue en repli', () {
      final List<XtreamUrlCandidate> v = XtreamUrlVariants.cascadeFor(
        'http://host.tv/series/USER/PASS/501.mkv',
        XtreamContentType.series,
      );
      expect(v.map((XtreamUrlCandidate c) => c.url), <String>[
        'http://host.tv/series/USER/PASS/501.mkv',
        'http://host.tv/USER/PASS/501.mkv',
      ]);
    });

    test('épisode SANS préfixe → variante /series/ proposée', () {
      final List<XtreamUrlCandidate> v = XtreamUrlVariants.cascadeFor(
        'http://host.tv/USER/PASS/501.avi',
        XtreamContentType.series,
      );
      expect(v.map((XtreamUrlCandidate c) => c.url), <String>[
        'http://host.tv/USER/PASS/501.avi',
        'http://host.tv/series/USER/PASS/501.avi',
      ]);
    });

    test('l\'extension du conteneur est TOUJOURS conservée', () {
      for (final String ext in <String>['mp4', 'mkv', 'avi']) {
        final List<XtreamUrlCandidate> v = XtreamUrlVariants.cascadeFor(
          'http://host.tv/movie/U/P/1.$ext',
          XtreamContentType.movie,
        );
        for (final XtreamUrlCandidate c in v) {
          expect(c.url, endsWith('.$ext'));
        }
      }
    });
  });

  group('formatCodeOf / applyFormat (mémorisation par source)', () {
    test('formatCodeOf encode préfixe + extension pour le live', () {
      expect(XtreamUrlVariants.formatCodeOf('http://h/U/P/1.ts'), 'none:ts');
      expect(XtreamUrlVariants.formatCodeOf('http://h/live/U/P/1.m3u8'),
          'live:m3u8');
      // VOD : l'extension appartient au contenu, pas au panel.
      expect(XtreamUrlVariants.formatCodeOf('http://h/movie/U/P/1.mp4'),
          'movie:');
      expect(XtreamUrlVariants.formatCodeOf('http://h/series/U/P/1.mkv'),
          'series:');
      expect(XtreamUrlVariants.formatCodeOf('http://cdn/x.m3u8'), isNull);
    });

    test('applyFormat réécrit un live vers le format mémorisé', () {
      expect(
        XtreamUrlVariants.applyFormat(
            'http://h:8080/U/P/22.ts', 'live:m3u8'),
        'http://h:8080/live/U/P/22.m3u8',
      );
      expect(
        XtreamUrlVariants.applyFormat(
            'http://h/live/U/P/22.m3u8', 'none:ts'),
        'http://h/U/P/22.ts',
      );
    });

    test('applyFormat VOD : préfixe appliqué, extension conservée', () {
      expect(
        XtreamUrlVariants.applyFormat(
            'http://h/U/P/9.mkv', 'movie:'),
        'http://h/movie/U/P/9.mkv',
      );
      expect(
        XtreamUrlVariants.applyFormat(
            'http://h/series/U/P/9.mp4', 'none:'),
        'http://h/U/P/9.mp4',
      );
    });

    test('applyFormat refuse ce qui n\'est pas réécrivable', () {
      // Pas du schéma Xtream (CDN, fichier local) → null.
      expect(XtreamUrlVariants.applyFormat('http://cdn/x.ts', 'live:ts'),
          isNull);
      expect(
          XtreamUrlVariants.applyFormat(
              '/data/local/rec.ts', 'live:ts'),
          isNull);
      // Code invalide → null.
      expect(
          XtreamUrlVariants.applyFormat(
              'http://h/U/P/1.ts', 'nimporte'),
          isNull);
      expect(
          XtreamUrlVariants.applyFormat(
              'http://h/U/P/1.ts', 'vod:ts'),
          isNull);
    });

    test('round-trip : le code du gagnant ré-applique la même URL', () {
      const String original = 'http://h/U/P/5.ts';
      final List<XtreamUrlCandidate> v = XtreamUrlVariants.cascadeFor(
          original, XtreamContentType.live);
      for (final XtreamUrlCandidate c in v) {
        expect(XtreamUrlVariants.applyFormat(original, c.formatCode), c.url,
            reason: c.formatCode);
      }
    });
  });

  group('detectType', () {
    test('détecte le type par le préfixe, null pour la forme nue', () {
      expect(XtreamUrlVariants.detectType('http://h/live/U/P/1.ts'),
          XtreamContentType.live);
      expect(XtreamUrlVariants.detectType('http://h/movie/U/P/1.mp4'),
          XtreamContentType.movie);
      expect(XtreamUrlVariants.detectType('http://h/series/U/P/1.mkv'),
          XtreamContentType.series);
      expect(XtreamUrlVariants.detectType('http://h/U/P/1.ts'), isNull);
      expect(XtreamUrlVariants.detectType('http://cdn/x.ts'), isNull);
    });
  });
}
