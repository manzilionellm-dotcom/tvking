// Une liste attribuée à un profil ne doit jamais réapparaître dans un autre
// par le cache mémoire, le disque, ni une réponse HTTP arrivée en retard.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/vod/data/vod_repository.dart';

class _ScopePaths extends PathProviderPlatform {
  _ScopePaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

http.Response _catalog(http.Request request) {
  final String source = request.url.host == 'a.example.test' ? 'A' : 'B';
  final String? action = request.url.queryParameters['action'];
  final Object body;
  if (action == 'get_vod_categories' || action == 'get_series_categories') {
    // Même catégorie dans les deux sources : une fuite du cache ne peut pas
    // être masquée par des clés de catégories différentes.
    body = <Object>[
      <String, String>{'category_id': '10', 'category_name': 'Action'},
    ];
  } else if (action == 'get_vod_info' || action == 'get_series_info') {
    body = <String, Object>{
      'info': <String, Object>{'plot': 'Résumé privé $source'},
      'seasons': <Object>[],
      'episodes': <String, Object>{},
    };
  } else {
    body = <Object>[
      <String, Object>{
        'stream_id': 101,
        'series_id': 201,
        'name': 'Titre $source',
        'category_id': '10',
        'container_extension': 'mp4',
      },
    ];
  }
  return http.Response(jsonEncode(body), 200,
      headers: <String, String>{'content-type': 'application/json'});
}

CinemaTitle _title(int playlist, CinemaKind kind, {String remoteId = '101'}) =>
    CinemaTitle(
      id: 'p$playlist:${kind == CinemaKind.movie ? 'm' : 's'}:$remoteId',
      kind: kind,
      sourceKey: 'p$playlist',
      remoteId: remoteId,
      name: 'Titre privé',
      categoryKey: 'action',
      searchKey: 'titre prive',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  final CinemaRepository cinema = CinemaRepository.instance;
  final ActiveProfile profile = ActiveProfile.instance;
  late Directory root;
  late Database db;
  late int a;
  late int b;
  int scenario = 0;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('zuno-profile-catalog-');
    PathProviderPlatform.instance = _ScopePaths(root.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${root.path}/lists.db';
    db = await PlaylistDatabase.instance.database;
  });

  setUp(() async {
    profile.set('scope-test-${++scenario}', playlistIds: <int>[]);
    cinema.clear();
    final Directory catalog = Directory('${root.path}/zuno_catalog');
    if (await catalog.exists()) await catalog.delete(recursive: true);
    await db.delete('playlists');
    Future<int> insert(String name) => db.insert(
          'playlists',
          Playlist(
            id: null,
            name: name,
            type: PlaylistType.xtream,
            xtreamServer: 'http://${name.toLowerCase()}.example.test',
            xtreamUsername: 'fixture',
            xtreamPassword: 'fixture',
            createdAt: scenario,
          ).toMap(),
        );
    a = await insert('A');
    b = await insert('B');
    CinemaRepository.httpForTesting = () => MockClient((request) async => _catalog(request));
  });

  tearDown(() {
    profile.set('scope-finished-$scenario', playlistIds: <int>[]);
    cinema.clear();
    CinemaRepository.httpForTesting = null;
  });

  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
  });

  test('le même profil réaffecté de A à B oublie les catégories et titres A',
      () async {
    profile.set('same-viewer', playlistIds: <int>[a]);
    expect((await cinema.sources()).map((s) => s.playlistId), <int>[a]);
    expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
    final CinemaCategory categoryA =
        (await cinema.categories(CinemaKind.movie)).single;
    expect((await cinema.titles(CinemaKind.movie, categoryA)).single.name,
        'Titre A');

    profile.set('same-viewer', playlistIds: <int>[b]);
    expect((await cinema.sources()).map((s) => s.playlistId), <int>[b]);
    expect(cinema.sourceByKey('p$a'), isNull);
    expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
    final CinemaCategory categoryB =
        (await cinema.categories(CinemaKind.movie)).single;
    expect(categoryB.parts.map((part) => part.sourceKey), <String>['p$b']);
    expect((await cinema.titles(CinemaKind.movie, categoryB)).single.name,
        'Titre B');
  });

  test('null conserve les listes historiques, [] reste vide malgré le disque A',
      () async {
    profile.set('legacy-viewer');
    expect((await cinema.sources()).map((s) => s.playlistId),
        unorderedEquals(<int>[a, b]));
    profile.set('viewer-a', playlistIds: <int>[a]);
    expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
    expect((await cinema.cachedVodMovies()).single.name, 'Titre A');

    profile.set('empty-viewer', playlistIds: <int>[]);
    expect(await cinema.sources(), isEmpty);
    expect(await cinema.categories(CinemaKind.movie), isEmpty);
    expect(await cinema.cachedVodMovies(), isEmpty);
    expect(await cinema.refreshNow(CinemaKind.movie), isFalse);

    // B n'a aucun catalogue publié. Celui de A existe encore sur le disque,
    // mais il ne constitue jamais un repli autorisé pour B.
    profile.set('viewer-b', playlistIds: <int>[b]);
    expect(await cinema.cachedVodMovies(), isEmpty);
    profile.set('viewer-a', playlistIds: <int>[a]);
    expect((await cinema.cachedVodMovies()).single.name, 'Titre A');
  });

  test('les catégories A tardives ne sont ni renvoyées ni mémorisées pour B',
      () async {
    final Completer<void> entered = Completer<void>();
    final Completer<void> release = Completer<void>();
    CinemaRepository.httpForTesting = () => MockClient((request) async {
          if (request.url.host == 'a.example.test' &&
              request.url.queryParameters['action'] == 'get_vod_categories') {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          return _catalog(request);
        });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    profile.set('viewer-a', playlistIds: <int>[a]);
    final Future<List<CinemaCategory>> pending =
        cinema.categories(CinemaKind.movie);
    await entered.future.timeout(const Duration(seconds: 5));
    profile.set('viewer-b', playlistIds: <int>[b]);
    await cinema.sources();
    release.complete();
    expect(await pending, isEmpty);
    expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
    final CinemaCategory current =
        (await cinema.categories(CinemaKind.movie)).single;
    expect(current.parts.map((part) => part.sourceKey), <String>['p$b']);
    expect((await cinema.titles(CinemaKind.movie, current)).single.name,
        'Titre B');
  });

  test('une page de titres A en vol ne pollue pas la catégorie homonyme B',
      () async {
    final Completer<void> entered = Completer<void>();
    final Completer<void> release = Completer<void>();
    CinemaRepository.httpForTesting = () => MockClient((request) async {
          if (request.url.host == 'a.example.test' &&
              request.url.queryParameters['action'] == 'get_vod_streams') {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          return _catalog(request);
        });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    profile.set('viewer-a', playlistIds: <int>[a]);
    await cinema.sources();
    final CinemaCategory oldCategory = CinemaCategory(
      key: 'action',
      name: 'Action',
      parts: <CategoryRef>[CategoryRef('p$a', '10')],
    );
    final Future<CinemaTitleLoad> pending =
        cinema.loadTitles(CinemaKind.movie, oldCategory, forceNetwork: true);
    await entered.future.timeout(const Duration(seconds: 5));
    profile.set('viewer-b', playlistIds: <int>[b]);
    await cinema.sources();
    release.complete();
    expect((await pending).titles, isEmpty);
    expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
    final CinemaCategory current =
        (await cinema.categories(CinemaKind.movie)).single;
    expect(
        (await cinema.loadTitles(CinemaKind.movie, current)).titles.single.name,
        'Titre B');
  });

  test(
      'fiches films/séries anciennes ou tardives sont exclues après le changement',
      () async {
    final Completer<void> movieEntered = Completer<void>();
    final Completer<void> seriesEntered = Completer<void>();
    final Completer<void> release = Completer<void>();
    bool holdDetails = false;
    CinemaRepository.httpForTesting = () => MockClient((request) async {
          final String? action = request.url.queryParameters['action'];
          if (holdDetails && request.url.host == 'a.example.test') {
            if (action == 'get_vod_info' && !movieEntered.isCompleted) {
              movieEntered.complete();
            }
            if (action == 'get_series_info' && !seriesEntered.isCompleted) {
              seriesEntered.complete();
            }
            await release.future;
          }
          return _catalog(request);
        });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    profile.set('viewer-a', playlistIds: <int>[a]);
    await cinema.sources();
    final CinemaTitle cachedMovie = _title(a, CinemaKind.movie);
    final CinemaTitle cachedSeries = _title(a, CinemaKind.series);
    expect((await cinema.movieDetails(cachedMovie)).plot, 'Résumé privé A');
    expect((await cinema.seriesDetails(cachedSeries))?.details.plot,
        'Résumé privé A');
    // Ces deux nouvelles fiches partent pendant que les anciennes restent
    // en cache : on vérifie les deux chemins sans effacement manuel du dépôt.
    holdDetails = true;
    final Future<CinemaDetails> movie =
        cinema.movieDetails(_title(a, CinemaKind.movie, remoteId: '102'));
    final Future<SeriesDetails?> series =
        cinema.seriesDetails(_title(a, CinemaKind.series, remoteId: '202'));
    await Future.wait(<Future<void>>[movieEntered.future, seriesEntered.future])
        .timeout(const Duration(seconds: 5));
    profile.set('viewer-b', playlistIds: <int>[b]);
    await cinema.sources();
    release.complete();
    expect((await movie).plot, isNull);
    expect(await series, isNull);
    expect((await cinema.movieDetails(cachedMovie)).plot, isNull);
    expect(await cinema.seriesDetails(cachedSeries), isNull);
  });

  test('VOD isole son cache et une réponse A tardive après réaffectation à B',
      () async {
    final Completer<void> entered = Completer<void>();
    final Completer<void> release = Completer<void>();
    bool holdA = false;
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    await http.runWithClient(() async {
      final VodRepository vod = VodRepository.instance;
      profile.set('vod-viewer', playlistIds: <int>[a]);
      expect((await vod.fetchMovies()).single.name, 'Titre A');
      profile.set('vod-viewer', playlistIds: <int>[b]);
      expect((await vod.fetchMovies()).single.name, 'Titre B');

      profile.set('vod-viewer', playlistIds: <int>[a]);
      holdA = true;
      final pending = vod.fetchMovies(forceRefresh: true);
      await entered.future.timeout(const Duration(seconds: 5));
      profile.set('vod-viewer', playlistIds: <int>[b]);
      expect((await vod.fetchMovies()).single.name, 'Titre B');
      release.complete();
      expect(await pending, isEmpty);
      expect((await vod.fetchMovies()).single.name, 'Titre B');
      profile.set('empty-viewer', playlistIds: <int>[]);
      expect(await vod.fetchMovies(), isEmpty);
      expect(vod.categories(), isEmpty);
    },
        () => MockClient((request) async {
              if (holdA &&
                  request.url.host == 'a.example.test' &&
                  request.url.queryParameters['action'] == 'get_vod_streams') {
                if (!entered.isCompleted) entered.complete();
                await release.future;
              }
              return _catalog(request);
            }));
  });
}
