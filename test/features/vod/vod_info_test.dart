// =========================================================
//  vod_info_test.dart — Parsing DÉFENSIF de la fiche film (get_vod_info)
// =========================================================
//  Le protocole Xtream n'est pas normalisé : chaque panel renvoie son
//  propre schéma (types variables, champs manquants, listes vs chaînes).
//  Ces tests verrouillent la promesse de VodInfo.fromJson : QUOI QU'IL
//  ARRIVE, jamais de crash — un champ illisible devient simplement null.
//  Les fonctions de parsing sont PURES → aucun réseau, aucun mock.
// =========================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/vod/domain/vod_info.dart';

void main() {
  group('VodInfo.fromJson — payload standard (sous-objet info)', () {
    test('payload complet : tous les champs sont extraits', () {
      final VodInfo info = VodInfo.fromJson(<String, dynamic>{
        'info': <String, dynamic>{
          'plot': 'Un tueur à gages sort de sa retraite.',
          'cast': 'Keanu Reeves, Halle Berry',
          'director': 'Chad Stahelski',
          'genre': 'Action, Thriller',
          'releasedate': '2019-05-14',
          'duration_secs': 6453,
          'duration': '01:47:33',
          'backdrop_path': <String>['http://img.example/backdrop.jpg'],
          'tmdb_id': 458156,
          'youtube_trailer': 'M7XM597XO94',
          'rating': 7.4,
        },
        'movie_data': <String, dynamic>{'stream_id': 12345},
      });

      expect(info.plot, 'Un tueur à gages sort de sa retraite.');
      expect(info.cast, 'Keanu Reeves, Halle Berry');
      expect(info.director, 'Chad Stahelski');
      expect(info.genre, 'Action, Thriller');
      expect(info.releaseDate, '2019-05-14');
      expect(info.year, '2019');
      expect(info.durationSecs, 6453);
      expect(info.backdropUrl, 'http://img.example/backdrop.jpg');
      expect(info.tmdbId, '458156');
      expect(info.youtubeTrailer, 'M7XM597XO94');
      expect(info.rating, '7.4');
    });

    test('payload partiel : les champs absents deviennent null, sans crash',
        () {
      final VodInfo info = VodInfo.fromJson(<String, dynamic>{
        'info': <String, dynamic>{'plot': 'Juste un synopsis.'},
      });
      expect(info.plot, 'Juste un synopsis.');
      expect(info.cast, isNull);
      expect(info.director, isNull);
      expect(info.genre, isNull);
      expect(info.releaseDate, isNull);
      expect(info.year, isNull);
      expect(info.durationSecs, isNull);
      expect(info.backdropUrl, isNull);
      expect(info.tmdbId, isNull);
      expect(info.youtubeTrailer, isNull);
      expect(info.rating, isNull);
    });

    test('payload vide / info non-Map (liste vide renvoyée par le serveur)',
        () {
      // Certains panels renvoient `info: []` quand le film n'existe pas.
      expect(VodInfo.fromJson(<String, dynamic>{}).plot, isNull);
      final VodInfo info =
          VodInfo.fromJson(<String, dynamic>{'info': <dynamic>[]});
      expect(info.plot, isNull);
      expect(info.durationSecs, isNull);
    });

    test('champs à la RACINE (serveurs qui ne mettent pas de sous-objet)',
        () {
      final VodInfo info = VodInfo.fromJson(<String, dynamic>{
        'plot': 'Synopsis à plat.',
        'cast': 'Acteur Un',
        'backdrop_path': 'http://img.example/flat.jpg',
      });
      expect(info.plot, 'Synopsis à plat.');
      expect(info.cast, 'Acteur Un');
      expect(info.backdropUrl, 'http://img.example/flat.jpg');
    });

    test('repli racine quand `info` existe mais est incomplet', () {
      final VodInfo info = VodInfo.fromJson(<String, dynamic>{
        'info': <String, dynamic>{'plot': 'Dans info.'},
        'genre': 'Comédie', // à la racine seulement
      });
      expect(info.plot, 'Dans info.');
      expect(info.genre, 'Comédie');
    });
  });

  group('VodInfo.fromJson — backdrop_path liste vs string', () {
    test('liste d\'URLs → première URL non vide', () {
      final VodInfo info = VodInfo.fromJson(<String, dynamic>{
        'info': <String, dynamic>{
          'backdrop_path': <dynamic>['', 'http://img.example/a.jpg', 'x'],
        },
      });
      expect(info.backdropUrl, 'http://img.example/a.jpg');
    });

    test('string simple → telle quelle', () {
      final VodInfo info = VodInfo.fromJson(<String, dynamic>{
        'info': <String, dynamic>{
          'backdrop_path': 'http://img.example/b.jpg',
        },
      });
      expect(info.backdropUrl, 'http://img.example/b.jpg');
    });

    test('liste vide, liste de nulls, type farfelu → null', () {
      expect(VodInfo.parseBackdrop(<dynamic>[]), isNull);
      expect(VodInfo.parseBackdrop(<dynamic>[null, '']), isNull);
      expect(VodInfo.parseBackdrop(42), '42'); // toString tolérant
      expect(VodInfo.parseBackdrop(null), isNull);
    });
  });

  group('VodInfo.fromJson — champs mal typés (jamais de crash)', () {
    test('nombres en String, note en int, cast en int', () {
      final VodInfo info = VodInfo.fromJson(<String, dynamic>{
        'info': <String, dynamic>{
          'duration_secs': '6453', // String au lieu d'int
          'rating': 8, // int au lieu de String
          'cast': 12345, // n'importe quoi → toString
          'tmdb_id': 'tt0133093',
        },
      });
      expect(info.durationSecs, 6453);
      expect(info.rating, '8');
      expect(info.cast, '12345');
      expect(info.tmdbId, 'tt0133093');
    });

    test('valeurs creuses : "", "null", rating "0" → null', () {
      final VodInfo info = VodInfo.fromJson(<String, dynamic>{
        'info': <String, dynamic>{
          'plot': '',
          'director': 'null',
          'rating': '0',
          'backdrop_path': '',
        },
      });
      expect(info.plot, isNull);
      expect(info.director, isNull);
      expect(info.rating, isNull);
      expect(info.backdropUrl, isNull);
    });

    test('duration_secs illisible et pas de duration → null', () {
      final VodInfo info = VodInfo.fromJson(<String, dynamic>{
        'info': <String, dynamic>{'duration_secs': 'abc'},
      });
      expect(info.durationSecs, isNull);
    });
  });

  group('parseDurationSecs — « 01:47:33 » vs secondes', () {
    test('duration_secs prioritaire (int et String)', () {
      expect(VodInfo.parseDurationSecs(6453, null), 6453);
      expect(VodInfo.parseDurationSecs('6453', null), 6453);
      // duration_secs gagne même si duration est aussi présent.
      expect(VodInfo.parseDurationSecs(100, '01:47:33'), 100);
    });

    test('repli horloge HH:MM:SS et MM:SS', () {
      expect(VodInfo.parseDurationSecs(null, '01:47:33'), 6453);
      expect(VodInfo.parseDurationSecs(null, '47:33'), 2853);
      expect(VodInfo.parseDurationSecs('abc', '00:30:00'), 1800);
    });

    test('valeurs inexploitables → null', () {
      expect(VodInfo.parseDurationSecs(null, null), isNull);
      expect(VodInfo.parseDurationSecs(0, '0'), isNull); // 0 = inconnu
      expect(VodInfo.parseDurationSecs(-5, null), isNull);
      expect(VodInfo.parseDurationSecs(null, '107 min'), isNull);
      expect(VodInfo.parseDurationSecs(null, '1:2:3:4'), isNull);
      expect(VodInfo.parseDurationSecs(null, 'xx:yy'), isNull);
      expect(VodInfo.parseDurationSecs(null, '00:00'), isNull); // durée nulle
    });
  });

  group('year — extraction depuis releaseDate', () {
    test('formats variés', () {
      expect(const VodInfo(releaseDate: '2019-05-14').year, '2019');
      expect(const VodInfo(releaseDate: '2019').year, '2019');
      expect(const VodInfo(releaseDate: '14/05/2019').year, '2019');
      expect(const VodInfo(releaseDate: 'n/a').year, isNull);
      expect(const VodInfo().year, isNull);
    });
  });

  group('formats d\'affichage (fiche 10-foot)', () {
    test('formatDurationShort : « 1 h 47 min » / « 47 min »', () {
      expect(VodInfo.formatDurationShort(6453), '1 h 47 min');
      expect(VodInfo.formatDurationShort(2853), '47 min');
      expect(VodInfo.formatDurationShort(59), '0 min');
    });

    test('formatClock : « 42:15 » / « 1:02:03 » (bouton Reprendre à …)', () {
      expect(VodInfo.formatClock(const Duration(minutes: 42, seconds: 15)),
          '42:15');
      expect(
          VodInfo.formatClock(
              const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
      expect(VodInfo.formatClock(const Duration(seconds: -4)), '0:00');
    });
  });
}
