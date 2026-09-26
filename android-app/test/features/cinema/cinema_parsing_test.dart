// =========================================================
//  cinema_parsing_test.dart — Module Cinéma : langue + lecture Xtream
// =========================================================
//  Verrouille :
//   (a) la langue déduite des noms de catégories réels (« FR | ACTION »,
//       « |EN| », « VOSTFR », « 华语电影 ») SANS faux positifs sur les mots
//       courants (« Films de Noël » n'est pas allemand, « In Theaters »
//       n'est pas hindi) ;
//   (b) la lecture tolérante des réponses Xtream (champs texte/nombre/vides,
//       `info` en liste vide, épisodes en objet OU en liste de listes) ;
//   (c) l'ordre des épisodes et l'« épisode suivant » (fin de saison →
//       saison suivante).
// =========================================================
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cinema/data/cinema_parsers.dart';
import 'package:tv_king/features/cinema/domain/cinema_language.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';

const CinemaSource _src = CinemaSource(
  key: 'p1',
  playlistId: 1,
  server: 'http://example.test:8080',
  username: 'u',
  password: 'p',
);

void main() {
  group('CinemaLanguage.detect', () {
    final Map<String, String?> cases = <String, String?>{
      'FR | ACTION': 'fr',
      '|EN| DRAMA': 'en',
      '[DE] Kino': 'de',
      'DE: Action': 'de',
      'AR - Films': 'ar',
      'VOSTFR': 'fr',
      'Films VF 2024': 'fr',
      'CHINESE MOVIES': 'zh',
      '华语电影': 'zh',
      'Bollywood Hits': 'hi',
      'TURKISH SERIES': 'tr',
      'Latino | Terror': 'es',
      'IT | Commedia': 'it',
      'Films de Noël': null,
      'Films en famille': null,
      'In Theaters': null,
      'Action': null,
      'Made in Italy': 'it',
      'Documentaires': null,
    };
    cases.forEach((String name, String? lang) {
      test('« $name » → $lang', () {
        expect(CinemaLanguage.detect(name), lang);
      });
    });

    test('la 1re langue citée l\'emporte', () {
      expect(CinemaLanguage.detect('EN | FR SUBS'), 'en');
    });

    test('noms de pistes audio (ISO 639-2)', () {
      expect(CinemaLanguage.labelFor('fre'), 'Français');
      expect(CinemaLanguage.labelFor('eng'), 'English');
      expect(CinemaLanguage.labelFor('zh-Hant'), '中文');
      expect(CinemaLanguage.labelFor('xyz'), 'XYZ');
      expect(CinemaLanguage.labelFor(null), isNull);
    });

    test('clé de recherche sans accents', () {
      expect(CinemaLanguage.searchKey('  Amélie   Poulain '), 'amelie poulain');
    });
  });

  group('parseCategories / mapTitles', () {
    test('catégories : ignore les entrées incomplètes', () {
      final List<({String id, String name})> c = parseCategories(<dynamic>[
        <String, dynamic>{'category_id': '10', 'category_name': 'FR | Action'},
        <String, dynamic>{'category_id': 11, 'category_name': ''},
        <String, dynamic>{'category_name': 'Sans id'},
        'garbage',
      ]);
      expect(c.length, 1);
      expect(c.first.id, '10');
    });

    test('films : URL, note sur 5 convertie, année lue dans le nom', () {
      final List<CinemaTitle> t = mapTitles(
        <dynamic>[
          <String, dynamic>{
            'stream_id': 42,
            'name': 'Inception (2010)',
            'stream_icon': 'http://img.test/a.jpg',
            'rating': '',
            'rating_5based': 4.4,
            'added': '1700000000',
            'category_id': '10',
            'container_extension': 'mkv',
          },
          <String, dynamic>{'stream_id': '', 'name': 'sans id'},
        ],
        kind: CinemaKind.movie,
        source: _src,
        categoryKeyById: const <String, String>{'10': 'fr action'},
      );
      expect(t.length, 1);
      final CinemaTitle m = t.first;
      expect(m.id, 'p1:m:42');
      expect(m.streamUrl, 'http://example.test:8080/movie/u/p/42.mkv');
      expect(m.rating, closeTo(8.8, 0.001));
      expect(m.year, '2010');
      expect(m.addedAt, 1700000000);
      expect(m.categoryKey, 'fr action');
      expect(m.posterUrl, 'http://img.test/a.jpg');
    });

    test('décodage depuis les octets + enveloppe {data: [...]}', () {
      final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(<String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'series_id': 7, 'name': 'Dark', 'cover': 'x', 'plot': 'N/A'},
        ],
      })));
      final List<CinemaTitle> t = mapTitles(
        decodeJsonBytes(bytes),
        kind: CinemaKind.series,
        source: _src,
        categoryKeyById: const <String, String>{},
        fallbackCategoryKey: 'fallback',
      );
      expect(t.single.id, 'p1:s:7');
      expect(t.single.streamUrl, isNull);
      expect(t.single.posterUrl, isNull, reason: 'URL non http ignorée');
      expect(t.single.plot, isNull, reason: '« N/A » = pas de résumé');
      expect(t.single.categoryKey, 'fallback');
    });
  });

  group('fiches', () {
    test('get_vod_info : info en liste vide = fiche vide, pas de crash', () {
      final CinemaDetails d = parseVodInfo(<String, dynamic>{'info': <dynamic>[]});
      expect(d.plot, isNull);
      expect(d.durationSec, 0);
    });

    test('get_vod_info : durée hh:mm:ss et backdrop en liste', () {
      final CinemaDetails d = parseVodInfo(<String, dynamic>{
        'info': <String, dynamic>{
          'plot': 'Un rêve dans un rêve.',
          'duration': '02:28:00',
          'backdrop_path': <String>['', 'https://img.test/b.jpg'],
          'rating': '8.4',
        },
      });
      expect(d.durationSec, 2 * 3600 + 28 * 60);
      expect(d.backdropUrl, 'https://img.test/b.jpg');
      expect(d.rating, 8.4);
    });

    test('get_series_info : épisodes en objet, tri, suivant inter-saison', () {
      final SeriesDetails s = parseSeriesInfo(
        <String, dynamic>{
          'info': <String, dynamic>{'plot': 'Winden, 2019.', 'episode_run_time': '52'},
          'seasons': <dynamic>[
            <String, dynamic>{'season_number': 1, 'name': 'Saison 1'},
            <String, dynamic>{'season_number': 2, 'name': 'Saison 2'},
            <String, dynamic>{'season_number': 3, 'name': 'Vide'},
          ],
          'episodes': <String, dynamic>{
            '2': <dynamic>[
              <String, dynamic>{'id': '201', 'episode_num': 1, 'title': 'Dark - S02E01 - Début', 'season': 2},
            ],
            '1': <dynamic>[
              <String, dynamic>{'id': '102', 'episode_num': 2, 'title': 'Dark S01E02', 'container_extension': 'mkv'},
              <String, dynamic>{'id': '101', 'episode_num': 1, 'title': 'Secrets', 'info': <String, dynamic>{'duration_secs': 3000}},
            ],
          },
        },
        source: _src,
        seriesId: 'p1:s:7',
        seriesName: 'Dark',
      );
      expect(s.seasons.map((CinemaSeason x) => x.number), <int>[1, 2],
          reason: 'la saison 3 sans épisode est masquée');
      final List<CinemaEpisode> s1 = s.episodes[1]!;
      expect(s1.map((CinemaEpisode e) => e.number), <int>[1, 2]);
      expect(s1[0].durationSec, 3000);
      expect(s1[1].title, '', reason: 'titre = seulement « Dark S01E02 »');
      expect(s1[1].streamUrl, 'http://example.test:8080/series/u/p/102.mkv');
      expect(s.episodes[2]!.single.title, 'Début');
      expect(s.nextAfter(s1[0])!.id, 'p1:e:102');
      expect(s.nextAfter(s1[1])!.id, 'p1:e:201', reason: 'fin de saison 1 → S2E1');
      expect(s.nextAfter(s.episodes[2]!.single), isNull);
      expect(s.details.durationSec, 52 * 60);
    });

    test('get_series_info : épisodes en liste de listes', () {
      final SeriesDetails s = parseSeriesInfo(
        <String, dynamic>{
          'episodes': <dynamic>[
            <dynamic>[
              <String, dynamic>{'id': '1', 'episode_num': '1', 'season': '1'},
            ],
          ],
        },
        source: _src,
        seriesId: 'p1:s:1',
      );
      expect(s.seasons.single.number, 1);
      expect(s.allInOrder.single.remoteId, '1');
    });
  });

  test('cleanEpisodeTitle', () {
    expect(cleanEpisodeTitle('Breaking Bad - S01E02 - Cat\'s in the Bag', 'Breaking Bad'),
        'Cat\'s in the Bag');
    expect(cleanEpisodeTitle('S03E10', 'X'), '');
  });
}
