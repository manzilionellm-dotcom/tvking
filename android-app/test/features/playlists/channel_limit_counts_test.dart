import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/app_platform.dart';
import 'package:tv_king/features/playlists/data/channel_limit_snapshot.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/profiles/data/active_profile.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';

import 'channel_limit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = PlaylistRepository.instance;
  setUpAll(ChannelLimitFixture.setUpAll);
  tearDownAll(ChannelLimitFixture.tearDownAll);
  setUp(() async {
    AppPlatform.isZuno = true;
    PlaylistRepository.mergeAllPlaylists = true;
    await ChannelLimitFixture.db.update('playlists', {'hidden': 0});
    for (final id in [2, 3]) {
      await ChannelLimitFixture.db.update(
        'channels',
        {'external_id': 'fixture-1-$id'},
        where: 'local_id = ?',
        whereArgs: [id],
      );
    }
    ProfileRepository.instance.resetForTesting(
      ChannelLimitFixture.catalog(ids: [1, 2, 3, 4]),
    );
    await repo.initialize();
  });

  test(
    'quatre sources : seuls 3 et 4 sont affectés, aucune donnée modifiée',
    () async {
      final before = await ChannelLimitFixture.fingerprint();
      final snapshot = repo.channelLimitSnapshot.value!;
      expect(snapshot.storedRows, 100000);
      expect(snapshot.loadedRows, 50000);
      expect(snapshot.loadedChannels, 50000);
      expect(snapshot.sources.map((source) => source.storedRows), [
        25000,
        25000,
        25000,
        25000,
      ]);
      expect(snapshot.sources.map((source) => source.loadedRows), [
        25000,
        25000,
        0,
        0,
      ]);
      expect(snapshot.affectedSources.map((source) => source.playlistId), [
        3,
        4,
      ]);
      expect(repo.currentChannels.first.id, 'fixture-1-1');
      expect(repo.currentChannels.last.id, 'fixture-2-25000');
      await repo.initialize();
      expect(await ChannelLimitFixture.fingerprint(), before);
    },
  );

  test(
    'exactement 50 000 lignes éligibles ne déclenchent pas la limite',
    () async {
      ActiveProfile.instance.set('p1', playlistIds: [1, 2]);
      ChannelReadCounts? counts;
      final channels = await repo.getAllChannels(
        onReadCounts: (value) => counts = value,
      );
      expect(channels, hasLength(50000));
      expect(counts!.storedRows, {1: 25000, 2: 25000});
      expect(counts!.loadedRows, counts!.storedRows);
      await repo.initialize();
      expect(repo.channelLimitSnapshot.value, isNull);
    },
  );

  test('source masquée exclue du COUNT et des détails', () async {
    await ChannelLimitFixture.db.update(
      'playlists',
      {'hidden': 1},
      where: 'id = ?',
      whereArgs: [3],
    );
    await repo.initialize();
    final snapshot = repo.channelLimitSnapshot.value!;
    expect(snapshot.storedRows, 75000);
    expect(snapshot.sources.map((source) => source.playlistId), [1, 2, 4]);
    expect(snapshot.affectedSources.map((source) => source.playlistId), [4]);
  });

  test(
    '50 000 lignes lues peuvent produire 49 999 objets après dédoublonnage',
    () async {
      await ChannelLimitFixture.db.update('channels', {
        'external_id': 'fixture-1-1',
      }, where: 'local_id IN (2, 3)');
      await repo.initialize();
      final snapshot = repo.channelLimitSnapshot.value!;
      expect(snapshot.storedRows, 100000);
      expect(snapshot.loadedRows, 50000);
      expect(snapshot.loadedChannels, 49999);
      expect(repo.currentChannels, hasLength(49999));
      expect(snapshot.affectedSources.map((source) => source.playlistId), [
        3,
        4,
      ]);
    },
  );

  test(
    'lecture devenue obsolète : ni résultat ni callback de compteurs',
    () async {
      var called = false;
      final pending = repo.getAllChannels(onReadCounts: (_) => called = true);
      ActiveProfile.instance.set('autre', playlistIds: [4]);
      expect(repo.channelLimitSnapshot.value, isNull);
      expect(await pending, isEmpty);
      expect(called, isFalse);
      await repo.initialize();
      expect(repo.currentChannels, hasLength(25000));
      expect(
        repo.currentChannels.every((channel) => channel.playlistId == 4),
        isTrue,
      );
      expect(repo.channelLimitSnapshot.value, isNull);
    },
  );

  test(
    '7 MOTION conserve son chemin sans nouveau snapshot ni callback',
    () async {
      AppPlatform.isZuno = false;
      var called = false;
      final channels = await repo.getAllChannels(
        onReadCounts: (_) => called = true,
      );
      expect(channels, hasLength(50000));
      expect(called, isFalse);
      await repo.initialize();
      expect(repo.channelLimitSnapshot.value, isNull);
    },
  );

  test(
    'mode source active : le comptage emploie exactement le même filtre',
    () async {
      PlaylistRepository.mergeAllPlaylists = false;
      ActiveProfile.instance.set('p1');
      ChannelReadCounts? counts;
      final channels = await repo.getAllChannels(
        onReadCounts: (value) => counts = value,
      );
      expect(channels, hasLength(25000));
      expect(counts!.storedRows, {1: 25000});
      expect(counts!.loadedRows, {1: 25000});
      await repo.initialize();
      expect(repo.channelLimitSnapshot.value, isNull);
    },
  );
}
