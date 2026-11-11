import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/novatube_private_features.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/channels/domain/channel.dart';
import 'package:tv_king/features/cinema/data/cinema_adult_signals.dart';
import 'package:tv_king/features/cinema/domain/cinema_models.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/domain/playlist.dart';
import 'package:tv_king/features/profiles/data/profile_repository.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/vod/data/download_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'SQLite conserve les flags neutres et les découvertes détaillées par source/profil',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final Directory directory =
        await Directory.systemTemp.createTemp('adult-signals-');
    PlaylistDatabase.debugFilePath = '${directory.path}/signals.db';
    PlaylistRepository.mergeAllPlaylists = true;
    FlavorConfig.setCurrent(FlavorConfig.novatube);
    final ProfileRepository profiles = ProfileRepository.instance;
    final PlaylistRepository sources = PlaylistRepository.instance;
    addTearDown(() async {
      await sources.reloadForActiveProfile();
      await PlaylistDatabase.instance.closeForTesting();
      PlaylistDatabase.debugFilePath = null;
      await directory.delete(recursive: true);
    });
    await profiles.load();
    final http.Client client = MockClient((_) async => http.Response('''#EXTM3U
#EXTINF:-1 tvg-id="normal" group-title="Divers" is_adult="0",Canal Jardin
https://example.invalid/normal.ts
#EXTINF:-1 tvg-id="marked" group-title="Divers" is_adult="true",Canal Soleil
https://example.invalid/marked.ts
''', 200));
    addTearDown(client.close);
    final Playlist source = await sources.addM3uPlaylist(
        name: 'Source personnelle',
        url: 'https://example.invalid/personal.m3u',
        httpClient: client);
    final Database db = await PlaylistDatabase.instance.database;
    final Map<String, Object?> persisted = (await db.query('channels',
            where: 'playlist_id = ? AND external_id = ?',
            whereArgs: <Object>[source.id!, 'marked']))
        .single;
    expect(persisted['declared_adult'], 1);
    expect(persisted['name'], 'Canal Soleil');
    expect(persisted['category'], 'Divers');
    await sources.reloadForActiveProfile();
    expect(sources.currentChannels.map((Channel c) => c.id), <String>[
      source.channelId('normal'),
      if (NovatubePrivateFeatures.adultCatalogs) source.channelId('marked'),
    ]);
    if (NovatubePrivateFeatures.adultCatalogs) {
      expect(sources.currentChannels.last.declaredAdult, isTrue);
      expect(sources.currentChannels.last.isAdult, isTrue);
    }

    final CinemaTitle neutral = CinemaTitle(
        id: 'p${source.id}:m:42',
        kind: CinemaKind.movie,
        sourceKey: 'p${source.id}',
        remoteId: '42',
        name: 'Titre neutre',
        categoryKey: 'divers',
        searchKey: 'titre neutre');
    await DownloadsRepository.instance.initialize();
    await db.insert(
        'downloads',
        Download(
                id: neutral.id,
                name: neutral.name,
                sourceUrl: 'https://example.invalid/old-copy.mp4',
                filePath: '/fixture.mp4',
                status: DownloadStatus.done,
                receivedBytes: 100,
                totalBytes: 100,
                createdAt: 1,
                category: neutral.categoryKey)
            .toMap());
    expect(
        await CinemaAdultSignals.remember(
            profileId: ProfileIds.origin,
            playlistId: source.id!,
            titleId: neutral.id),
        isTrue);
    final Download upgraded = Download.fromMap((await db.query('downloads',
            where: 'id = ?', whereArgs: <Object>[neutral.id]))
        .single);
    expect(upgraded.declaredAdult, isTrue);
    expect(upgraded.name, neutral.name);
    expect(upgraded.receivedBytes, 100);
    final Set<String> learned =
        await CinemaAdultSignals.read(ProfileIds.origin);
    final CinemaTitle protected = CinemaAdultSignals.apply(neutral, learned);
    expect(protected.declaredAdult, isTrue);
    expect((protected.id, protected.name, protected.categoryKey),
        (neutral.id, neutral.name, neutral.categoryKey));

    final FamilyProfile other =
        (await profiles.addProfile(name: 'Autre', isKids: false))!;
    await profiles.activate(other.id, leaveAllowed: true);
    expect(sources.currentChannels, isEmpty);
    expect(await CinemaAdultSignals.read(other.id), isEmpty);
    expect(
        await CinemaAdultSignals.remember(
            profileId: other.id, playlistId: source.id!, titleId: neutral.id),
        isFalse);
    await profiles.activate(ProfileIds.origin, leaveAllowed: true);
    expect(
        CinemaAdultSignals.apply(
                neutral, await CinemaAdultSignals.read(ProfileIds.origin))
            .isAdult,
        isTrue);
    await sources.deletePlaylist(source.id!);
    expect(await CinemaAdultSignals.read(ProfileIds.origin), isEmpty);
    expect(await db.query('cinema_adult_signals'), isEmpty);
  });
}
