// =========================================================
//  vod_catalog_cache_test.dart — Cache disque du catalogue (façon Netflix)
// =========================================================
//  Le contrat du cache : ce qu'on écrit se relit À L'IDENTIQUE (films et
//  séries), une version inconnue est ignorée (liste vide, jamais de crash),
//  et les champs optionnels absents survivent au cycle.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/vod/data/series_repository.dart';
import 'package:tv_king/features/vod/data/vod_repository.dart';
import 'package:tv_king/features/vod/domain/vod_movie.dart';
import 'package:tv_king/features/vod/domain/vod_series.dart';

void main() {
  group('cache catalogue FILMS', () {
    test('aller-retour identique (10 000 films, champs optionnels mixtes)',
        () {
      final List<VodMovie> movies = List<VodMovie>.generate(
        10000,
        (int i) => VodMovie(
          id: 'vod-$i',
          name: 'Film $i',
          category: 'Cat ${i % 12}',
          streamUrl: 'http://p.example/movie/u/p/$i.mkv',
          containerExt: 'mkv',
          posterUrl: i.isEven ? 'http://p.example/img/$i.jpg' : null,
          rating: i % 3 == 0 ? '7.$i' : null,
          year: i % 5 == 0 ? '20${10 + i % 15}' : null,
        ),
      );
      final String raw = encodeVodCatalog(movies);
      final List<VodMovie> back = decodeVodCatalog(raw);
      expect(back.length, movies.length);
      expect(back.first.id, movies.first.id);
      expect(back.last.streamUrl, movies.last.streamUrl);
      expect(back[2].posterUrl, movies[2].posterUrl);
      expect(back[1].posterUrl, isNull);
      expect(back[3].rating, movies[3].rating);
    });

    test('version inconnue → liste vide (pas de crash)', () {
      expect(decodeVodCatalog('{"v":99,"m":[]}'), isEmpty);
    });
  });

  group('cache catalogue SÉRIES', () {
    test('aller-retour identique', () {
      final List<VodSeries> series = List<VodSeries>.generate(
        500,
        (int i) => VodSeries(
          id: '$i',
          name: 'Série $i',
          category: 'Cat ${i % 6}',
          posterUrl: i.isEven ? 'http://p.example/s/$i.jpg' : null,
          plot: i % 3 == 0 ? 'Résumé $i' : null,
          rating: null,
          year: '2024',
        ),
      );
      final String raw = encodeSeriesCatalog(series);
      final List<VodSeries> back = decodeSeriesCatalog(raw);
      expect(back.length, series.length);
      expect(back.first.name, 'Série 0');
      expect(back[3].plot, 'Résumé 3');
      expect(back[1].posterUrl, isNull);
    });

    test('version inconnue → liste vide (pas de crash)', () {
      expect(decodeSeriesCatalog('{"v":0,"s":[]}'), isEmpty);
    });
  });
}
