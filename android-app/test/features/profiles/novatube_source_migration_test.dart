// Régression de la vraie migration SQLite v7 → v9. Aucun serveur contacté.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/playlists/data/deleted_sources.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v7 conserve toutes les anciennes données dans Profil 1, même au-delà de dix sources', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final Directory directory =
        await Directory.systemTemp.createTemp('novatube-v7-');
    final String path = '${directory.path}/legacy.db';
    PlaylistDatabase.debugFilePath = path;
    PlaylistRepository.mergeAllPlaylists = true;
    FlavorConfig.setCurrent(FlavorConfig.novatube);
    addTearDown(() async {
      await PlaylistRepository.instance.reloadForActiveProfile();
      await PlaylistDatabase.instance.closeForTesting();
      PlaylistDatabase.debugFilePath = null;
      await directory.delete(recursive: true);
    });

    final Database legacy = await openDatabase(path, version: 7,
        onCreate: (Database db, int _) async {
      await db.execute('''
        CREATE TABLE playlists (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, type TEXT NOT NULL, m3u_url TEXT,
          xtream_server TEXT, xtream_username TEXT, xtream_password TEXT,
          epg_url TEXT, created_at INTEGER NOT NULL, last_synced_at INTEGER,
          channel_count INTEGER NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 0,
          hidden INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE channels (
          local_id INTEGER PRIMARY KEY AUTOINCREMENT,
          playlist_id INTEGER NOT NULL, external_id TEXT NOT NULL,
          name TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'Autres',
          stream_url TEXT NOT NULL, logo_url TEXT,
          is_live INTEGER NOT NULL DEFAULT 1,
          catchup_supported INTEGER NOT NULL DEFAULT 0,
          catchup_days INTEGER, catchup_source TEXT, http_headers TEXT,
          FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE TABLE deleted_sources (fingerprint TEXT PRIMARY KEY)');
      await db.execute('CREATE TABLE favorites (channel_id TEXT PRIMARY KEY)');
      await db.execute('''
        CREATE TABLE epg_programs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          channel_id TEXT NOT NULL, start_time INTEGER NOT NULL,
          stop_time INTEGER NOT NULL, title TEXT NOT NULL,
          description TEXT, category TEXT, icon_url TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE downloads (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, source_url TEXT NOT NULL,
          file_path TEXT NOT NULL, status TEXT NOT NULL,
          received_bytes INTEGER NOT NULL DEFAULT 0,
          total_bytes INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, poster_url TEXT
        )
      ''');
      // La limite actuelle ne supprime aucune donnée déjà installée.
      for (int i = 1; i <= 11; i++) {
        await db.insert('playlists', <String, Object>{
          'id': i, 'name': 'Ancienne $i', 'type': 'm3u',
          'm3u_url': 'https://example.invalid/legacy-$i.m3u',
          'created_at': i, 'last_synced_at': i,
          'channel_count': 1, 'is_active': i == 1 ? 1 : 0,
        });
        await db.insert('channels', <String, Object>{
          'playlist_id': i, 'external_id': 'legacy-$i',
          'name': 'Documentaire $i', 'category': 'Documentaires',
          'stream_url': 'https://example.invalid/legacy-$i.ts',
        });
      }
      await db.insert('favorites', <String, Object>{'channel_id': 'legacy-1'});
      await db.insert('deleted_sources',
          <String, Object>{'fingerprint': 'legacy-fingerprint'});
      final int now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('epg_programs', <String, Object>{
        'channel_id': 'legacy-1', 'start_time': now - 60000,
        'stop_time': now + 3600000, 'title': 'Guide conservé',
      });
      await db.insert('downloads', <String, Object>{
        'id': 'legacy-download', 'name': 'Documentaire conservé',
        'source_url': 'https://example.invalid/legacy.mp4',
        'file_path': '${directory.path}/legacy.mp4',
        'status': 'completed', 'created_at': now,
      });
    });
    await legacy.close();

    ProfileCatalog catalog = ProfileCatalog.fresh(nowMs: 1)
        .add(name: 'Autre', isKids: false, nowMs: 2)!;
    final String other = catalog.profiles.last.id;
    catalog = catalog.activate(other)!;
    SharedPreferences.setMockInitialValues(<String, Object>{
      ProfileKeys.catalog: catalog.encode(),
    });
    final ProfileRepository profiles = ProfileRepository.instance;
    final PlaylistRepository sources = PlaylistRepository.instance;
    await profiles.load();
    await EpgRepository.instance.initialize();
    expect(profiles.active.id, other);
    expect(sources.currentPlaylists, isEmpty);
    expect(sources.currentChannels, isEmpty);
    expect(FavoritesRepository.instance.current, isEmpty);
    expect(await DeletedSources.read(), isEmpty);
    expect(await EpgRepository.instance.currentProgram('legacy-1'), isNull);

    final Database db = await PlaylistDatabase.instance.database;
    expect(await db.getVersion(), 9);
    final List<Map<String, Object?>> rows = await db.query('playlists');
    expect(rows, hasLength(11));
    expect(rows.every((Map<String, Object?> row) =>
        row['profile_id'] == ProfileIds.origin && row['scoped_channel_ids'] == 0), isTrue);
    final Map<String, Object?> download = (await db.query('downloads')).single;
    expect(download['profile_id'], ProfileIds.origin);
    expect(download['category'], '');
    expect(download['declared_adult'], 0);
    expect((await db.query('channels')).every((Map<String, Object?> row) =>
        row['declared_adult'] == 0), isTrue);
    expect(download['name'], 'Documentaire conservé');

    await profiles.activate(ProfileIds.origin, leaveAllowed: true);
    expect(sources.currentPlaylists, hasLength(11));
    expect(sources.currentChannels, hasLength(11));
    expect(sources.currentPlaylists.every((Playlist p) => !p.scopedChannelIds), isTrue);
    expect(sources.currentChannels.first.id, 'legacy-1');
    expect(sources.currentPlaylists.firstWhere((Playlist p) => p.id == 1).m3uUrl,
        'https://example.invalid/legacy-1.m3u');
    expect(await sources.canAddSource(), isFalse);
    expect(FavoritesRepository.instance.current, <String>{'legacy-1'});
    expect(await DeletedSources.read(), <String>{'legacy-fingerprint'});
    expect((await EpgRepository.instance.currentProgram('legacy-1'))!.title, 'Guide conservé');

    await profiles.activate(other, leaveAllowed: true);
    expect(sources.currentPlaylists, isEmpty);
    expect(await sources.canAddSource(), isTrue);
    expect(FavoritesRepository.instance.current, isEmpty);
  });
}
