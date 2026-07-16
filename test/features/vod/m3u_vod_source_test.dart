// =========================================================
//  m3u_vod_source_test.dart — Verrouille le pont M3U → modèles Cinéma
// =========================================================
//  Contrats critiques :
//    - identifiants STABLES (reprise de lecture, épisode suivant) ;
//    - préfixe « ep- » sur les épisodes (contrat AutoplayPolicy) ;
//    - tri saison/épisode, regroupement par nom de série normalisé.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/vod/data/m3u_vod_source.dart';
import 'package:tv_king/features/vod/domain/vod_movie.dart';
import 'package:tv_king/features/vod/domain/vod_series.dart';

Channel _ch(String id, String name, String url,
        {String category = 'VOD', String? logo}) =>
    Channel(
      id: id,
      playlistId: 1,
      name: name,
      category: category,
      streamUrl: url,
      isLive: false,
      logoUrl: logo,
      catchupSupported: false,
    );

void main() {
  group('m3uSeriesId', () {
    test('normalisation stable (casse, espaces, accents ignorés)', () {
      expect(m3uSeriesId('Breaking Bad'), 'm3useries-breaking-bad');
      expect(m3uSeriesId('breaking   BAD'), 'm3useries-breaking-bad');
      expect(m3uSeriesId('Dark!'), 'm3useries-dark');
    });

    test('nom vide → identifiant de secours (jamais vide)', () {
      expect(m3uSeriesId('***'), 'm3useries-sans-nom');
    });
  });

  group('m3uContainerExt', () {
    test('extension extraite du chemin, query ignorée', () {
      expect(m3uContainerExt('http://h/vod/f.mkv'), 'mkv');
      expect(m3uContainerExt('http://h/vod/f.mp4?tk=1'), 'mp4');
    });

    test('sans extension → repli mp4', () {
      expect(m3uContainerExt('http://h/vod/12345'), 'mp4');
    });
  });

  group('m3uChannelToMovie', () {
    test('mapping complet (id conservé = clé de reprise)', () {
      final VodMovie m = m3uChannelToMovie(_ch(
        'm3u-1-42',
        'Inception',
        'http://h/movie/u/p/42.mkv',
        category: 'FILMS | ACTION',
        logo: 'http://h/poster.jpg',
      ));
      expect(m.id, 'm3u-1-42');
      expect(m.name, 'Inception');
      expect(m.category, 'FILMS | ACTION');
      expect(m.streamUrl, 'http://h/movie/u/p/42.mkv');
      expect(m.containerExt, 'mkv');
      expect(m.posterUrl, 'http://h/poster.jpg');
    });
  });

  group('splitM3uVod', () {
    test('films et épisodes séparés par le classificateur', () {
      final ({List<Channel> movies, List<Channel> episodes}) r = splitM3uVod(
        <Channel>[
          _ch('a', 'Inception', 'http://h/movie/u/p/1.mkv'),
          _ch('b', 'Vikings S01 E01', 'http://h/series/u/p/2.mp4'),
          _ch('c', 'Le Parrain', 'http://h/vod/parrain.mp4'),
        ],
      );
      expect(r.movies.map((Channel c) => c.id), <String>['a', 'c']);
      expect(r.episodes.map((Channel c) => c.id), <String>['b']);
    });
  });

  group('groupM3uEpisodesIntoSeries', () {
    final List<Channel> eps = <Channel>[
      _ch('e1', 'Vikings S01 E02', 'http://h/series/u/p/2.mp4',
          logo: 'http://h/vikings.jpg'),
      _ch('e2', 'Vikings S01 E01', 'http://h/series/u/p/1.mp4'),
      _ch('e3', 'Dark S02 E01', 'http://h/series/u/p/9.mp4'),
      _ch('e4', 'vikings s02e01', 'http://h/series/u/p/3.mp4'),
    ];

    test('regroupe par nom normalisé (casse ignorée)', () {
      final List<VodSeries> series = groupM3uEpisodesIntoSeries(eps);
      expect(series.length, 2);
      expect(series.first.name, 'Vikings');
      expect(series.first.id, 'm3useries-vikings');
      // Poster = celui du premier épisode rencontré.
      expect(series.first.posterUrl, 'http://h/vikings.jpg');
      expect(series.last.name, 'Dark');
    });

    test('m3uEpisodesForSeries : tri saison puis épisode, préfixe ep-', () {
      final List<VodEpisode> out =
          m3uEpisodesForSeries(eps, 'm3useries-vikings');
      expect(out.length, 3);
      expect(out.map((VodEpisode e) => e.tag),
          <String>['S01E01', 'S01E02', 'S02E01']);
      // Contrat AutoplayPolicy : identifiant préfixé « ep- ».
      expect(out.every((VodEpisode e) => e.id.startsWith('ep-')), isTrue);
      expect(out.first.id, 'ep-e2');
    });

    test('série inconnue → liste vide', () {
      expect(m3uEpisodesForSeries(eps, 'm3useries-inconnue'), isEmpty);
    });
  });
}
