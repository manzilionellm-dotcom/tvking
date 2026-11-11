// Fixture portable vers le 116 : seules les API déjà présentes sont utilisées.
// Les 100 000 lignes sont produites en SQL, sans liste de 100 000 Channel Dart.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';

abstract final class ChannelLimitFixture {
  static late Database db;

  static ProfileCatalog catalog({List<int>? ids, bool kids = false}) =>
      ProfileCatalog(
        profiles: [
          FamilyProfile(
            id: 'p1',
            name: 'Comptage',
            avatar: 0,
            isKids: kids,
            createdAtMs: 0,
            playlistIds: ids,
          ),
        ],
        activeId: 'p1',
        askOnStartup: false,
      );

  static Future<void> setUpAll() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppPlatform.isZuno = true;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    PlaylistRepository.mergeAllPlaylists = true;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    db = await PlaylistDatabase.instance.database;
    for (var source = 1; source <= 4; source++) {
      await db.insert('playlists', {
        'id': source,
        'name': 'Source $source',
        'type': 'm3u',
        'created_at': source,
        'is_active': source == 1 ? 1 : 0,
        // Valeur volontairement inexacte : le comptage doit lire COUNT(*).
        'channel_count': 17,
      });
      await db.rawInsert(
        '''
        WITH RECURSIVE seq(n) AS (
          SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 25000
        )
        INSERT INTO channels
          (playlist_id, external_id, name, category, stream_url, is_live)
        SELECT ?, 'fixture-' || ? || '-' || n, 'Chaîne ' || n,
               'Fixture', 'http://127.0.0.1/fixture/' || n || '.ts', 1
        FROM seq
      ''',
        [source, source],
      );
    }
    ProfileRepository.instance.resetForTesting(catalog(ids: [1, 2, 3, 4]));
  }

  static Future<List<Map<String, Object?>>> fingerprint() => db.rawQuery('''
      SELECT playlist_id, COUNT(*) AS rows_count, SUM(local_id) AS ids_sum,
             SUM(LENGTH(external_id)) AS external_lengths,
             SUM(LENGTH(name)) AS name_lengths,
             SUM(LENGTH(stream_url)) AS url_lengths
      FROM channels GROUP BY playlist_id ORDER BY playlist_id
    ''');

  static Future<void> preventChannelWrites() async {
    // Détecte toute mutation de cette fixture pendant le scénario de lecture.
    // Aucun trigger n'est installé dans une base client.
    await db.execute('''CREATE TEMP TRIGGER fixture_no_delete
      BEFORE DELETE ON channels BEGIN
        SELECT RAISE(ABORT, 'L104 lecture ne doit pas supprimer'); END''');
    await db.execute('''CREATE TEMP TRIGGER fixture_no_update
      BEFORE UPDATE ON channels BEGIN
        SELECT RAISE(ABORT, 'L104 lecture ne doit pas modifier'); END''');
    await db.execute('''CREATE TEMP TRIGGER fixture_no_insert
      BEFORE INSERT ON channels BEGIN
        SELECT RAISE(ABORT, 'L104 lecture ne doit pas inserer'); END''');
  }

  static Future<void> tearDownAll() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    PlaylistRepository.mergeAllPlaylists = false;
    AppPlatform.isZuno = false;
  }
}
