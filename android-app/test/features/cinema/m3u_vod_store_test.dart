import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cinema/data/cinema_parsers.dart';
import 'package:tv_king/features/cinema/data/m3u_vod_store.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';

/// Un petit M3U de fournisseur : 2 directs, 3 films dans 2 catégories,
/// 2 séries (dont une en deux saisons, épisodes mélangés), un doublon.
const String kM3u = '''
#EXTM3U
#EXTINF:-1 tvg-logo="http://l/tf1.png" group-title="FR | TNT",TF1 HD
http://h.tv:8080/live/user/pass/101.ts
#EXTINF:-1 tvg-logo="http://l/inception.jpg" group-title="FILMS | SCIENCE-FICTION",Inception (2010)
http://h.tv:8080/movie/user/pass/5001.mkv
#EXTINF:-1 group-title="FILMS | SCIENCE-FICTION",Matrix (1999)
http://h.tv:8080/movie/user/pass/5002.mp4
#EXTINF:-1 group-title="FILMS | COMEDIE",Taxi (1998)
http://h.tv:8080/movie/user/pass/5003.mp4
#EXTINF:-1 group-title="FILMS | COMEDIE",Taxi (1998)
http://h.tv:8080/movie/user/pass/5003.mp4
#EXTINF:-1 tvg-logo="http://l/dark.jpg" group-title="SERIES | NETFLIX",Dark S02E01 Début
http://h.tv:8080/series/user/pass/9201.mkv
#EXTINF:-1 group-title="SERIES | NETFLIX",Dark S01E02 Mensonges
http://h.tv:8080/series/user/pass/9102.mkv
#EXTINF:-1 group-title="SERIES | NETFLIX",Dark S01E01 Secrets
http://h.tv:8080/series/user/pass/9101.mkv
#EXTINF:-1 group-title="SERIES | FR",Lupin S01E01
http://h.tv:8080/series/user/pass/8001.mp4
#EXTINF:-1 group-title="RADIO",Radio Nova
http://h.tv:8080/live/user/pass/700.aac
''';

CinemaSource get source => const CinemaSource(
      allowM3uUrls: true,
      key: 'p1',
      playlistId: 1,
      server: 'http://h.tv:8080',
      username: 'user',
      password: 'pass',
    );

Future<M3uVodStore> build(Directory root, String m3u,
    {int maxMovies = kM3uVodMaxMovies, int maxEpisodes = kM3uVodMaxEpisodes}) async {
  final File file = File('${root.path}/in.m3u')..writeAsStringSync(m3u);
  final M3uVodSummary s = await buildM3uVodStore(M3uVodBuildJob(
    m3uPath: file.path,
    outPath: '${root.path}/store',
    signature: 'sig-1',
    maxMovies: maxMovies,
    maxEpisodes: maxEpisodes,
  ));
  expect(s.error, isNull);
  return M3uVodStore(Directory('${root.path}/store'));
}

dynamic json(Uint8List? b) => decodeJsonBytes(b!);

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('m3u-vod-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('le dossier se lit avec les lecteurs Xtream déjà en place', () async {
    final M3uVodStore store = await build(root, kM3u);

    final List<({String id, String name})> cats =
        parseCategories(json(await store.categories(movies: true)));
    expect(cats.map((c) => c.name), <String>['FILMS | SCIENCE-FICTION', 'FILMS | COMEDIE']);

    final List<CinemaTitle> sf = mapTitles(
      json(await store.titles(movies: true, categoryId: cats.first.id)),
      kind: CinemaKind.movie,
      source: source,
      categoryKeyById: <String, String>{cats.first.id: 'sf'},
    );
    expect(sf.map((t) => t.name), <String>['Inception (2010)', 'Matrix (1999)']);
    expect(sf.first.remoteId, '5001', reason: 'le numéro du fournisseur est gardé');
    expect(sf.first.containerExt, 'mkv');
    expect(sf.first.posterUrl, 'http://l/inception.jpg');
    expect(sf.first.year, '2010');
    expect(sf.first.categoryKey, 'sf');
    expect(sf.first.streamUrl, 'http://h.tv:8080/movie/user/pass/5001.mkv',
        reason: 'l\'adresse vient du M3U lui-même');
    expect(sf.last.addedAt, greaterThan(sf.first.addedAt),
        reason: 'ordre du fichier : le dernier est le plus récent');

    // Le doublon (même film deux fois dans la catégorie) n'apparaît qu'une fois.
    final List<CinemaTitle> comedy = mapTitles(
      json(await store.titles(movies: true, categoryId: cats.last.id)),
      kind: CinemaKind.movie,
      source: source,
      categoryKeyById: <String, String>{cats.last.id: 'co'},
    );
    expect(comedy.map((t) => t.name), <String>['Taxi (1998)']);
  });

  test('séries : catégories, une vignette par série, saisons et épisodes triés', () async {
    final M3uVodStore store = await build(root, kM3u);
    final List<({String id, String name})> cats =
        parseCategories(json(await store.categories(movies: false)));
    expect(cats.map((c) => c.name), <String>['SERIES | NETFLIX', 'SERIES | FR']);

    final List<CinemaTitle> netflix = mapTitles(
      json(await store.titles(movies: false, categoryId: cats.first.id)),
      kind: CinemaKind.series,
      source: source,
      categoryKeyById: <String, String>{cats.first.id: 'nf'},
    );
    expect(netflix, hasLength(1), reason: '3 épisodes = UNE série');
    expect(netflix.single.name, 'Dark');
    expect(netflix.single.posterUrl, 'http://l/dark.jpg');
    expect(netflix.single.streamUrl, isNull);

    final SeriesDetails d = parseSeriesInfo(
      json(await store.seriesInfo(netflix.single.remoteId)),
      source: source,
      seriesId: netflix.single.id,
      seriesName: 'Dark',
    );
    expect(d.seasons.map((s) => s.number), <int>[1, 2]);
    expect(d.episodes[1]!.map((e) => e.number), <int>[1, 2], reason: 'triés malgré le désordre du M3U');
    expect(d.episodes[1]!.first.title, 'Secrets', reason: 'nom de série et code retirés');
    expect(d.episodes[1]!.first.streamUrl, 'http://h.tv:8080/series/user/pass/9101.mkv');
    expect(d.episodes[2]!.single.streamUrl, 'http://h.tv:8080/series/user/pass/9201.mkv');
    expect(d.allInOrder.map((e) => e.remoteId), <String>['9101', '9102', '9201']);
  });

  test('le livre d\'adresses ne contient que les films', () async {
    final M3uVodStore store = await build(root, kM3u);
    final Map<String, String> book = await store.readUrlBook();
    expect(book, <String, String>{
      '5001': 'http://h.tv:8080/movie/user/pass/5001.mkv',
      '5002': 'http://h.tv:8080/movie/user/pass/5002.mp4',
      '5003': 'http://h.tv:8080/movie/user/pass/5003.mp4',
    });
  });

  test('en-tête : version, signature, compteurs', () async {
    final M3uVodStore store = await build(root, kM3u);
    final M3uVodMeta meta = (await store.readMeta())!;
    expect(meta.signature, 'sig-1');
    expect((meta.movies, meta.series, meta.episodes), (3, 2, 4));
    expect(meta.truncated, isFalse);
    expect(meta.age(DateTime.now()).inMinutes, lessThan(2));
  });

  test('M3U sans film ni série : dossier valide, catégories vides', () async {
    final M3uVodStore store = await build(root, '#EXTM3U\n#EXTINF:-1,TF1\nhttp://h/live/u/p/1.ts\n');
    expect(parseCategories(json(await store.categories(movies: true))), isEmpty);
    expect(parseCategories(json(await store.categories(movies: false))), isEmpty);
    final M3uVodMeta meta = (await store.readMeta())!;
    expect((meta.movies, meta.episodes), (0, 0));
  });

  test('adresses directes (hors Xtream) : identifiant par empreinte, adresse intacte', () async {
    final M3uVodStore store = await build(root, '''
#EXTINF:-1 group-title="Mes films",Le Grand Bleu
https://cdn.site/films/Le Grand Bleu.mp4?token=abc
''');
    final List<({String id, String name})> cats =
        parseCategories(json(await store.categories(movies: true)));
    final List<CinemaTitle> titles = mapTitles(
      json(await store.titles(movies: true, categoryId: cats.single.id)),
      kind: CinemaKind.movie,
      source: source,
      categoryKeyById: <String, String>{cats.single.id: 'x'},
    );
    expect(titles.single.remoteId, startsWith('h'));
    expect(titles.single.streamUrl, 'https://cdn.site/films/Le Grand Bleu.mp4?token=abc');
    expect(m3uVodIsOwnId(titles.single.remoteId), isTrue);
    expect(m3uVodIsOwnId('5001'), isFalse);
    expect((await store.readUrlBook())[titles.single.remoteId], titles.single.streamUrl);
  });

  test('plafonds : le début du M3U est gardé, la coupure est signalée', () async {
    final StringBuffer many = StringBuffer('#EXTM3U\n');
    for (int i = 1; i <= 30; i++) {
      many.write('#EXTINF:-1 group-title="Films",Film $i\nhttp://h/movie/u/p/$i.mp4\n');
    }
    final M3uVodStore store = await build(root, many.toString(), maxMovies: 10, maxEpisodes: 0);
    final M3uVodMeta meta = (await store.readMeta())!;
    expect(meta.movies, 10);
    expect(meta.truncated, isTrue);
  });

  test('identifiants de catégorie suspects refusés (pas de chemin « ../ »)', () async {
    final M3uVodStore store = await build(root, kM3u);
    expect(await store.titles(movies: true, categoryId: '../meta'), isNull);
    expect(await store.titles(movies: true, categoryId: 'mg999'), isNull);
    expect(await store.seriesInfo('../x'), isNull);
    expect(await store.seriesInfo('qinconnu'), isNull);
  });

  test('un M3U illisible ne laisse pas de dossier à moitié écrit', () async {
    final M3uVodSummary s = await buildM3uVodStore(M3uVodBuildJob(
      m3uPath: '${root.path}/absent.m3u',
      outPath: '${root.path}/store',
      signature: 's',
    ));
    expect(s.error, isNotNull);
    expect(Directory('${root.path}/store').existsSync(), isFalse);
    expect(Directory('${root.path}/store.tmp').existsSync(), isFalse);
  });

  test('une reconstruction remplace l\'ancien dossier d\'un coup', () async {
    await build(root, kM3u);
    final M3uVodStore again = await build(root, '#EXTINF:-1 group-title="Neuf",Nouveau\nhttp://h/movie/u/p/1.mp4\n');
    final List<({String id, String name})> cats =
        parseCategories(json(await again.categories(movies: true)));
    expect(cats.map((c) => c.name), <String>['Neuf']);
    expect(utf8.decode((await again.categories(movies: false))!), '[]');
  });
}
