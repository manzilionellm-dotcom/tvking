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
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cinema/data/cinema_repository.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/tv/core/tv_content_refresh.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  FlavorConfig.setCurrent(FlavorConfig.sevenMotion);

  test('la demande TV attend le nouveau film et signale une panne fournisseur', () async {
    const String mac = 'MK:11:22:33:44:55';
    final Directory dir = Directory.systemTemp.createTempSync('tv-refresh-pipeline-');
    PathProviderPlatform.instance = _Paths(dir.path);
    SharedPreferences.setMockInitialValues(<String, Object>{'device.virtual_mac.v1': mac});
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/lists.db';
    final Database db = await PlaylistDatabase.instance.database;
    await db.insert('playlists', const Playlist(
      id: null, name: 'Test', type: PlaylistType.xtream,
      xtreamServer: 'http://catalog.invalid', xtreamUsername: 'test',
      xtreamPassword: 'test', createdAt: 1, lastSyncedAt: 1, channelCount: 1,
    ).toMap());
    await PlaylistRepository.instance.initialize();
    int count = 1;
    bool fail = false;
    Completer<void>? movieStarted;
    Completer<void>? releaseMovie;
    int movieRequests = 0;

    http.Client client() => MockClient((http.Request request) async {
      if (request.url.path.startsWith('/api/device-source/')) {
        return http.Response(jsonEncode(<String, Object>{
          'mac': mac, 'rev': 1, 'updated_at': 1791300000001,
          'sources': <Object>[<String, Object>{
            'type': 'xtream', 'server_url': 'http://catalog.invalid',
            'username': 'test', 'password': 'test',
          }],
        }), 200);
      }
      if (request.url.path.startsWith('/api/')) return http.Response('{}', 404);
      if (request.url.path.endsWith('xmltv.php')) return http.Response('<tv></tv>', 200);
      final String? action = request.url.queryParameters['action'];
      if (action == 'get_vod_streams') {
        movieRequests++;
        if (movieStarted != null && !movieStarted!.isCompleted) movieStarted!.complete();
        if (releaseMovie != null) await releaseMovie!.future;
      }
      if (fail) return http.Response('offline', 503);
      if (action == 'get_live_categories' || action == 'get_vod_categories' ||
          action == 'get_series_categories') {
        return http.Response('[{"category_id":"1","category_name":"FR Test"}]', 200);
      }
      if (action == 'get_live_streams' || action == 'get_vod_streams' || action == 'get_series') {
        return http.Response(jsonEncode(<Object>[
          for (int n = 1; n <= count; n++) <String, Object>{
            'stream_id': n, 'series_id': n, 'name': 'Film $n',
            'category_id': '1', 'container_extension': 'mp4',
          },
        ]), 200);
      }
      return http.Response('{"user_info":{"auth":1,"status":"Active"}}', 200);
    });

    final CinemaRepository cinema = CinemaRepository.instance;
    CinemaRepository.httpForTesting = client;
    addTearDown(() async {
      CinemaRepository.httpForTesting = null;
      cinema.clear();
      await PlaylistDatabase.instance.closeForTesting();
    });

    await http.runWithClient(() async {
      expect(await cinema.refreshNow(CinemaKind.movie), isTrue);
      count = 2;
      final int before = movieRequests;
      movieStarted = Completer<void>();
      releaseMovie = Completer<void>();
      final Future<void> first = TvContentRefresh.run(clearCinema: true);
      await movieStarted!.future;
      bool secondFinished = false;
      final Future<void> second = TvContentRefresh.run(clearCinema: true).then((_) {
        secondFinished = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(secondFinished, isFalse);
      expect(TvContentRefresh.running.value, isTrue);
      releaseMovie!.complete();
      await Future.wait(<Future<void>>[first, second]);
      releaseMovie = null;
      final categories = await cinema.categories(CinemaKind.movie);
      final titles = (await cinema.loadTitles(CinemaKind.movie, categories.single)).titles;
      expect(titles.map((t) => t.name), contains('Film 2'));
      expect(movieRequests, greaterThan(before));
      expect(TvContentRefresh.running.value, isFalse);

      fail = true;
      await TvContentRefresh.run(clearCinema: true);
      expect(TvContentRefresh.notice.value, isNotNull);
      expect((await cinema.loadTitles(CinemaKind.movie, categories.single)).titles, hasLength(2));
      expect(TvContentRefresh.running.value, isFalse);
    }, client);
  });
}
