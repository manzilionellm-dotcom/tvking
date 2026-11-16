// Cinéma avec des listes M3U : de bout en bout, sans réseau réel.
//
// Le vrai module (CinemaRepository) lit ici :
//   • une liste M3U (lien ou fichier local) ;
//   • un compte Xtream dont l'API répond « 404 » pour les films : le M3U du
//     même compte prend le relais ;
//   • un compte Xtream dont l'API marche : rien ne change, aucun M3U lu.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/features/cinema/data/cinema_api.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/data/m3u_vod_store.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

const String kM3u = '''
#EXTM3U
#EXTINF:-1 tvg-logo="http://l/tf1.png" group-title="FR | TNT",TF1 HD
http://xt.invalid/live/user/pass/101.ts
#EXTINF:-1 tvg-logo="http://l/inception.jpg" group-title="FILMS | SCIENCE-FICTION",Inception (2010)
http://xt.invalid/movie/user/pass/5001.mkv
#EXTINF:-1 group-title="FILMS | SCIENCE-FICTION",Matrix (1999)
http://xt.invalid/movie/user/pass/5002.mp4
#EXTINF:-1 group-title="FILMS | COMEDIE",Taxi (1998)
http://xt.invalid/movie/user/pass/5003.mp4
#EXTINF:-1 tvg-logo="http://l/dark.jpg" group-title="SERIES | NETFLIX",Dark S01E02 Mensonges
http://xt.invalid/series/user/pass/9102.mkv
#EXTINF:-1 group-title="SERIES | NETFLIX",Dark S01E01 Secrets
http://xt.invalid/series/user/pass/9101.mkv
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory dir;
  late Database db;
  late CinemaRepository repo;
  late List<String> requests;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('m3u-vod-repo-');
    PathProviderPlatform.instance = _Paths(dir.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/lists.db';
    db = await PlaylistDatabase.instance.database;
    repo = CinemaRepository.forM3uTests();
    repo.forgetDiskForTesting();
    repo.clear();
    M3uVodApi.resetForTesting();
    requests = <String>[];
  });

  tearDown(() async {
    await repo.shutdownForTesting();
    M3uVodApi.resetForTesting();
    CinemaRepository.httpForTesting = null;
    RepairFlags.debugReset();
    await PlaylistDatabase.instance.closeForTesting();
    dir.deleteSync(recursive: true);
  });

  /// Une chaîne « film » en base : ce que l'import d'un M3U de films y laisse.
  Future<void> addVodRow(int playlistId) => db.insert('channels', <String, Object?>{
        'playlist_id': playlistId,
        'external_id': 'x$playlistId',
        'name': 'Inception (2010)',
        'category': 'FILMS',
        'stream_url': 'http://xt.invalid/movie/user/pass/5001.mkv',
      });

  Future<int> addPlaylist(Playlist p) => db.insert('playlists', p.toMap());

  void serve(http.Response Function(http.Request request) handler) {
    CinemaRepository.httpForTesting = () => MockClient((http.Request request) async {
          requests.add('${request.url.path}?${request.url.query}');
          return handler(request);
        });
  }

  http.Response m3uBody() => http.Response.bytes(utf8.encode(kM3u), 200,
      headers: <String, String>{'content-type': 'audio/x-mpegurl'});

  int downloads() => requests.where((String r) => r.contains('list.m3u') || r.contains('get.php')).length;

  group('liste M3U', () {
    late int id;
    setUp(() async {
      id = await addPlaylist(const Playlist(
        id: null,
        name: 'Ma liste',
        type: PlaylistType.m3u,
        m3uUrl: 'http://m3u.invalid/list.m3u',
        channelCount: 1,
        createdAt: 1,
      ));
      await addVodRow(id);
    });

    test('toutes les catégories du M3U, films et séries, lisibles', () async {
      serve((http.Request r) => r.url.path.endsWith('list.m3u') ? m3uBody() : http.Response('', 404));

      final List<CinemaSource> sources = await repo.sources();
      expect(sources.single.isM3u, isTrue);

      final List<CinemaCategory> movieCats = await repo.categories(CinemaKind.movie);
      expect(movieCats.map((CinemaCategory c) => c.name.toLowerCase()),
          <String>['films | science-fiction', 'films | comedie']);
      final CinemaTitleLoad sf = await repo.loadTitles(CinemaKind.movie, movieCats.first);
      expect(sf.failed, isFalse);
      expect(sf.titles.map((CinemaTitle t) => t.name), <String>['Inception (2010)', 'Matrix (1999)']);
      expect(sf.titles.first.streamUrl, 'http://xt.invalid/movie/user/pass/5001.mkv');
      expect(sf.titles.first.posterUrl, 'http://l/inception.jpg');
      final CinemaTitleLoad comedy = await repo.loadTitles(CinemaKind.movie, movieCats.last);
      expect(comedy.titles.map((CinemaTitle t) => t.name), <String>['Taxi (1998)']);

      final List<CinemaCategory> seriesCats = await repo.categories(CinemaKind.series);
      expect(seriesCats.single.name.toLowerCase(), 'series | netflix');
      final CinemaTitle dark = (await repo.loadTitles(CinemaKind.series, seriesCats.single)).titles.single;
      expect(dark.name, 'Dark');
      final SeriesDetails details = (await repo.seriesDetails(dark))!;
      expect(details.allInOrder.map((CinemaEpisode e) => e.title), <String>['Secrets', 'Mensonges']);
      expect(details.allInOrder.first.streamUrl, 'http://xt.invalid/series/user/pass/9101.mkv');

      expect(downloads(), 1, reason: 'UN seul téléchargement pour films + séries + fiches');
    });

    test('catalogue sur disque : au redémarrage, rien n\'est retéléchargé et les films restent lisibles', () async {
      serve((http.Request r) => r.url.path.endsWith('list.m3u') ? m3uBody() : http.Response('', 404));
      expect(await repo.refreshNow(CinemaKind.movie), isTrue);
      expect(downloads(), 1);

      // « Redémarrage » : la mémoire est vide, les fichiers sont là.
      repo.clear();
      M3uUrlBook.clearAll();
      M3uVodApi.resetForTesting();

      final List<CinemaCategory> cats = await repo.categories(CinemaKind.movie);
      expect(cats, hasLength(2));
      final CinemaTitleLoad sf = await repo.loadTitles(CinemaKind.movie, cats.first);
      expect(sf.titles.first.streamUrl, 'http://xt.invalid/movie/user/pass/5001.mkv',
          reason: 'l\'adresse revient du dossier M3U, pas du catalogue partagé');

      // Le catalogue partagé, lui, ne contient ni adresse ni identifiant.
      final String shared = Directory('${dir.path}/zuno_catalog')
          .listSync(recursive: true)
          .whereType<File>()
          .map((File f) => f.readAsStringSync())
          .join('\n');
      expect(shared, isNot(contains('xt.invalid')));
      expect(shared, isNot(contains('/movie/')));
      expect(downloads(), 1);
    });

    test('bouton « Actualiser » juste après : pas de second téléchargement', () async {
      serve((http.Request r) => r.url.path.endsWith('list.m3u') ? m3uBody() : http.Response('', 404));
      await repo.categories(CinemaKind.movie);
      await repo.refreshNow(CinemaKind.movie);
      await repo.refreshNow(CinemaKind.series);
      expect(downloads(), 1);
    });

    test('« Actualiser » plus tard : le M3U est relu ; s\'il est en panne, l\'ancien reste affiché', () async {
      bool down = false;
      serve((http.Request r) {
        if (down) return http.Response('Bad Gateway', 502);
        return r.url.path.endsWith('list.m3u') ? m3uBody() : http.Response('', 404);
      });
      final List<CinemaCategory> cats = await repo.categories(CinemaKind.movie);
      expect(cats, hasLength(2));
      expect(downloads(), 1);

      // Le dossier date de plus de deux minutes : « Actualiser » relit le M3U.
      final File meta = File('${dir.path}/zuno_m3u_vod/p$id/meta.json');
      final Map<String, Object?> json = jsonDecode(meta.readAsStringSync()) as Map<String, Object?>;
      json['builtAt'] = DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
      meta.writeAsStringSync(jsonEncode(json));
      expect(await repo.refreshNow(CinemaKind.movie), isTrue);
      expect(downloads(), 2);

      // Panne du fournisseur : l'actualisation échoue, le catalogue reste.
      json['builtAt'] = DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
      meta.writeAsStringSync(jsonEncode(json));
      down = true;
      expect(await repo.refreshNow(CinemaKind.movie), isFalse);
      expect(await repo.categories(CinemaKind.movie), hasLength(2));
    });

    test('M3U illisible (page web) : échec propre, rien d\'enregistré', () async {
      serve((http.Request r) => http.Response('<html>Erreur</html>', 200));
      final List<CinemaCategory> cats = await repo.categories(CinemaKind.movie);
      expect(cats, isEmpty);
      expect(Directory('${dir.path}/zuno_m3u_vod/p$id').existsSync(), isFalse);
    });
  });

  test('liste M3U sans aucun film en base : on ne télécharge rien', () async {
    await addPlaylist(const Playlist(
      id: null,
      name: 'Directs',
      type: PlaylistType.m3u,
      m3uUrl: 'http://m3u.invalid/list.m3u',
      createdAt: 1,
    ));
    serve((http.Request r) => m3uBody());
    expect(await repo.sources(), isEmpty);
    expect(await repo.categories(CinemaKind.movie), isEmpty);
    expect(requests, isEmpty);
  });

  test('fichier M3U local : lu sans réseau', () async {
    final File file = File('${dir.path}/ma-liste.m3u')..writeAsStringSync(kM3u);
    final int id = await addPlaylist(Playlist(
      id: null,
      name: 'Clé USB',
      type: PlaylistType.m3u,
      m3uUrl: Uri.file(file.path).toString(),
      channelCount: 1,
      createdAt: 1,
    ));
    await addVodRow(id);
    serve((http.Request r) => http.Response('', 500));
    final List<CinemaCategory> cats = await repo.categories(CinemaKind.movie);
    expect(cats, hasLength(2));
    expect(requests, isEmpty);
  });

  test('interrupteur de secours : ancien comportement, aucun M3U lu', () async {
    final int id = await addPlaylist(const Playlist(
      id: null,
      name: 'Ma liste',
      type: PlaylistType.m3u,
      m3uUrl: 'http://m3u.invalid/list.m3u',
      channelCount: 1,
      createdAt: 1,
    ));
    await addVodRow(id);
    await addPlaylist(const Playlist(
      id: null,
      name: 'Abonnement',
      type: PlaylistType.xtream,
      xtreamServer: 'http://xt.invalid',
      xtreamUsername: 'user',
      xtreamPassword: 'pass',
      createdAt: 1,
    ));
    SharedPreferences.setMockInitialValues(<String, Object>{RepairFlags.cinemaM3uOffKey: true});
    await RepairFlags.load();
    expect(RepairFlags.cinemaM3uOff, isTrue);
    serve((http.Request r) {
      if (r.url.path.endsWith('list.m3u') || r.url.path.endsWith('get.php')) fail('aucun M3U ne doit être lu');
      return http.Response('Not Found', 404);
    });
    final List<CinemaSource> sources = await repo.sources();
    expect(sources.map((CinemaSource s) => s.isM3u), <bool>[false], reason: 'la liste M3U est ignorée');
    expect(await repo.categories(CinemaKind.movie), isEmpty);
    expect(downloads(), 0);
  });

  group('compte Xtream', () {
    Future<void> addAccount() => addPlaylist(const Playlist(
          id: null,
          name: 'Abonnement',
          type: PlaylistType.xtream,
          xtreamServer: 'http://xt.invalid',
          xtreamUsername: 'user',
          xtreamPassword: 'pass',
          createdAt: 1,
        ));

    test('l\'API répond « 404 » pour les films : le M3U du compte prend le relais', () async {
      await addAccount();
      serve((http.Request r) {
        if (r.url.path.endsWith('get.php')) {
          expect(r.url.queryParameters['username'], 'user');
          expect(r.url.queryParameters['type'], 'm3u_plus');
          return m3uBody();
        }
        if (r.url.path.endsWith('player_api.php')) return http.Response('Not Found', 404);
        return http.Response('', 500);
      });

      final List<CinemaCategory> cats = await repo.categories(CinemaKind.movie);
      expect(cats.map((CinemaCategory c) => c.name.toLowerCase()),
          <String>['films | science-fiction', 'films | comedie']);
      final CinemaTitleLoad sf = await repo.loadTitles(CinemaKind.movie, cats.first);
      expect(sf.titles.map((CinemaTitle t) => t.remoteId), <String>['5001', '5002']);
      expect(sf.titles.first.streamUrl, 'http://xt.invalid/movie/user/pass/5001.mkv');

      // Les séries viennent du MÊME fichier : pas de second téléchargement.
      final List<CinemaCategory> seriesCats = await repo.categories(CinemaKind.series);
      expect(seriesCats, hasLength(1));
      final CinemaTitle dark = (await repo.loadTitles(CinemaKind.series, seriesCats.single)).titles.single;
      expect((await repo.seriesDetails(dark))!.allInOrder, hasLength(2));
      expect(downloads(), 1);

      // Pas de fiche détaillée dans un M3U, et pas d'appel inutile au serveur.
      final int before = requests.length;
      final CinemaDetails d = await repo.movieDetails(sf.titles.first);
      expect(d.plot, isNull);
      expect(requests.length, before);
    });

    test('l\'API a des films : aucun M3U n\'est lu, rien ne change', () async {
      await addAccount();
      serve((http.Request r) {
        if (r.url.path.endsWith('get.php')) fail('le M3U ne doit pas être lu');
        final String action = r.url.queryParameters['action'] ?? '';
        if (action == 'get_vod_categories') {
          return http.Response('[{"category_id":"1","category_name":"FR Films"}]', 200);
        }
        if (action == 'get_vod_streams') {
          return http.Response('[{"stream_id":7,"name":"Film API","category_id":"1","container_extension":"mp4"}]', 200);
        }
        return http.Response('[]', 200);
      });
      final List<CinemaCategory> cats = await repo.categories(CinemaKind.movie);
      expect(cats.single.name, 'FR Films');
      final CinemaTitle t = (await repo.loadTitles(CinemaKind.movie, cats.single)).titles.single;
      expect(t.streamUrl, 'http://xt.invalid:80/movie/user/pass/7.mp4'.replaceAll(':80', ''));
      expect(downloads(), 0);
    });

    test('panne passagère (503) : comportement d\'avant, aucun M3U lu', () async {
      await addAccount();
      serve((http.Request r) {
        if (r.url.path.endsWith('get.php')) fail('le M3U ne doit pas être lu pour une panne passagère');
        return http.Response('Service Unavailable', 503);
      });
      expect(await repo.categories(CinemaKind.movie), isEmpty);
      expect(downloads(), 0);
    });

    test('liste de catégories vide (compte sans films) : crue, aucun M3U lu', () async {
      await addAccount();
      serve((http.Request r) {
        if (r.url.path.endsWith('get.php')) fail('le M3U ne doit pas être lu pour une liste vide');
        return http.Response('[]', 200);
      });
      expect(await repo.categories(CinemaKind.movie), isEmpty);
      expect(await repo.categories(CinemaKind.series), isEmpty);
      expect(downloads(), 0);
    });

    test('liste vide + bouton « Actualiser » : le M3U du compte est lu', () async {
      await addAccount();
      serve((http.Request r) {
        if (r.url.path.endsWith('get.php')) return m3uBody();
        return http.Response('[]', 200);
      });
      expect(await repo.refreshNow(CinemaKind.movie), isTrue);
      expect(await repo.categories(CinemaKind.movie), hasLength(2));
      expect(downloads(), 1);
    });

    test('le serveur répond par les infos du compte au lieu d\'une liste : le M3U est lu', () async {
      await addAccount();
      serve((http.Request r) {
        if (r.url.path.endsWith('get.php')) return m3uBody();
        return http.Response('{"user_info":{"auth":1},"server_info":{"url":"xt.invalid"}}', 200);
      });
      expect(await repo.categories(CinemaKind.movie), hasLength(2));
      expect(downloads(), 1);
    });

    test('le M3U du compte est refusé aussi : liste vide, erreur journalisée, pas de plantage', () async {
      await addAccount();
      serve((http.Request r) => http.Response('Forbidden', r.url.path.endsWith('get.php') ? 403 : 404));
      expect(await repo.categories(CinemaKind.movie), isEmpty);
    });
  });
}
