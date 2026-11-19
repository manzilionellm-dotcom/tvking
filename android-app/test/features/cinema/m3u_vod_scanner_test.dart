import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cinema/data/m3u_vod_scanner.dart';
import 'package:tv_king/features/cinema/domain/m3u_vod_classifier.dart';

List<M3uVodEntry> scan(String m3u) {
  final List<M3uVodEntry> out = <M3uVodEntry>[];
  final M3uVodScanner scanner = M3uVodScanner(onEntry: out.add);
  for (final String line in m3u.split('\n')) {
    scanner.feed(line);
  }
  return out;
}

void main() {
  group('M3uVodClassifier : film, épisode ou direct', () {
    M3uVodKind? kind(String url, {String name = 'X', String group = ''}) =>
        M3uVodClassifier.classify(name: name, group: group, url: url);

    test('adresses de type Xtream : /movie/ film, /series/ épisode', () {
      expect(kind('http://h.tv:8080/movie/u/p/123.mkv'), M3uVodKind.movie);
      expect(kind('http://h.tv:8080/series/u/p/456.mp4'), M3uVodKind.episode);
      // Un film en .m3u8 (HLS) sous /movie/ reste un film.
      expect(kind('http://h.tv/movie/u/p/9.m3u8'), M3uVodKind.movie);
    });

    test('directs : /live/, sans extension, .ts, .m3u8, rtmp', () {
      expect(kind('http://h.tv:8080/live/u/p/7.ts'), isNull);
      expect(kind('http://h.tv:8080/u/p/12345'), isNull);
      expect(kind('http://h.tv/hls/tf1.m3u8'), isNull);
      expect(kind('http://h.tv/stream.php?id=4'), isNull);
      expect(kind('rtmp://h.tv/live/x.mp4'), isNull);
      // Une chaîne « Films 24/7 » n'est pas un film.
      expect(kind('http://h.tv/films247.m3u8', group: 'FILMS', name: 'Cinéma 24/7'), isNull);
    });

    test('fichier vidéo direct : film, ou épisode si le nom a un code', () {
      expect(kind('https://cdn.site/films/Matrix.mp4'), M3uVodKind.movie);
      expect(kind('https://cdn.site/x/Dark.S02E05.mkv', name: 'Dark S02E05'), M3uVodKind.episode);
      expect(kind('https://cdn.site/x/a.mkv?token=abc'), M3uVodKind.movie);
    });

    test('extension et chemin ignorent la requête et le serveur', () {
      expect(M3uVodClassifier.extensionOf('http://h/a/b.MKV?x=1#y'), 'mkv');
      expect(M3uVodClassifier.extensionOf('http://h/a/b'), '');
      expect(M3uVodClassifier.extensionOf('http://h/a/b.'), '');
      expect(M3uVodClassifier.pathOf('http://h:80/a b/é.mp4?x=1'), '/a b/é.mp4');
    });

    test('codes saison / épisode : S01E02, 1x02, Saison 1 Épisode 2', () {
      M3uEpisodeName? p(String n) => M3uVodClassifier.parseEpisode(n);
      final M3uEpisodeName a = p("Breaking Bad S01E02 Cat's in the Bag")!;
      expect((a.series, a.season, a.episode, a.title), ('Breaking Bad', 1, 2, "Cat's in the Bag"));
      final M3uEpisodeName b = p('FR - Dark - S02 E05')!;
      expect((b.series, b.season, b.episode), ('FR - Dark', 2, 5));
      final M3uEpisodeName c = p('The Office 3x12')!;
      expect((c.series, c.season, c.episode), ('The Office', 3, 12));
      final M3uEpisodeName d = p('Lupin Saison 2 Épisode 7')!;
      expect((d.series, d.season, d.episode), ('Lupin', 2, 7));
      final M3uEpisodeName e = p('Money Heist (2017) s05.e10 - Fin')!;
      expect((e.series, e.season, e.episode, e.title), ('Money Heist (2017)', 5, 10, 'Fin'));
      // Pas de code, ou rien devant le code : ce n'est pas un épisode.
      expect(p('Matrix Reloaded'), isNull);
      expect(p('S01E01'), isNull);
      // Une résolution n'est pas une saison.
      expect(p('Film 1920x1080'), isNull);
    });

    test('nom lisible tiré de l\'adresse', () {
      expect(M3uVodClassifier.nameFromUrl('http://h/a/Mon%20Film_2020.mkv'), 'Mon Film 2020');
    });
  });

  group('M3uVodScanner : lit un M3U de fournisseur', () {
    const String provider = '''
#EXTM3U
#EXTINF:-1 tvg-id="tf1.fr" tvg-name="TF1" tvg-logo="http://l/tf1.png" group-title="FR | TNT",TF1 HD
http://h.tv:8080/live/user/pass/101.ts
#EXTINF:-1 tvg-id="" tvg-name="Inception (2010)" tvg-logo="http://l/inception.jpg" group-title="FILMS | SCIENCE-FICTION",Inception (2010)
http://h.tv:8080/movie/user/pass/5001.mkv
#EXTINF:-1 tvg-logo="" group-title="SERIES | NETFLIX",Dark S01E01 Secrets
http://h.tv:8080/series/user/pass/9001.mp4
#EXTINF:-1 group-title="SERIES | NETFLIX",Dark S01E02 Mensonges
http://h.tv:8080/series/user/pass/9002.mp4
#EXTINF:-1 group-title="RADIO",Radio Nova
http://h.tv:8080/live/user/pass/700.aac
''';

    test('garde 1 film et 2 épisodes, oublie les directs', () {
      final List<M3uVodEntry> got = scan(provider);
      expect(got, hasLength(3));
      final M3uVodEntry film = got[0];
      expect(film.kind, M3uVodKind.movie);
      expect(film.name, 'Inception (2010)');
      expect(film.category, 'FILMS | SCIENCE-FICTION');
      expect(film.url, 'http://h.tv:8080/movie/user/pass/5001.mkv');
      expect(film.ext, 'mkv');
      expect(film.logo, 'http://l/inception.jpg');
      final M3uVodEntry ep = got[1];
      expect(ep.kind, M3uVodKind.episode);
      expect((ep.series, ep.season, ep.episode), ('Dark', 1, 1));
      expect(ep.category, 'SERIES | NETFLIX');
      expect(ep.logo, isNull, reason: 'tvg-logo vide : pas d\'affiche');
      expect((got[2].series, got[2].episode), ('Dark', 2));
    });

    test('statistiques : lignes, adresses, films, épisodes', () {
      final M3uVodScanner s = M3uVodScanner(onEntry: (_) {});
      for (final String l in provider.split('\n')) {
        s.feed(l);
      }
      expect((s.urls, s.movies, s.episodes), (5, 1, 2));
    });

    test('virgule dans le nom, apostrophe dans la catégorie, attribut sans guillemets', () {
      final List<M3uVodEntry> got = scan('''
#EXTINF:-1 group-title="Films d'action" tvg-logo=http://l/a.jpg,Fast, Furious & Co (2009)
http://h/movie/u/p/1.mp4
''');
      expect(got, hasLength(1));
      expect(got.single.name, 'Fast, Furious & Co (2009)');
      expect(got.single.category, "Films d'action");
      expect(got.single.logo, 'http://l/a.jpg');
    });

    test('catégorie sur une ligne #EXTGRP, valable pour la seule entrée suivante', () {
      final List<M3uVodEntry> got = scan('''
#EXTGRP:Comédies
#EXTINF:-1,Les Visiteurs
http://h/movie/u/p/1.mp4
#EXTINF:-1,Taxi
http://h/movie/u/p/2.mp4
''');
      expect(got.map((M3uVodEntry e) => e.category), <String>['Comédies', '']);
    });

    test('adresse sans #EXTINF : le nom vient du fichier', () {
      final List<M3uVodEntry> got = scan('''
https://cdn.site/films/Le_Grand_Bleu.mp4
https://cdn.site/live/chaine
''');
      expect(got, hasLength(1));
      expect(got.single.name, 'Le Grand Bleu');
      expect(got.single.ext, 'mp4');
    });

    test('BOM, lignes vides, balises inconnues, nom vide : aucun plantage', () {
      final List<M3uVodEntry> got = scan('﻿#EXTM3U\n\n#EXTVLCOPT:http-user-agent=x\n'
          '#EXTINF:-1 tvg-name="Alien (1979)" group-title="Films",\n'
          'http://h/movie/u/p/3.avi\n#EXT-X-FOO\n#EXTINF:-1,orphelin\n');
      expect(got, hasLength(1));
      expect(got.single.name, 'Alien (1979)', reason: 'nom vide : tvg-name');
      expect(got.single.ext, 'avi');
    });

    test('épisode /series/ sans code dans le nom : saison 1, numéro 0', () {
      final List<M3uVodEntry> got = scan('''
#EXTINF:-1 group-title="Séries",Le Bureau des Légendes
http://h/series/u/p/77.mkv
''');
      final M3uVodEntry e = got.single;
      expect(e.kind, M3uVodKind.episode);
      expect((e.series, e.season, e.episode), ('Le Bureau des Légendes', 1, 0));
    });
  });
}
