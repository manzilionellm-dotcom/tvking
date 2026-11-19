// Cinéma + M3U sur un VRAI réseau (sockets locaux, pas de faux client HTTP).
//
// Les autres tests utilisent un faux client : ils prouvent la logique, pas le
// comportement d'un vrai serveur. Ici un petit serveur HTTP local se comporte
// comme les panels IPTV de la nature : réponse en morceaux, compressée, derrière
// une redirection, refusée à certaines signatures de lecteur (User-Agent), page
// web à la place du M3U, connexion coupée en route, serveur qui se tait.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/cinema/data/cinema_api.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/m3u_fetcher.dart';
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

String m3uText({int films = 3}) {
  final StringBuffer b = StringBuffer('#EXTM3U\n');
  b.write('#EXTINF:-1 group-title="FR | TNT",TF1\nhttp://panel.invalid/live/u/p/1.ts\n');
  for (int i = 1; i <= films; i++) {
    b.write('#EXTINF:-1 tvg-logo="http://img.invalid/$i.jpg" group-title="FILMS | ACTION",Film $i (20${10 + i})\n'
        'http://panel.invalid/movie/u/p/${5000 + i}.mkv\n');
  }
  b.write('#EXTINF:-1 group-title="SERIES | DRAMA",Serie S01E01 Pilote\nhttp://panel.invalid/series/u/p/9001.mp4\n');
  return b.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late HttpServer server;
  late Directory dir;
  late String base;
  final List<String> seenAgents = <String>[];
  late Future<void> Function(HttpRequest) handler;

  setUp(() async {
    // flutter_test refuse tout HTTP par défaut (réponse 400) : on le rouvre
    // pour cette seule machine, l'adresse locale.
    HttpOverrides.global = null;
    dir = Directory.systemTemp.createTempSync('m3u-net-');
    seenAgents.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((HttpRequest req) async {
      seenAgents.add(req.headers.value(HttpHeaders.userAgentHeader) ?? '');
      try {
        await handler(req);
      } catch (_) {
        // Le client a raccroché : normal dans ces scénarios.
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  Future<void> sendM3u(HttpRequest req, String body, {bool chunked = false}) async {
    req.response.headers.contentType = ContentType('audio', 'x-mpegurl');
    if (!chunked) {
      req.response.write(body);
      await req.response.close();
      return;
    }
    req.response.bufferOutput = false;
    req.response.headers.chunkedTransferEncoding = true;
    const int step = 90;
    for (int i = 0; i < body.length; i += step) {
      req.response.write(body.substring(i, i + step > body.length ? body.length : i + step));
      await req.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await req.response.close();
  }

  /// Annonce 200 000 octets, n'en envoie que [head], puis RACCROCHE pour de bon
  /// (le client reçoit une fin de connexion, pas un silence).
  ///
  /// Piège évité : `detachSocket` refuse de rendre la main une fois les
  /// en-têtes partis (StateError). On détache donc AVANT toute écriture et on
  /// parle HTTP à la main sur la prise.
  Future<void> cutAfter(HttpRequest req, String head) async {
    final Socket socket = await req.response.detachSocket(writeHeaders: false);
    socket.write('HTTP/1.1 200 OK\r\n'
        'content-type: audio/x-mpegurl\r\n'
        'content-length: 200000\r\n'
        'connection: close\r\n\r\n');
    socket.write(head);
    await socket.flush();
    socket.destroy();
  }

  Future<String> fetch({FetchTimeouts? timeouts}) async {
    final File target = File('${dir.path}/dl.m3u');
    await M3uFetcher.fetchToFile('$base/get.php?username=u&password=p&type=m3u_plus', target, timeouts: timeouts);
    return target.readAsStringSync();
  }

  const FetchTimeouts quick = FetchTimeouts(
    headers: Duration(seconds: 3),
    idle: Duration(milliseconds: 800),
    total: Duration(seconds: 6),
  );

  group('M3uFetcher.fetchToFile sur un vrai socket', () {
    test('réponse en morceaux : le fichier est identique à l\'original', () async {
      final String body = m3uText(films: 40);
      handler = (HttpRequest req) => sendM3u(req, body, chunked: true);
      expect(await fetch(timeouts: quick), body);
    });

    test('réponse compressée (gzip) : décompressée à l\'arrivée', () async {
      final String body = m3uText(films: 40);
      handler = (HttpRequest req) async {
        req.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        req.response.add(gzip.encode(utf8.encode(body)));
        await req.response.close();
      };
      expect(await fetch(timeouts: quick), body);
    });

    test('redirection : le M3U est suivi jusqu\'au bout', () async {
      final String body = m3uText();
      handler = (HttpRequest req) async {
        if (req.uri.path == '/get.php') {
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set(HttpHeaders.locationHeader, '/vraie-liste.m3u');
          await req.response.close();
        } else {
          await sendM3u(req, body);
        }
      };
      expect(await fetch(timeouts: quick), body);
    });

    test('panel qui ne sert que certains lecteurs : la rotation de signatures trouve la bonne', () async {
      // La première signature essayée est celle des réglages (VLC par défaut).
      // Ce panel la refuse, comme ExoPlayer et OkHttp : il ne connaît que
      // « IPTVSmartersPlayer », la quatrième de la liste.
      final String body = m3uText();
      handler = (HttpRequest req) async {
        final String ua = req.headers.value(HttpHeaders.userAgentHeader) ?? '';
        if (ua != 'IPTVSmartersPlayer') {
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
          return;
        }
        await sendM3u(req, body);
      };
      expect(await fetch(timeouts: quick), body);
      expect(seenAgents.first, contains('VLC'), reason: 'la signature des réglages passe en premier');
      expect(seenAgents.toSet().length, greaterThanOrEqualTo(4), reason: 'plusieurs signatures essayées');
      expect(seenAgents.last, 'IPTVSmartersPlayer');
    });

    test('page web à la place du M3U : refusée, rien n\'est gardé comme liste', () async {
      handler = (HttpRequest req) async {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body>Abonnement expiré</body></html>');
        await req.response.close();
      };
      await expectLater(fetch(timeouts: quick), throwsA(isA<Exception>().having((Exception e) => '$e', 'message', contains('page web'))));
    });

    test('connexion coupée en route : échec net (pas un silence), jamais de fichier pris pour complet', () async {
      handler = (HttpRequest req) => cutAfter(req, m3uText().substring(0, 400));
      Object? failure;
      try {
        await fetch(timeouts: quick);
      } catch (e) {
        failure = e;
      }
      expect(failure, isA<Exception>(), reason: 'une liste coupée ne doit jamais passer pour complète');
      final String text = '$failure'.toLowerCase();
      expect(text, contains('closed'), reason: 'c\'est une fin de connexion : $failure');
      expect(text, isNot(contains('s\'est tu')), reason: 'pas le délai d\'inactivité : le serveur a raccroché');
      // Chaque signature a eu sa chance : la coupure n'a pas arrêté la boucle trop tôt.
      expect(seenAgents.length, greaterThan(1));
    });

    test('serveur qui se tait en route : délai d\'inactivité, pas d\'attente infinie', () async {
      handler = (HttpRequest req) async {
        req.response.headers.contentType = ContentType('audio', 'x-mpegurl');
        req.response.bufferOutput = false;
        req.response.write('#EXTM3U\n#EXTINF:-1,x\n');
        await req.response.flush();
        await Future<void>.delayed(const Duration(seconds: 30));
      };
      final Stopwatch sw = Stopwatch()..start();
      await expectLater(fetch(timeouts: quick), throwsA(isA<Exception>().having((Exception e) => '$e', 'message', contains('s\'est tu'))));
      expect(sw.elapsed, lessThan(const Duration(seconds: 8)));
    });

    test('plafond de taille : le téléchargement s\'arrête', () async {
      final String body = m3uText(films: 2000);
      handler = (HttpRequest req) => sendM3u(req, body);
      final File target = File('${dir.path}/dl.m3u');
      await expectLater(
        M3uFetcher.fetchToFile('$base/get.php', target, timeouts: quick, maxBytes: 10 * 1024),
        throwsA(isA<Object>().having((Object e) => '$e', 'message', contains('dépasse'))),
      );
    });

    test('un M3U de 25 Mo arrive en entier sans erreur', () async {
      // ~97 octets par film : 290 000 films ≈ 28 Mo, plus que les 25 Mo du titre.
      final StringBuffer big = StringBuffer(m3uText(films: 1));
      for (int i = 0; i < 290000; i++) {
        big.write('#EXTINF:-1 group-title="FILMS | GROS",Film gros $i\nhttp://panel.invalid/movie/u/p/${100000 + i}.mkv\n');
      }
      final String body = big.toString();
      expect(body.length, greaterThan(25 * 1024 * 1024));
      handler = (HttpRequest req) => sendM3u(req, body);
      final File target = File('${dir.path}/dl.m3u');
      await M3uFetcher.fetchToFile('$base/get.php', target,
          timeouts: const FetchTimeouts(headers: Duration(seconds: 5), idle: Duration(seconds: 5), total: Duration(seconds: 60)));
      expect(target.lengthSync(), utf8.encode(body).length);
    });
  });

  group('Cinéma de bout en bout, vrai réseau', () {
    late Database db;
    late CinemaRepository repo;

    setUp(() async {
      PathProviderPlatform.instance = _Paths(dir.path);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await PlaylistDatabase.instance.closeForTesting();
      PlaylistDatabase.debugFilePath = '${dir.path}/lists.db';
      db = await PlaylistDatabase.instance.database;
      repo = CinemaRepository.instance;
      CinemaRepository.httpForTesting = null; // vrais clients HTTP
      repo.forgetDiskForTesting();
      repo.clear();
      M3uVodApi.resetForTesting();
    });

    tearDown(() async {
      await repo.shutdownForTesting();
      M3uVodApi.resetForTesting();
      await PlaylistDatabase.instance.closeForTesting();
    });

    /// Un abonnement Xtream dont le serveur local joue le panel.
    Future<void> addXtreamAccount() => db.insert(
          'playlists',
          Playlist(
            id: null,
            name: 'Abonnement',
            type: PlaylistType.xtream,
            xtreamServer: base,
            xtreamUsername: 'u',
            xtreamPassword: 'p',
            createdAt: 1,
          ).toMap(),
        );

    /// Panel dont l'API Xtream ne connaît pas les films (404), seul `get.php` répond.
    Future<void> Function(HttpRequest) panelWithoutVodApi(Future<void> Function(HttpRequest) onGet) {
      return (HttpRequest req) async {
        if (req.uri.path.endsWith('get.php')) {
          await onGet(req);
        } else {
          req.response.statusCode = HttpStatus.notFound;
          req.response.write('Not Found');
          await req.response.close();
        }
      };
    }

    test('compte Xtream : l\'API répond 404 pour les films, le M3U du compte est lu pour de vrai', () async {
      final String body = m3uText(films: 5);
      handler = panelWithoutVodApi((HttpRequest req) => sendM3u(req, body, chunked: true));
      await addXtreamAccount();
      final List<CinemaCategory> cats = await repo.categories(CinemaKind.movie);
      expect(cats.map((CinemaCategory c) => c.name), <String>['FILMS | ACTION']);
      final CinemaTitleLoad films = await repo.loadTitles(CinemaKind.movie, cats.single);
      expect(films.titles, hasLength(5));
      expect(films.titles.first.streamUrl, 'http://panel.invalid/movie/u/p/5001.mkv');
      final List<CinemaCategory> series = await repo.categories(CinemaKind.series);
      expect(series.single.name, 'SERIES | DRAMA');
    });

    test('connexion coupée pendant le M3U : pas de liste vide retenue, rien laissé sur le disque, la reprise marche', () async {
      final String body = m3uText(films: 5);
      bool cut = true;
      handler = panelWithoutVodApi((HttpRequest req) async {
        if (!cut) return sendM3u(req, body);
        await cutAfter(req, body.substring(0, 300));
      });
      await addXtreamAccount();

      expect(await repo.categories(CinemaKind.movie), isEmpty, reason: 'rien à montrer, mais pas d\'écran « aucun film » figé');
      final Directory root = Directory('${dir.path}/zuno_m3u_vod');
      final List<String> left = root.existsSync()
          ? root.listSync().map((FileSystemEntity e) => e.path.split('/').last).toList()
          : <String>[];
      expect(left, isEmpty, reason: 'ni dossier à moitié fait ni fichier temporaire');

      // Le réseau revient : la même demande, sans rien vider, marche.
      cut = false;
      final List<CinemaCategory> again = await repo.categories(CinemaKind.movie);
      expect(again.map((CinemaCategory c) => c.name), <String>['FILMS | ACTION']);
    });

    test('liste M3U (pas Xtream) servie compressée : films, séries et épisodes lisibles', () async {
      final String body = '${m3uText(films: 4)}'
          '#EXTINF:-1 group-title="SERIES | DRAMA",Serie S01E02 Suite\n'
          'http://panel.invalid/series/u/p/9002.mp4\n';
      int downloads = 0;
      handler = (HttpRequest req) async {
        if (!req.uri.path.endsWith('list.m3u')) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        downloads++;
        req.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        req.response.add(gzip.encode(utf8.encode(body)));
        await req.response.close();
      };
      final int id = await db.insert(
        'playlists',
        Playlist(
          id: null,
          name: 'Ma liste',
          type: PlaylistType.m3u,
          m3uUrl: '$base/list.m3u',
          channelCount: 1,
          createdAt: 1,
        ).toMap(),
      );
      // Ce que l'import d'un M3U de films laisse en base : la liste compte comme source Cinéma.
      await db.insert('channels', <String, Object?>{
        'playlist_id': id,
        'external_id': 'x$id',
        'name': 'Film 1 (2011)',
        'category': 'FILMS | ACTION',
        'stream_url': 'http://panel.invalid/movie/u/p/5001.mkv',
      });

      final List<CinemaCategory> cats = await repo.categories(CinemaKind.movie);
      expect(cats.map((CinemaCategory c) => c.name), <String>['FILMS | ACTION']);
      final CinemaTitleLoad films = await repo.loadTitles(CinemaKind.movie, cats.single);
      expect(films.titles, hasLength(4));
      final List<CinemaCategory> seriesCats = await repo.categories(CinemaKind.series);
      final CinemaTitle serie = (await repo.loadTitles(CinemaKind.series, seriesCats.single)).titles.single;
      final SeriesDetails details = (await repo.seriesDetails(serie))!;
      expect(details.allInOrder.map((CinemaEpisode e) => e.streamUrl),
          <String>['http://panel.invalid/series/u/p/9001.mp4', 'http://panel.invalid/series/u/p/9002.mp4']);
      expect(downloads, 1, reason: 'un seul téléchargement pour films, séries et fiches');
    });
  });
}
