// Suppressions réelles : le signal de portée suit le COMMIT SQLite et ferme
// les autorisations déjà ouvertes comme les réponses d'authentification tardives.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/cast/data/cast_platform.dart';
import 'package:tv_king/features/playlists/data/box_reset.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/security/data/adult_access.dart';
import 'package:tv_king/features/security/data/app_pin_settings.dart';
import 'package:tv_king/features/security/data/parental_controls.dart';

ProfileCatalog _catalog({required int a, required int b}) => ProfileCatalog(
      profiles: <FamilyProfile>[
        FamilyProfile.origin(),
        FamilyProfile(
          id: 'a',
          name: 'A',
          avatar: 1,
          isKids: false,
          createdAtMs: 1,
          playlistIds: <int>[a],
        ),
        FamilyProfile(
          id: 'b',
          name: 'B',
          avatar: 2,
          isKids: false,
          createdAtMs: 2,
          playlistIds: <int>[b],
        ),
      ],
      activeId: 'a',
      askOnStartup: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lists = PlaylistRepository.instance;
  final profiles = ProfileRepository.instance;
  const capability = MethodChannel('com.sevenmotion.zuno/cast-capability');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    PlaylistDatabase.debugFilePath = inMemoryDatabasePath;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    PlaylistRepository.mergeAllPlaylists = true;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = await PlaylistDatabase.instance.database;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RepairFlags.debugReset();
    await db.execute('DROP TRIGGER IF EXISTS refuse_delete');
    await db.delete('channels');
    await db.delete('playlists');
    await db.delete('deleted_sources');
    profiles.resetForTesting(ProfileCatalog.fresh());
    await ParentalControls.instance.load();
    await AppPinSettings.instance.setPin('3718');
    await lists.initialize();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(capability, (_) async => false);
    await CastPlatform.initializeZuno();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(capability, null);
    debugDefaultTargetPlatformOverride = null;
  });

  tearDownAll(() async {
    RepairFlags.debugReset();
    await db.execute('DROP TRIGGER IF EXISTS refuse_delete');
    await lists.initialize();
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    PlaylistRepository.mergeAllPlaylists = false;
  });

  Future<int> source(String name) async {
    final id = await db.insert('playlists', <String, Object?>{
      'name': name,
      'type': 'm3u',
      'm3u_url': 'http://127.0.0.1/$name.m3u',
      'created_at': 1,
      'is_active': 1,
      'channel_count': 1,
    });
    await db.insert('channels', <String, Object?>{
      'playlist_id': id,
      'external_id': 'fixture-$id',
      'name': 'Fixture $id',
      'category': 'Adultes',
      'stream_url': 'http://127.0.0.1/fixture-$id.ts',
      'is_live': 1,
    });
    await lists.initialize();
    return id;
  }

  Future<AdultAccessGrant> grant() async {
    await AppPinSettings.instance.setPin('3718');
    final access = await authenticateAdultAccess(
      reason: 'Fixture suppression',
      confirmPin: () => AppPinSettings.instance.verify('3718'),
    );
    expect(access, isNotNull);
    final result = access!;
    addTearDown(result.dispose);
    return result;
  }

  test('DELETE réel du profil partagé révoque sans changer son identité',
      () async {
    final removed = await source('removed');
    final kept = await source('kept');
    final access = await grant();
    var revoked = 0;
    access.addListener(() => revoked++);
    final scope = ActiveProfile.instance.scopeListenable.value;

    await lists.deletePlaylist(removed);

    expect(
        await db
            .query('playlists', where: 'id = ?', whereArgs: <Object>[removed]),
        isEmpty);
    expect(ActiveProfile.instance.id, 'p1');
    expect(ActiveProfile.instance.playlistIds, isNull);
    expect(ActiveProfile.instance.scopeListenable.value, scope + 1);
    expect(access.isValid, isFalse);
    expect(revoked, 1);
    expect(lists.currentChannels.map((c) => c.playlistId), <int>[kept]);
    expect(
        (await lists.getAllChannels()).map((c) => c.playlistId), <int>[kept]);
  });

  test('rollback SQL ne signale pas une suppression réussie ni APPLIED',
      () async {
    final id = await source('rollback');
    final access = await grant();
    final scope = ActiveProfile.instance.scopeListenable.value;
    await db.execute('''
      CREATE TRIGGER refuse_delete BEFORE DELETE ON playlists
      BEGIN SELECT RAISE(ABORT, 'fixture deletion refused'); END
    ''');

    await expectLater(
        BoxReset.maybeApply(100, strict: true), throwsA(anything));

    expect(
        await db.query('playlists', where: 'id = ?', whereArgs: <Object>[id]),
        hasLength(1));
    expect(await db.query('channels'), hasLength(1));
    expect(ActiveProfile.instance.scopeListenable.value, scope);
    expect(access.isValid, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(BoxReset.appliedKey), isNull);
  });

  test('PIN réussi après le DELETE réel ne rouvre jamais l’accès', () async {
    final id = await source('late-pin');
    final entered = Completer<void>();
    final release = Completer<void>();
    final pending = authenticateAdultAccess(
      reason: 'Fixture PIN tardif',
      confirmPin: () async {
        entered.complete();
        await release.future;
        return AppPinSettings.instance.verify('3718');
      },
    );
    await entered.future;
    await lists.deletePlaylist(id);
    release.complete();
    expect(await pending, isNull);
    expect(lists.currentChannels, isEmpty);
  });

  test('suppression tardive de A préserve le profil B réellement isolé',
      () async {
    final a = await source('profile-a');
    final b = await source('profile-b');
    profiles.resetForTesting(_catalog(a: a, b: b));
    await lists.initialize();
    final locked = Completer<void>();
    final release = Completer<void>();
    final blocker = db.transaction((txn) async {
      await txn.rawQuery('SELECT 1');
      locked.complete();
      await release.future;
    });
    await locked.future;
    final deletion = lists.deletePlaylist(a);
    await pumpEventQueue();
    await profiles.activate('b', leaveAllowed: true);
    final access = await grant();
    final scope = ActiveProfile.instance.scopeListenable.value;
    release.complete();
    await blocker;
    await deletion;

    expect(ActiveProfile.instance.id, 'b');
    expect(ActiveProfile.instance.scopeListenable.value, scope);
    expect(access.isValid, isTrue);
    expect(lists.currentChannels.single.playlistId, b);
    expect(profiles.profileById('a')!.playlistIds, <int>[a],
        reason:
            'les clés historiques ne sont pas réécrites par la suppression');
  });

  test('retrait panel réel ferme le grant et ne laisse aucune chaîne',
      () async {
    await source('panel');
    final access = await grant();

    final removed = await RemoteSourceRepository.applyRevocations(
        SourceFingerprint.ofM3uUrl('http://127.0.0.1/panel.m3u'));

    expect(removed, 1);
    expect(access.isValid, isFalse);
    expect(await db.query('playlists'), isEmpty);
    expect(lists.currentChannels, isEmpty);
  });

  test('reset panel réel révoque avant son marqueur de réussite', () async {
    await source('reset-a');
    await source('reset-b');
    final access = await grant();

    expect(await BoxReset.maybeApply(200, strict: true), isTrue);

    expect(access.isValid, isFalse);
    expect(await db.query('playlists'), isEmpty);
    expect(await db.query('channels'), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(BoxReset.appliedKey), 200);
  });

  test('reset d’une box déjà vide ferme aussi un accès ouvert', () async {
    final access = await grant();

    expect(await BoxReset.maybeApply(300, strict: true), isTrue);

    expect(access.isValid, isFalse);
    await lists.initialize();
    expect(lists.currentChannels, isEmpty);
  });
}
