import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/data/recently_watched_repository.dart';
import 'package:tv_king/features/playlists/data/deleted_sources.dart';
import 'package:tv_king/features/playlists/data/favorites_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';

Future<Playlist> _source(String name) async {
  final Database db = await PlaylistDatabase.instance.database;
  final Playlist source = Playlist(id: null, name: name,
    type: PlaylistType.m3u, m3uUrl: 'http://$name.invalid/list.m3u',
    createdAt: 1, isActive: true);
  return source.copyWith(id: await db.insert('playlists', source.toMap()));
}

Future<void> _channel(Playlist source, String id) async {
  final Database db = await PlaylistDatabase.instance.database;
  await db.insert('channels', <String, Object?>{
    'playlist_id': source.id, 'external_id': id, 'name': id,
    'stream_url': 'http://stream.invalid/$id.ts',
  });
}

Future<void> _legacyReferences(List<String> ids) async {
  final Database db = await PlaylistDatabase.instance.database;
  await db.execute('CREATE TABLE favorites (channel_id TEXT PRIMARY KEY)');
  await db.execute('CREATE TABLE recently_watched '
    '(channel_id TEXT PRIMARY KEY, last_watched_at INTEGER NOT NULL)');
  for (final String id in ids) {
    await db.insert('favorites', <String, Object?>{'channel_id': id});
    await db.insert('recently_watched', <String, Object?>{
      'channel_id': id, 'last_watched_at': 1,
    });
  }
}

Future<void> _scopedReferences(List<String> ids) async {
  final Database db = await PlaylistDatabase.instance.database;
  await db.execute('CREATE TABLE favorites_by_profile '
    '(profile_id TEXT NOT NULL, channel_id TEXT NOT NULL, '
    'PRIMARY KEY (profile_id, channel_id))');
  await db.execute('CREATE TABLE recently_watched_by_profile '
    '(profile_id TEXT NOT NULL, channel_id TEXT NOT NULL, '
    'last_watched_at INTEGER NOT NULL, PRIMARY KEY (profile_id, channel_id))');
  for (final String profile in <String>[ProfileIds.origin, 'p2']) {
    for (final String id in ids) {
      await db.insert('favorites_by_profile', <String, Object?>{
        'profile_id': profile, 'channel_id': id,
      });
      await db.insert('recently_watched_by_profile', <String, Object?>{
        'profile_id': profile, 'channel_id': id, 'last_watched_at': 1,
      });
    }
  }
}

Future<Set<String>> _ids(String table) async {
  final Database db = await PlaylistDatabase.instance.database;
  return (await db.query(table, columns: <String>['channel_id']))
    .map((Map<String, Object?> row) => row['channel_id'] as String).toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:AA:BB:CC:DD:EE',
    });
    dir = await Directory.systemTemp.createTemp('zuno-delete-cleanup-');
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
    PlaylistRepository.mergeAllPlaylists = true;
    await PlaylistRepository.instance.initialize();
  });

  tearDown(() async {
    FavoritesRepository.instance.debugBeforeCachePublication = null;
    RecentlyWatchedRepository.instance.debugBeforeCachePublication = null;
    await PlaylistDatabase.instance.closeForTesting();
    await dir.delete(recursive: true);
  });

  test('premier retrait : aucune migration inutile de favoris ou historique', () async {
    final Playlist source = await _source('a');
    await _channel(source, 'gone');
    await PlaylistRepository.instance.initialize();
    await RemoteSourceRepository.applyRevocations(SourceFingerprint.ofPlaylist(source));
    final Database db = await PlaylistDatabase.instance.database;
    expect(await db.query('channels'), isEmpty);
    expect(await db.query('playlists'), isEmpty);
    expect(await db.query('deleted_sources'), isNotEmpty);
    final List<Map<String, Object?>> tables = await db.query('sqlite_master',
      columns: <String>['name'], where: 'name IN (?, ?, ?, ?)',
      whereArgs: <String>['favorites', 'favorites_by_profile',
        'recently_watched', 'recently_watched_by_profile']);
    expect(tables, isEmpty, reason: 'une fonction jamais utilisée ne migre pas pendant le retrait');
    await FavoritesRepository.instance.initialize();
    await RecentlyWatchedRepository.instance.initialize();
    expect(FavoritesRepository.instance.current, isEmpty);
    expect(RecentlyWatchedRepository.instance.current, isEmpty);
  });

  test('avant migration : le retrait dans les tables anciennes survit à la migration', () async {
    await _legacyReferences(<String>['gone', 'keep']);
    await Future.wait<void>(<Future<void>>[
      FavoritesRepository.instance.forgetChannels(<String>['gone']),
      RecentlyWatchedRepository.instance.forgetChannels(<String>['gone']),
    ]);
    expect(await _ids('favorites'), <String>{'keep'});
    expect(await _ids('recently_watched'), <String>{'keep'});
    await FavoritesRepository.instance.initialize();
    await RecentlyWatchedRepository.instance.initialize();
    expect(FavoritesRepository.instance.current, <String>{'keep'});
    expect(RecentlyWatchedRepository.instance.current, <String>['keep']);
  });

  test('tous les profils sont nettoyés, les autres chaînes restent en cache et sur disque', () async {
    await _legacyReferences(<String>['gone', 'keep']);
    await _scopedReferences(<String>['gone', 'keep']);
    await FavoritesRepository.instance.initialize();
    await RecentlyWatchedRepository.instance.initialize();
    await Future.wait<void>(<Future<void>>[
      FavoritesRepository.instance.forgetChannels(<String>['gone']),
      RecentlyWatchedRepository.instance.forgetChannels(<String>['gone']),
    ]);
    for (final String table in <String>['favorites', 'favorites_by_profile',
        'recently_watched', 'recently_watched_by_profile']) {
      expect(await _ids(table), <String>{'keep'}, reason: table);
    }
    final Database db = await PlaylistDatabase.instance.database;
    expect(await db.query('favorites_by_profile'), hasLength(2));
    expect(await db.query('recently_watched_by_profile'), hasLength(2));
    expect(FavoritesRepository.instance.current, <String>{'keep'});
    expect(RecentlyWatchedRepository.instance.current, <String>['keep']);
  });

  test('une ancienne lecture retardée ne republie ni favori ni historique supprimé', () async {
    await _legacyReferences(<String>['gone', 'keep']);
    await FavoritesRepository.instance.initialize();
    await RecentlyWatchedRepository.instance.initialize();
    final Completer<void> favoriteRead = Completer<void>();
    final Completer<void> historyRead = Completer<void>();
    final Completer<void> release = Completer<void>();
    FavoritesRepository.instance.debugBeforeCachePublication = () async {
      if (!favoriteRead.isCompleted) {
        favoriteRead.complete();
        await release.future;
      }
    };
    RecentlyWatchedRepository.instance.debugBeforeCachePublication = () async {
      if (!historyRead.isCompleted) {
        historyRead.complete();
        await release.future;
      }
    };
    final Future<void> favoriteWork = FavoritesRepository.instance.toggle('added');
    final Future<void> historyWork = RecentlyWatchedRepository.instance.record('added');
    try {
      await Future.wait<void>(<Future<void>>[favoriteRead.future, historyRead.future]);
      await Future.wait<void>(<Future<void>>[
        FavoritesRepository.instance.forgetChannels(<String>['gone']),
        RecentlyWatchedRepository.instance.forgetChannels(<String>['gone']),
      ]);
      expect(FavoritesRepository.instance.current, <String>{'keep', 'added'});
      expect(RecentlyWatchedRepository.instance.current, isNot(contains('gone')));
    } finally {
      release.complete();
      await Future.wait<void>(<Future<void>>[favoriteWork, historyWork]);
    }
    expect(FavoritesRepository.instance.current, <String>{'keep', 'added'});
    expect(RecentlyWatchedRepository.instance.current.toSet(), <String>{'keep', 'added'});
  });

  test('un identifiant encore servi par une autre liste conserve ses références', () async {
    final Playlist first = await _source('a');
    final Playlist second = await _source('b');
    await _channel(first, 'shared');
    await _channel(first, 'only-a');
    await _channel(second, 'shared');
    await _channel(second, 'only-b');
    final List<String> ids = <String>['shared', 'only-a', 'only-b'];
    await _legacyReferences(ids);
    await _scopedReferences(ids);
    final Database db = await PlaylistDatabase.instance.database;
    for (final String id in ids) {
      await db.insert('watch_sessions', <String, Object?>{'channel_id': id, 'started_at': 1});
    }
    await PlaylistRepository.instance.initialize();
    await RemoteSourceRepository.applyRevocations(SourceFingerprint.ofPlaylist(first));
    for (final String table in <String>['favorites', 'favorites_by_profile',
        'recently_watched', 'recently_watched_by_profile', 'watch_sessions']) {
      expect(await _ids(table), <String>{'shared', 'only-b'}, reason: table);
    }
    await PlaylistDatabase.instance.closeForTesting();
    await PlaylistRepository.instance.initialize();
    expect((await PlaylistRepository.instance.getAllPlaylists()).single.id, second.id);
    expect(PlaylistRepository.instance.currentChannels.map((c) => c.id).toSet(),
      <String>{'shared', 'only-b'});
    expect(await _ids('favorites'), <String>{'shared', 'only-b'});
  });

  test('un ID redevenu disponible avant le DELETE reste favori et récent', () async {
    await _legacyReferences(<String>['returned', 'gone']);
    await _scopedReferences(<String>['returned', 'gone']);
    // La prélecture du synchroniseur avait classé ces deux IDs absents,
    // mais un import concurrent vient de republier « returned ».
    final Playlist source = await _source('returned');
    await _channel(source, 'returned');
    await Future.wait<void>(<Future<void>>[
      FavoritesRepository.instance.forgetChannels(
        <String>['returned', 'gone'], onlyUnreferenced: true),
      RecentlyWatchedRepository.instance.forgetChannels(
        <String>['returned', 'gone'], onlyUnreferenced: true),
    ]);
    for (final String table in <String>['favorites', 'favorites_by_profile',
        'recently_watched', 'recently_watched_by_profile']) {
      expect(await _ids(table), <String>{'returned'}, reason: table);
    }
  });

  test('objet UI encore affiché : une ligne absente et un serveur coupé gardent le refus', () async {
    final Playlist source = await _source('late');
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('playlists', where: 'id = ?', whereArgs: <Object>[source.id!]);
    final http.Client offline = MockClient((_) async {
      throw const SocketException('serveur de recette indisponible');
    });
    try {
      expect(await RemoteSourceRepository.deleteFromTv(source, client: offline), isTrue);
    } finally {
      offline.close();
    }
    final List<String> expected = await DeletedSources.hashes(SourceFingerprint.ofPlaylist(source));
    await PlaylistDatabase.instance.closeForTesting();
    expect(await DeletedSources.read(), containsAll(expected));
    int downloads = 0;
    final http.Client stale = MockClient((http.Request request) async {
      if (request.url.path.startsWith('/api/device-source/')) {
        return http.Response(jsonEncode(<String, Object>{'sources': <Object>[
          <String, Object>{'type': 'm3u', 'm3u_url': source.m3uUrl!},
        ]}), 200);
      }
      if (request.url.host == 'late.invalid') downloads++;
      return http.Response('{}', 404);
    });
    try {
      await http.runWithClient(() => RemoteSourceRepository.sync(force: true), () => stale);
      expect(downloads, 0, reason: 'une ancienne réponse ne retélécharge pas la source refusée');
      expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
    } finally {
      stale.close();
    }
  });

  test('un retrait par alias M3U mémorise aussi le compte Xtream après redémarrage', () async {
    const String link = 'http://source.invalid:80/get.php?username=user&password=test&type=m3u_plus';
    const Playlist source = Playlist(id: null, name: 'Compte',
      type: PlaylistType.xtream, createdAt: 1, m3uUrl: link,
      xtreamServer: 'http://source.invalid:80', xtreamUsername: 'user', xtreamPassword: 'test');
    final Database db = await PlaylistDatabase.instance.database;
    await db.insert('playlists', source.toMap());
    await RemoteSourceRepository.applyRevocations(<String>[SourceFingerprint.m3u(link)!]);
    final List<String> expected = await DeletedSources.hashes(SourceFingerprint.ofPlaylist(source));
    expect(expected.length, greaterThan(1));
    await PlaylistDatabase.instance.closeForTesting();
    expect(await DeletedSources.read(), containsAll(expected));
    expect(await PlaylistRepository.instance.getAllPlaylists(), isEmpty);
  });
}
