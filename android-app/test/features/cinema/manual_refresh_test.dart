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

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override Future<String?> getApplicationDocumentsPath() async => root;
  @override Future<String?> getApplicationSupportPath() async => root;
  @override Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  test('Actualiser télécharge le seul film ajouté et conserve le catalogue en cas de panne', () async {
    final Directory dir = Directory.systemTemp.createTempSync('tv-cinema-refresh-');
    PathProviderPlatform.instance = _Paths(dir.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/lists.db';
    final Database db = await PlaylistDatabase.instance.database;
    await db.insert('playlists', const Playlist(id: null, name: 'Test', type: PlaylistType.xtream,
      xtreamServer: 'http://catalog.invalid', xtreamUsername: 'test', xtreamPassword: 'test', createdAt: 1).toMap());
    int count = 1;
    int requests = 0;
    bool fail = false;
    CinemaRepository.httpForTesting = () => MockClient((http.Request request) async {
      requests++;
      if (fail) return http.Response('offline', 503);
      if (request.url.queryParameters['action'] == 'get_vod_categories') {
        return http.Response('[{"category_id":"1","category_name":"FR Films"}]', 200);
      }
      return http.Response(jsonEncode(<Object>[
        for (int n = 1; n <= count; n++) <String, Object>{'stream_id': n, 'name': 'Film $n', 'category_id': '1', 'container_extension': 'mp4'},
      ]), 200);
    });
    final CinemaRepository repo = CinemaRepository.instance;
    addTearDown(() async {
      repo.clear();
      CinemaRepository.httpForTesting = null;
      await PlaylistDatabase.instance.closeForTesting();
    });
    expect(await repo.refreshNow(CinemaKind.movie), isTrue);
    var categories = await repo.categories(CinemaKind.movie);
    expect((await repo.loadTitles(CinemaKind.movie, categories.single)).titles, hasLength(1));
    final int before = requests;
    count = 2;
    expect(await repo.refreshNow(CinemaKind.movie), isTrue);
    categories = await repo.categories(CinemaKind.movie);
    expect((await repo.loadTitles(CinemaKind.movie, categories.single)).titles.map((t) => t.name), contains('Film 2'));
    expect(requests, greaterThan(before));
    fail = true;
    expect(await repo.refreshNow(CinemaKind.movie), isFalse);
    expect((await repo.loadTitles(CinemaKind.movie, categories.single)).titles, hasLength(2));
  });
}
