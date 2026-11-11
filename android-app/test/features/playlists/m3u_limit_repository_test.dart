import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    PlaylistRepository.mergeAllPlaylists = true;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    AppPlatform.isZuno = true;
    ActiveProfile.instance.set('p1');
  });
  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    PlaylistRepository.mergeAllPlaylists = false;
    AppPlatform.isZuno = false;
  });

  test(
    '50 003 URL valides : 50 000 lignes stockées, trois non importées',
    () async {
      final body = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 50003; i++) {
        body.writeln('http://127.0.0.1/fixture/$i.ts');
      }
      final client = MockClient(
        (_) async => http.Response(body.toString(), 200),
      );
      addTearDown(client.close);
      final repo = PlaylistRepository.instance;
      await repo.addM3uPlaylist(
        name: 'Import synthétique',
        url: 'http://127.0.0.1/fixture/catalogue.m3u',
        httpClient: client,
      );
      final db = await PlaylistDatabase.instance.database;
      final count = await db.rawQuery('SELECT COUNT(*) AS n FROM channels');
      expect(count.single['n'], 50000);
      final snapshot = repo.channelLimitSnapshot.value!;
      expect(snapshot.storedRows, 50000);
      expect(snapshot.loadedRows, 50000);
      expect(snapshot.hasLoadLimit, isFalse);
      final source = snapshot.affectedSources.single;
      expect(source.importCounts!.validEntries, 50003);
      expect(source.importCounts!.retainedEntries, 50000);
      expect(source.importCounts!.skippedEntries, 3);
    },
  );
}
