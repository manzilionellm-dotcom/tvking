import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/tv/presentation/novatube_max_m3u_batch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Les dix profils sont conservés après relecture du catalogue', () {
    var catalog = ProfileCatalog.fresh();
    for (int i = 2; i <= 10; i++) {
      catalog = catalog.add(name: 'Profil $i', isKids: i == 7, nowMs: 1234500 + i)!;
    }
    expect(catalog.profiles.map((p) => p.id).toSet().length, 10);
    expect(catalog.add(name: 'Onze', isKids: false, nowMs: 1234600), isNull);
    expect(ProfileCatalog.decode(catalog.encode()).profiles.length, 10);
  });

  test('Lot M3U privé, dédoublonné, conserve HTTP et protège les noms', () {
    const first = 'http://test.invalid/get.php?username=a&password=b';
    const second = 'https://test.invalid/autre';
    final entries = MaxM3uBatchDialog.entries('$first\r\n$first\n$second', {});
    expect(entries.map((e) => e.url), [first, second]);
    expect(entries.map((e) => e.name), ['test.invalid · 1', 'test.invalid · 2']);
    expect(MaxM3uBatchDialog.entries(first, {first}), isEmpty);
    expect(() => MaxM3uBatchDialog.entries('file:///tmp/data', {}), throwsFormatException);
  });

  test('Deux listes locales importées même si une troisième est indisponible', () async {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('novatube-max-lots');
    final db = PlaylistDatabase.instance;
    PlaylistDatabase.debugFilePath = '${directory.path}/max.db';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final path = request.uri.path;
      if (path == '/une' || path == '/deux') {
        request.response.headers.contentType = ContentType.text;
        final name = path.substring(1);
        request.response.write('#EXTM3U\n#EXTINF:-1 tvg-id="$name" group-title="Test",$name\nhttp://example.invalid/$name.ts\n');
      } else {
        request.response.statusCode = 403;
      }
      request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await db.closeForTesting();
      PlaylistDatabase.debugFilePath = null;
      await directory.delete(recursive: true);
    });
    final base = 'http://127.0.0.1:${server.port}';
    final entries = MaxM3uBatchDialog.entries('$base/une\n$base/refuse\n$base/deux', {});
    final repo = PlaylistRepository.instance;
    PlaylistRepository.mergeAllPlaylists = true;
    await repo.initialize();
    final results = await repo.addM3uPlaylistsBatch(entries: entries);
    expect(results.map((r) => r.ok), [true, false, true]);
    expect((await repo.getAllChannels()).map((c) => c.name).toSet(), {'une', 'deux'});
    expect(repo.currentPlaylists.where((p) => p.channelCount > 0).length, 2);
  });
}
