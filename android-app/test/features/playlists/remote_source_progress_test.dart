import 'dart:async';
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
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';

// Vrai import et vrai SQLite, mais aucun service ni identifiant client.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    directory = await Directory.systemTemp.createTemp('zuno-progress-');
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${directory.path}/lists.db';
    PlaylistRepository.mergeAllPlaylists = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:11:22:33:44:55',
    });
    ImportProgressBus.clear();
    RemoteSourceRepository.lastResult.value = null;
    RepairFlags.syncPillOff = true;
  });

  tearDown(() async {
    RepairFlags.syncPillOff = false;
    ImportProgressBus.clear();
    await PlaylistDatabase.instance.closeForTesting();
    await directory.delete(recursive: true);
  });

  test('le canal expose la réception réelle même sans pastille de diagnostic', () async {
    final sourceRequested = Completer<void>();
    final playlistRequested = Completer<void>();
    final sourceResponse = Completer<http.Response>();
    final playlistResponse = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path.startsWith('/api/device-source/')) {
        sourceRequested.complete();
        return sourceResponse.future;
      }
      if (request.url.host == 'playlist.invalid') {
        playlistRequested.complete();
        return playlistResponse.future;
      }
      return http.Response('{}', 404);
    });
    addTearDown(client.close);
    ImportProgressBus.done(9999); // L'ancien catalogue ne doit pas réapparaître.
    final pending = http.runWithClient(
      () => RemoteSourceRepository.sync(force: true), () => client,
    );
    await sourceRequested.future;
    expect(RemoteSourceRepository.syncing.value, isTrue);
    expect(RemoteSourceRepository.importing.value, isFalse);
    expect(ImportProgressBus.current.value, isNull);
    sourceResponse.complete(http.Response(jsonEncode(<String, Object>{
      'sources': <Object>[
        <String, Object>{'type': 'm3u', 'm3u_url': 'http://playlist.invalid/list.m3u', 'origin': 'panel'},
      ],
    }), 200));
    await playlistRequested.future;
    expect(RemoteSourceRepository.importing.value, isTrue,
        reason: 'l’écran écoute les faits, pas la préférence de pastille');
    playlistResponse.complete(http.Response(
      '#EXTM3U\n#EXTINF:-1 tvg-id="fixture" group-title="Fixture",Fixture\n'
      'http://127.0.0.1/fixture.ts\n', 200,
    ));
    expect(await pending, RemoteSyncResult.loaded);
    expect(RemoteSourceRepository.syncing.value, isFalse);
    expect(RemoteSourceRepository.importing.value, isFalse);
    expect(RemoteSourceRepository.lastResult.value, RemoteSyncResult.loaded);
    expect(ImportProgressBus.current.value!.count, 1);
    expect(ImportProgressBus.current.value!.stage, ImportStage.done);
  });

  test('absence de liste puis panne terminent la recherche sans ancien compteur', () async {
    for (final status in <int>[200, 503]) {
      final client = MockClient((_) async => http.Response('{"sources":[]}', status));
      ImportProgressBus.done(800);
      final result = await http.runWithClient(
        () => RemoteSourceRepository.sync(force: true), () => client,
      );
      client.close();
      expect(result, status == 200 ? RemoteSyncResult.noSource : RemoteSyncResult.networkError);
      expect(RemoteSourceRepository.lastResult.value, result);
      expect(RemoteSourceRepository.syncing.value, isFalse);
      expect(RemoteSourceRepository.importing.value, isFalse);
      expect(ImportProgressBus.current.value, isNull);
    }
  });
}
