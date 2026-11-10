// Profils de listes : migration douce, affectation au bon propriétaire et
// filtrage SQLite sans perdre les identités de chaînes ni dépasser le cache.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';

ProfileCatalog _catalog(
        {String active = 'p1',
        List<int> a = const <int>[],
        List<int> b = const <int>[]}) =>
    ProfileCatalog(
      profiles: <FamilyProfile>[
        FamilyProfile.origin(),
        FamilyProfile(
            id: 'a',
            name: 'A',
            avatar: 1,
            isKids: false,
            createdAtMs: 1,
            playlistIds: a),
        FamilyProfile(
            id: 'b',
            name: 'B',
            avatar: 2,
            isKids: false,
            createdAtMs: 2,
            playlistIds: b),
      ],
      activeId: active,
      askOnStartup: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database db;
  final PlaylistRepository lists = PlaylistRepository.instance;
  final ProfileRepository profiles = ProfileRepository.instance;

  setUpAll(() async {
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('zuno-profile-lists-');
    PlaylistDatabase.debugFilePath = '${directory.path}/fixture.db';
    db = await PlaylistDatabase.instance.database;
    PlaylistRepository.mergeAllPlaylists = true;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await db.delete('channels');
    await db.delete('playlists');
    profiles.resetForTesting(_catalog());
    await lists.initialize();
  });

  tearDownAll(() async {
    profiles.resetForTesting(ProfileCatalog.fresh());
    await lists.initialize();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    PlaylistRepository.mergeAllPlaylists = false;
    await directory.delete(recursive: true);
  });

  Future<int> source(String name, {bool hidden = false}) =>
      db.insert('playlists', <String, Object?>{
        'name': name,
        'type': 'm3u',
        'created_at': 1,
        'is_active': 1,
        'hidden': hidden ? 1 : 0,
        'channel_count': 1
      });

  Future<void> channel(int sourceId, String id) async {
    await db.insert('channels', <String, Object?>{
      'playlist_id': sourceId,
      'external_id': id,
      'name': id,
      'category': 'Fixture',
      'stream_url': 'https://fixture.invalid/$sourceId/$id',
      'is_live': 1,
    });
  }

  test('ancien JSON partagé ; nouveau profil vide ; sérialisation distincte',
      () {
    final ProfileCatalog old =
        ProfileCatalog.decode(jsonEncode(<String, Object?>{
      'activeId': 'old',
      'profiles': <Object>[
        FamilyProfile.origin().toJson(),
        <String, Object?>{'id': 'old', 'name': 'Avant', 'avatar': 1},
      ],
    }));
    expect(old.active.playlistIds, isNull);
    final ProfileCatalog added =
        old.add(name: 'Après', isKids: false, nowMs: 4)!;
    expect(added.profiles.last.playlistIds, isEmpty);
    final ProfileCatalog restored = ProfileCatalog.decode(added.encode());
    expect(restored.byId('old')!.playlistIds, isNull);
    expect(restored.profiles.last.playlistIds, isEmpty);
    expect(ProfileKeys.pin('p1'), 'security.app_pin_value');
    expect(ProfileKeys.watchProgress('p1'), 'cinema.progress.v1');
  });

  test(
      'liaison idempotente et sélection corrompue ne révèle pas toutes les listes',
      () {
    final ProfileCatalog c = _catalog();
    final ProfileCatalog attached = c.attachPlaylist('a', 17)!;
    expect(attached.byId('a')!.playlistIds, <int>[17]);
    expect(identical(attached.attachPlaylist('a', 17), attached), isTrue);
    expect(attached.attachPlaylist('missing', 18), isNull);
    expect(attached.attachPlaylist('a', 0), isNull);
    expect(attached.attachPlaylist('p1', 17)!.active.playlistIds, isNull);
    final FamilyProfile invalid = FamilyProfile.fromJson(<String, Object?>{
      'id': 'bad',
      'name': 'Bad',
      'playlistIds': 'malformed',
    })!;
    expect(invalid.playlistIds, isEmpty);
    final FamilyProfile normalized = FamilyProfile.fromJson(<String, Object?>{
      'id': 'ok',
      'playlistIds': <Object>[17, 17, -1, 1.5, '18'],
    })!;
    expect(normalized.playlistIds, <int>[17]);
  });

  test('résultat tardif appartient au profil capturé, même après changement',
      () async {
    profiles.resetForTesting(_catalog(active: 'a'));
    final String owner = ActiveProfile.instance.id;
    await profiles.activate('b', leaveAllowed: true);
    expect(await profiles.attachPlaylist(owner, 31), isTrue);
    expect(ActiveProfile.instance.id, 'b');
    expect(profiles.profileById('a')!.playlistIds, <int>[31]);
    expect(profiles.active.playlistIds, isEmpty);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProfileCatalog saved =
        ProfileCatalog.decode(prefs.getString(ProfileKeys.catalog));
    expect(saved.byId('a')!.playlistIds, <int>[31]);
    expect(saved.activeId, 'b');
    profiles.resetForTesting(_catalog().remove('a')!);
    expect(await profiles.attachPlaylist(owner, 32), isFalse);
    expect(profiles.profileById(owner), isNull);
  });

  test(
      'même profil reçoit sa liste : signal de portée sans faux changement identité',
      () async {
    profiles.resetForTesting(_catalog(active: 'a'));
    int identity = 0;
    int scope = 0;
    void onIdentity() => identity++;
    void onScope() => scope++;
    ActiveProfile.instance.listenable.addListener(onIdentity);
    ActiveProfile.instance.scopeListenable.addListener(onScope);
    addTearDown(() {
      ActiveProfile.instance.listenable.removeListener(onIdentity);
      ActiveProfile.instance.scopeListenable.removeListener(onScope);
    });
    expect(await profiles.attachPlaylist('a', 23), isTrue);
    expect(ActiveProfile.instance.playlistIds, <int>[23]);
    expect(ActiveProfile.instance.allowsPlaylist(23), isTrue);
    expect(ActiveProfile.instance.allowsPlaylist(24), isFalse);
    expect(ActiveProfile.instance.allowsPlaylist(null), isFalse);
    expect(identity, 0);
    expect(scope, 1);
    expect(await profiles.attachPlaylist('a', 23), isTrue);
    expect(scope, 1);
    await lists.initialize();
  });

  test(
      'vue profil isolée ; inventaire panel intact ; aucune mutation activation',
      () async {
    final int a = await source('A');
    final int b = await source('B');
    await channel(a, 'a-only');
    await channel(b, 'b-only');
    final before = await db
        .query('playlists', columns: <String>['id', 'is_active', 'hidden']);
    profiles.resetForTesting(_catalog(active: 'a', a: <int>[a], b: <int>[b]));
    await lists.initialize();
    expect(lists.currentChannels.map((c) => c.id), <String>['a-only']);
    expect(lists.currentPlaylists.map((p) => p.id), <int>[a]);
    expect(await lists.getAllPlaylists(), hasLength(2));
    expect(lists.currentDevicePlaylists, hasLength(2));
    expect(lists.hasDeviceChannels, isTrue);
    await profiles.activate('b', leaveAllowed: true);
    expect(lists.currentChannels, isEmpty,
        reason: 'ancien écran retiré immédiatement');
    await lists.initialize();
    expect((await lists.getAllChannels()).map((c) => c.id), <String>['b-only']);
    expect((await lists.getVisiblePlaylists()).map((p) => p.id), <int>[b]);
    expect(
        await db
            .query('playlists', columns: <String>['id', 'is_active', 'hidden']),
        before);
  });

  test('profil sans liste ne retombe jamais sur toutes les chaînes', () async {
    final int a = await source('A');
    await channel(a, 'visible-for-origin');
    profiles.resetForTesting(_catalog(active: 'a'));
    await lists.initialize();
    expect(lists.currentChannels, isEmpty);
    expect(await lists.getAllChannels(), isEmpty);
    expect(lists.currentPlaylists, isEmpty);
    expect(lists.hasDeviceChannels, isTrue);
    await profiles.activate('p1', leaveAllowed: true);
    await lists.initialize();
    expect(lists.currentChannels.single.id, 'visible-for-origin');
  });

  test('lecture SQL déjà partie ne publie pas le profil quitté', () async {
    final int a = await source('A');
    final int b = await source('B');
    await channel(a, 'old-profile');
    await channel(b, 'new-profile');
    profiles.resetForTesting(_catalog(active: 'a', a: <int>[a], b: <int>[b]));
    await lists.initialize();
    final Completer<void> locked = Completer<void>();
    final Completer<void> release = Completer<void>();
    final Future<void> blocker = db.transaction((Transaction txn) async {
      await txn.rawQuery('SELECT 1');
      locked.complete();
      await release.future;
    });
    await locked.future;
    final oldRead = lists.getAllChannels();
    await pumpEventQueue();
    await profiles.activate('b', leaveAllowed: true);
    expect(lists.currentChannels, isEmpty);
    release.complete();
    await blocker;
    expect(await oldRead, isEmpty);
    await lists.initialize();
    expect(lists.currentChannels.single.id, 'new-profile');
  });

  test('doublon garde son suffixe global après filtrage, favoris stables',
      () async {
    final int a = await source('A');
    final int b = await source('B');
    await channel(a, 'xtream-42');
    await channel(b, 'xtream-42');
    await lists.initialize();
    expect(lists.currentChannels.map((c) => c.id),
        <String>['xtream-42', 'xtream-42~p$b']);
    profiles.resetForTesting(_catalog(active: 'b', b: <int>[b]));
    await lists.initialize();
    expect(lists.currentChannels.single.id, 'xtream-42~p$b');
    expect(lists.currentChannels.single.playlistId, b);
  });

  test('liste après 50 000 chaînes reste accessible sans relever le plafond',
      () async {
    final int a = await source('Grande');
    final int b = await source('Après');
    await db.rawInsert('''
      WITH RECURSIVE seq(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM seq WHERE n<50000)
      INSERT INTO channels(playlist_id,external_id,name,stream_url)
      SELECT ?, 'bulk-' || n, 'Fixture ' || n, 'https://fixture.invalid/' || n FROM seq
    ''', <Object>[a]);
    await channel(b, 'after-the-cap');
    profiles.resetForTesting(_catalog(active: 'b', b: <int>[b]));
    await lists.initialize();
    expect(lists.currentChannels.map((c) => c.id), <String>['after-the-cap']);
    expect(lists.hasDeviceChannels, isTrue);
    expect(PlaylistRepository.kMaxInMemoryChannels, 50000);
  });

  test(
      'détacher est local au profil et reset invalide le bool appareil immédiatement',
      () async {
    final int a = await source('Partagée');
    await channel(a, 'shared');
    profiles.resetForTesting(_catalog(active: 'a', a: <int>[a], b: <int>[a]));
    await lists.initialize();
    expect(await profiles.detachPlaylist('a', a), isTrue);
    await lists.initialize();
    expect(lists.currentChannels, isEmpty);
    expect(profiles.profileById('b')!.playlistIds, <int>[a]);
    expect(await lists.getAllPlaylists(), hasLength(1));
    expect(await db.query('deleted_sources'), isEmpty);
    expect(lists.hasDeviceChannels, isTrue);
    lists.cancelPendingImports();
    expect(lists.hasDeviceChannels, isFalse);
    expect(lists.currentDevicePlaylists, isEmpty);
  });
}
