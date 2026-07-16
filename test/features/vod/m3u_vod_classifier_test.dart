// =========================================================
//  m3u_vod_classifier_test.dart — Verrouille la classification VOD des M3U
// =========================================================
//  RÈGLE D'OR testée partout : en cas de doute → LIVE. Un live classé film
//  perdrait Guide/REC/zapping ; un film classé live reste simplement là où
//  il était avant (aucune régression) — l'erreur n'est pas symétrique.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/vod/domain/m3u_vod_classifier.dart';

void main() {
  group('M3uVodClassifier.classify — chemins Xtream', () {
    test('/movie/ → film', () {
      expect(
        M3uVodClassifier.classify(
          url: 'http://host:80/movie/user/pass/12345.mkv',
          name: 'Inception',
        ),
        M3uVodKind.movie,
      );
    });

    test('/movies/ (variante) → film', () {
      expect(
        M3uVodClassifier.classify(
          url: 'http://host/movies/user/pass/1.mp4',
          name: 'Le Parrain',
        ),
        M3uVodKind.movie,
      );
    });

    test('/series/ → épisode même sans numérotation dans le nom', () {
      expect(
        M3uVodClassifier.classify(
          url: 'http://host/series/user/pass/998.mp4',
          name: 'Pilot',
        ),
        M3uVodKind.episode,
      );
    });

    test('/movie/ MAIS nom SxxExx → épisode (le nom départage)', () {
      expect(
        M3uVodClassifier.classify(
          url: 'http://host/movie/user/pass/7.mkv',
          name: 'Vikings S02 E05',
        ),
        M3uVodKind.episode,
      );
    });
  });

  group('M3uVodClassifier.classify — extensions de fichier', () {
    test('.mp4 sans numérotation → film', () {
      expect(
        M3uVodClassifier.classify(
          url: 'http://cdn.example.com/vod/inception.mp4',
          name: 'Inception (2010)',
        ),
        M3uVodKind.movie,
      );
    });

    test('.mkv avec « S01E02 » collé → épisode', () {
      expect(
        M3uVodClassifier.classify(
          url: 'http://cdn/x/breaking.bad.mkv',
          name: 'Breaking Bad S01E02',
        ),
        M3uVodKind.episode,
      );
    });

    test('extension dans la QUERY seulement → live (pas un fichier)', () {
      expect(
        M3uVodClassifier.classify(
          url: 'http://host/stream?file=x.mp4',
          name: 'Chaîne 4',
        ),
        M3uVodKind.live,
      );
    });

    test('.mp4 suivi d\'une query string → film quand même', () {
      expect(
        M3uVodClassifier.classify(
          url: 'http://cdn/vod/film.mp4?token=abc',
          name: 'Film',
        ),
        M3uVodKind.movie,
      );
    });
  });

  group('M3uVodClassifier.classify — tout le reste = LIVE', () {
    for (final (String url, String name) in <(String, String)>[
      ('http://host:8080/live/user/pass/55.ts', 'TF1 HD'),
      ('http://host/user/pass/55', 'Canal+ (URL Xtream sans extension)'),
      ('http://host/playlist/master.m3u8', 'beIN 1'),
      ('udp://239.0.0.1:1234', 'Multicast'),
      ('rtsp://cam.local/stream', 'Caméra'),
      // Nom trompeur : un GROUUPE « FILMS » peut contenir du live cinéma.
      ('http://host/live/u/p/9.ts', 'FILMS: Action 24/7 S01E02'),
    ]) {
      test('$name → live', () {
        expect(
          M3uVodClassifier.classify(url: url, name: name),
          M3uVodKind.live,
        );
      });
    }
  });

  group('M3uVodClassifier.episodeTag — extraction SxxExx', () {
    test('« Vikings S02 E05 » → série/saison/épisode', () {
      final M3uEpisodeTag? tag =
          M3uVodClassifier.episodeTag('Vikings S02 E05');
      expect(tag, isNotNull);
      expect(tag!.seriesName, 'Vikings');
      expect(tag.season, 2);
      expect(tag.episode, 5);
    });

    test('séparateurs variés : « Dark - S1.E10 »', () {
      final M3uEpisodeTag? tag =
          M3uVodClassifier.episodeTag('Dark - S1.E10');
      expect(tag, isNotNull);
      expect(tag!.seriesName, 'Dark');
      expect(tag.season, 1);
      expect(tag.episode, 10);
    });

    test('format « 1x03 »', () {
      final M3uEpisodeTag? tag =
          M3uVodClassifier.episodeTag('Friends 1x03');
      expect(tag, isNotNull);
      expect(tag!.seriesName, 'Friends');
      expect(tag.season, 1);
      expect(tag.episode, 3);
    });

    test('insensible à la casse : « s03e12 »', () {
      final M3uEpisodeTag? tag =
          M3uVodClassifier.episodeTag('the office s03e12');
      expect(tag, isNotNull);
      expect(tag!.season, 3);
      expect(tag.episode, 12);
    });

    test('numérotation en TÊTE (« S01E02 - Pilot ») → nom de repli non vide',
        () {
      final M3uEpisodeTag? tag =
          M3uVodClassifier.episodeTag('S01E02 - Pilot');
      expect(tag, isNotNull);
      expect(tag!.seriesName.isNotEmpty, isTrue);
      expect(tag.season, 1);
      expect(tag.episode, 2);
    });

    test('sans numérotation → null', () {
      expect(M3uVodClassifier.episodeTag('Inception (2010)'), isNull);
      // « x » dans un mot ne doit pas matcher (pas de faux 1x03).
      expect(M3uVodClassifier.episodeTag('Extra Large'), isNull);
    });
  });
}
