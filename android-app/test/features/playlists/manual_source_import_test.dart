import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';

// Les portes ci-dessous imposent l'ordre des imports sans minuterie réseau.
// Seule la synchro finale utilise SQLite ; tous ses échanges HTTP sont simulés.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late bool previousMergeAllPlaylists;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    FlavorConfig.setCurrent(FlavorConfig.sevenMotion);
    directory = await Directory.systemTemp.createTemp('zuno-manual-import-');
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = '${directory.path}/lists.db';
    previousMergeAllPlaylists = PlaylistRepository.mergeAllPlaylists;
    PlaylistRepository.mergeAllPlaylists = true;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': 'MK:11:22:33:44:55',
    });
    ImportProgressBus.clear();
    RemoteSourceRepository.lastResult.value = null;
    expect(RemoteSourceRepository.manualImporting.value, isFalse);
    expect(RemoteSourceRepository.syncing.value, isFalse);
  });

  tearDown(() async {
    ImportProgressBus.clear();
    PlaylistRepository.mergeAllPlaylists = previousMergeAllPlaylists;
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await directory.delete(recursive: true);
  });

  test('le succès rend sa valeur et nettoie la progression avant la fin', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    ImportProgress? progressAtStart;
    bool? activeAtStart;
    ImportProgressBus.done(9999);

    final pending = RemoteSourceRepository.runUserImport<int>(() async {
      progressAtStart = ImportProgressBus.current.value;
      activeAtStart = RemoteSourceRepository.manualImporting.value;
      ImportProgressBus.saving(3, 8);
      started.complete();
      await release.future;
      ImportProgressBus.done(8);
      return 8;
    });

    try {
      await started.future;
      expect(progressAtStart, isNull,
          reason: 'le compteur précédent disparaît avant le nouvel import');
      expect(activeAtStart, isTrue);
      expect(RemoteSourceRepository.manualImporting.value, isTrue);
      expect(ImportProgressBus.current.value!.stage, ImportStage.saving);
      release.complete();
      expect(await pending, 8);
      expect(ImportProgressBus.current.value, isNull);
      expect(RemoteSourceRepository.manualImporting.value, isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      await pending;
    }
  });

  for (final asynchronous in <bool>[false, true]) {
    test('une erreur ${asynchronous ? 'asynchrone' : 'synchrone'} '
        'nettoie le bus et libère l’import suivant', () async {
      final failure = StateError('échec de fixture');
      final transitions = <bool>[];
      final progressWhenStopped = <ImportProgress?>[];
      void onManualState() {
        final active = RemoteSourceRepository.manualImporting.value;
        transitions.add(active);
        if (!active) progressWhenStopped.add(ImportProgressBus.current.value);
      }
      RemoteSourceRepository.manualImporting.addListener(onManualState);
      addTearDown(() =>
          RemoteSourceRepository.manualImporting.removeListener(onManualState));

      final failed = RemoteSourceRepository.runUserImport<int>(() {
        ImportProgressBus.found(7);
        if (asynchronous) return Future<int>.error(failure);
        throw failure;
      });
      // Poser l'écouteur d'erreur avant que la file lance le travail.
      final observedFailure = expectLater(failed, throwsA(same(failure)));
      ImportProgress? progressAtNextStart;
      final next = RemoteSourceRepository.runUserImport<int>(() async {
        progressAtNextStart = ImportProgressBus.current.value;
        ImportProgressBus.done(2);
        return 2;
      });

      await observedFailure;
      expect(await next, 2);
      expect(progressAtNextStart, isNull);
      expect(transitions, <bool>[true, false, true, false]);
      expect(progressWhenStopped, <ImportProgress?>[null, null],
          reason: 'la fin est annoncée après le nettoyage du compteur');
      expect(RemoteSourceRepository.manualImporting.value, isFalse);
      expect(ImportProgressBus.current.value, isNull);
    });
  }

  test('deux imports manuels restent FIFO sans effacer le compteur du second',
      () async {
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final releaseSecond = Completer<void>();
    final order = <String>[];
    final transitions = <bool>[];
    final progressWhenStopped = <ImportProgress?>[];
    void onManualState() {
      final active = RemoteSourceRepository.manualImporting.value;
      transitions.add(active);
      if (!active) progressWhenStopped.add(ImportProgressBus.current.value);
    }
    RemoteSourceRepository.manualImporting.addListener(onManualState);
    addTearDown(() =>
        RemoteSourceRepository.manualImporting.removeListener(onManualState));

    final first = RemoteSourceRepository.runUserImport<String>(() async {
      order.add('premier début');
      ImportProgressBus.found(11);
      firstStarted.complete();
      await releaseFirst.future;
      order.add('premier fin');
      return 'premier';
    });
    final second = RemoteSourceRepository.runUserImport<String>(() async {
      order.add('second début');
      ImportProgressBus.found(22);
      secondStarted.complete();
      await releaseSecond.future;
      order.add('second fin');
      return 'second';
    });

    try {
      await firstStarted.future;
      // Laisser passer les callbacks déjà prêts : le second doit attendre.
      await Future<void>.delayed(Duration.zero);
      expect(secondStarted.isCompleted, isFalse);
      expect(order, <String>['premier début']);
      expect(ImportProgressBus.current.value!.count, 11);
      releaseFirst.complete();
      await secondStarted.future;
      expect(await first, 'premier');
      await Future<void>.delayed(Duration.zero);
      expect(order, <String>['premier début', 'premier fin', 'second début']);
      expect(transitions, <bool>[true, false, true]);
      expect(progressWhenStopped, <ImportProgress?>[null]);
      expect(RemoteSourceRepository.manualImporting.value, isTrue);
      expect(ImportProgressBus.current.value!.count, 22,
          reason: 'la fin du premier Future ne nettoie pas le second import');
      releaseSecond.complete();
      expect(await second, 'second');
      expect(order.last, 'second fin');
      expect(transitions, <bool>[true, false, true, false]);
      expect(progressWhenStopped, <ImportProgress?>[null, null]);
      expect(ImportProgressBus.current.value, isNull);
    } finally {
      if (!releaseFirst.isCompleted) releaseFirst.complete();
      if (!releaseSecond.isCompleted) releaseSecond.complete();
      await Future.wait(<Future<String>>[first, second]);
    }
  });

  test('la vraie synchro du panel attend la fin et le nettoyage de l’import manuel',
      () async {
    final manualStarted = Completer<void>();
    final releaseManual = Completer<void>();
    final sourceRequested = Completer<void>();
    final playlistRequested = Completer<void>();
    final sourceResponse = Completer<http.Response>();
    final playlistResponse = Completer<http.Response>();
    final requestPaths = <String>[];
    bool? manualActiveAtSourceRequest;
    ImportProgress? progressAtSourceRequest;
    final client = MockClient((request) async {
      requestPaths.add(request.url.path);
      if (request.url.path.startsWith('/api/device-source/')) {
        manualActiveAtSourceRequest = RemoteSourceRepository.manualImporting.value;
        progressAtSourceRequest = ImportProgressBus.current.value;
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

    final manual = RemoteSourceRepository.runUserImport<int>(() async {
      ImportProgressBus.found(321);
      manualStarted.complete();
      await releaseManual.future;
      return 321;
    });
    final remote = http.runWithClient(
      () => RemoteSourceRepository.sync(force: true), () => client,
    );

    try {
      await manualStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(requestPaths, isEmpty,
          reason: 'même la requête panel attend le travail manuel en cours');
      expect(RemoteSourceRepository.syncing.value, isFalse);
      expect(ImportProgressBus.current.value!.count, 321);
      releaseManual.complete();
      await sourceRequested.future;
      expect(await manual, 321);
      expect(manualActiveAtSourceRequest, isFalse);
      expect(progressAtSourceRequest, isNull);
      expect(RemoteSourceRepository.syncing.value, isTrue);

      sourceResponse.complete(http.Response(jsonEncode(<String, Object>{
        'sources': <Object>[
          <String, Object>{
            'type': 'm3u',
            'm3u_url': 'http://playlist.invalid/list.m3u',
            'origin': 'panel',
          },
        ],
      }), 200));
      await playlistRequested.future;
      expect(RemoteSourceRepository.importing.value, isTrue);
      expect(RemoteSourceRepository.manualImporting.value, isFalse);
      playlistResponse.complete(http.Response(
        '#EXTM3U\n#EXTINF:-1 tvg-id="fixture" group-title="Fixture",Fixture\n'
        'http://127.0.0.1/fixture.ts\n', 200,
      ));
      expect(await remote, RemoteSyncResult.loaded);
      expect(RemoteSourceRepository.syncing.value, isFalse);
      expect(RemoteSourceRepository.importing.value, isFalse);
      expect(ImportProgressBus.current.value!.stage, ImportStage.done);
      expect(ImportProgressBus.current.value!.count, 1,
          reason: 'la fin manuelle ne doit pas effacer le résultat du panel');
    } finally {
      if (!releaseManual.isCompleted) releaseManual.complete();
      if (!sourceResponse.isCompleted) {
        sourceResponse.complete(http.Response('{"sources":[]}', 200));
      }
      if (!playlistResponse.isCompleted) {
        playlistResponse.complete(http.Response('', 503));
      }
      await manual;
      await remote;
    }
  });
}
