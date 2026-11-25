// Vrai parcours import/refresh, SQLite FFI et HTTP simulé : les insertions
// groupées doivent conserver les données et l'ancien catalogue en cas d'erreur.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';

String _catalogue(int count, {String tag = 'initial'}) {
  final StringBuffer body = StringBuffer('#EXTM3U\r\n');
  for (int i = 0; i < count; i++) {
    final String optional = i.isEven
        ? 'tvg-logo="http://127.0.0.1/logo/$i.png" catchup="default" '
            'catchup-days="7" catchup-source="http://127.0.0.1/replay/$i" '
        : '';
    body
      ..writeln('#EXTINF:-1 tvg-id="$tag-$i" $optional'
          'group-title="L’actualité",Écran d\'été 日本 $i')
      ..writeln('http://127.0.0.1/$tag/$i.ts?token=a\'b&x=1');
  }
  return body.toString();
}

MockClient _client(String body) => MockClient(
      (_) async => http.Response.bytes(utf8.encode(body), 200),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final PlaylistRepository repo = PlaylistRepository.instance;
  late Directory dir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    PlaylistRepository.mergeAllPlaylists = true;
    dir = await Directory.systemTemp.createTemp('zuno-import-bulk-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    db = await PlaylistDatabase.instance.database;
  });

  setUp(() async {
    RepairFlags.debugReset();
    ImportProgressBus.clear();
    await db.execute('DROP TRIGGER IF EXISTS reject_new_catalogue');
    await db.delete('playlists');
    await repo.initialize();
  });

  tearDownAll(() async {
    RepairFlags.debugReset();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await dir.delete(recursive: true);
  });

  Future<Playlist> add(int count) => repo.addM3uPlaylist(
        name: 'Catalogue de test',
        url: 'http://127.0.0.1/catalogue.m3u',
        httpClient: _client(_catalogue(count)),
      );

  test('2213 chaînes : ordre, Unicode, apostrophes et champs nullable intacts',
      () async {
    final Playlist saved = await add(2213);
    final List<Map<String, Object?>> rows = await db.query(
      'channels',
      where: 'playlist_id = ?',
      whereArgs: <Object>[saved.id!],
      orderBy: 'local_id',
    );
    expect(rows, hasLength(2213));
    // Vérifie toutes les frontières de lot, et pas seulement la première ligne.
    for (int i = 0; i < rows.length; i++) {
      final Map<String, Object?> row = rows[i];
      expect(row['external_id'], 'initial-$i');
      expect(row['name'], 'Écran d\'été 日本 $i');
      expect(row['category'], 'L’actualité');
      expect(row['stream_url'], "http://127.0.0.1/initial/$i.ts?token=a'b&x=1");
      expect(row['is_live'], 1);
      expect(row['logo_url'], i.isEven ? 'http://127.0.0.1/logo/$i.png' : null);
      expect(row['catchup_supported'], i.isEven ? 1 : 0);
      expect(row['catchup_days'], i.isEven ? 7 : null);
      expect(row['catchup_source'],
          i.isEven ? 'http://127.0.0.1/replay/$i' : null);
    }
    expect(saved.channelCount, 2213);
    expect(repo.currentChannels, hasLength(2213));
    expect(ImportProgressBus.current.value?.stage, ImportStage.done);
    expect(ImportProgressBus.current.value?.count, 2213);
  });

  test('refresh interrompu après 1000 insertions : ancien catalogue intact',
      () async {
    final Playlist saved = await add(137);
    final List<Map<String, Object?>> before = await db.query('channels');
    // L'échec survient dans le deuxième lot : le premier est lui aussi annulé.
    await db.execute('''
      CREATE TRIGGER reject_new_catalogue BEFORE INSERT ON channels
      WHEN NEW.external_id = 'nouveau-1101'
      BEGIN SELECT RAISE(ABORT, 'test catalogue interrompu'); END
    ''');
    await expectLater(
      http.runWithClient(
        () => repo.refreshPlaylist(saved),
        () => _client(_catalogue(2213, tag: 'nouveau')),
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('channels'), before);
    expect(repo.currentChannels, hasLength(137));
    final Playlist current = (await repo.getAllPlaylists()).single;
    expect(current.channelCount, saved.channelCount);
    expect(current.lastSyncedAt, saved.lastSyncedAt);
    expect(ImportProgressBus.current.value?.stage, isNot(ImportStage.done));
  });

  test('refreshStale ignore les listes cachées et les ajouts en cours',
      () async {
    final Playlist saved = await add(1);
    await db.update(
        'playlists',
        <String, Object?>{
          'hidden': 1,
          'last_synced_at': 1,
        },
        where: 'id = ?',
        whereArgs: <Object>[saved.id!]);
    await db.insert('playlists', <String, Object?>{
      'name': 'Ajout en cours',
      'type': 'm3u',
      'm3u_url': 'http://127.0.0.1/pending.m3u',
      'created_at': 1,
    });
    int requests = 0;
    final int refreshed = await http.runWithClient(
      () => repo.refreshStale(),
      () => MockClient((_) async {
        requests++;
        return http.Response.bytes(utf8.encode(_catalogue(2)), 200);
      }),
    );
    expect(requests, 0, reason: 'aucun téléchargement concurrent inutile');
    expect(refreshed, 0);
    expect(await db.query('playlists'), hasLength(2));
  });
}
