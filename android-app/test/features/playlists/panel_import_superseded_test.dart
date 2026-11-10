import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/core/app/repair_flags.dart';
import 'package:tv_king/core/flavor/flavor.dart';
import 'package:tv_king/features/playlists/data/box_reset.dart';
import 'package:tv_king/features/playlists/data/deleted_sources.dart';
import 'package:tv_king/features/playlists/data/import_progress.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';
import 'package:tv_king/features/playlists/data/playlist_repository.dart';
import 'package:tv_king/features/playlists/data/remote_source_repository.dart';
import 'package:tv_king/features/playlists/domain/source_fingerprint.dart';

const _mac = 'MK:30:70:0E:D7:5B';

String _m3u(int count) {
  final body = StringBuffer('#EXTM3U\n');
  for (var i = 0; i < count; i++) {
    body.write('#EXTINF:-1 group-title="Test",Chaîne $i\n'
        'http://127.0.0.1/fixture/$i.ts\n');
  }
  return body.toString();
}

/// L'API du panel est une fixture ; les téléchargements passent par un
/// VRAI socket. close() n'achève aucun Completer artificiellement : il
/// ferme seulement l'IOClient employé par le code de production.
class _SocketHttpOverrides extends HttpOverrides {}

class _ObservedClient extends http.BaseClient {
  _ObservedClient(this.inner);
  final http.Client inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(request);

  @override
  void close() {
    closed = true;
    inner.close();
  }
}

class _PanelFixtureClient extends http.BaseClient {
  _PanelFixtureClient(this.source, {this.sourceServer});
  final Map<String, Object> Function() source;
  final String? sourceServer;
  final IOClient _transport =
      HttpOverrides.runWithHttpOverrides(IOClient.new, _SocketHttpOverrides());

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path.startsWith('/api/')) {
      final isSource = request.url.path.startsWith('/api/device-source/');
      if (isSource && sourceServer != null) {
        return _transport.send(http.Request(
            'GET', Uri.parse('$sourceServer/api/device-source/fixture'))
          ..headers.addAll(request.headers));
      }
      return Future.value(http.StreamedResponse(
        Stream.value(utf8.encode(isSource ? jsonEncode(source()) : '{}')),
        isSource ? 200 : 404,
      ));
    }
    return _transport.send(request);
  }

  @override
  void close() => _transport.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = PlaylistRepository.instance;
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
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device.virtual_mac.v1': _mac,
    });
    RepairFlags.debugReset();
    await db.delete('playlists');
    await db.delete('deleted_sources');
    await repo.initialize();
    RemoteSourceRepository.importing.value = false;
    RemoteSourceRepository.syncing.value = false;
    RemoteSourceRepository.manualImporting.value = false;
    RemoteSourceRepository.lastResult.value = null;
    RemoteSourceRepository.resetImportQueueForTesting();
    ImportProgressBus.clear();
  });

  tearDownAll(() async {
    RepairFlags.debugReset();
    await PlaylistDatabase.instance.closeForTesting();
  });

  test('reset pendant auth Xtream avant la ligne : réponse tardive annulée',
      () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var requests = 0;
    final client = _ObservedClient(MockClient((request) async {
      requests++;
      started.complete();
      await release.future;
      return http.Response(
          jsonEncode(<String, Object>{
            'user_info': <String, Object>{'auth': 1, 'status': 'Active'},
            'server_info': <String, Object>{},
          }),
          200);
    }));
    final stopped = expectLater(
        repo.addXtreamPlaylist(
          name: 'Ancien import',
          serverUrl: 'http://xtream.invalid',
          username: 'fixture',
          password: 'fixture',
          httpClient: client,
          restoreDeleted: false,
        ),
        throwsA(isA<PlaylistImportSuperseded>()));
    await started.future;
    expect(await db.query('playlists'), isEmpty);
    expect(await BoxReset.maybeApply(100, strict: true), isTrue);
    expect(client.closed, isFalse,
        reason: 'le client fourni reste à son propriétaire');
    release.complete();
    await stopped;
    expect(requests, 1, reason: 'aucune demande catégories après le reset');
    expect(await db.query('playlists'), isEmpty);
    expect(await db.query('channels'), isEmpty);
    expect(repo.currentChannels, isEmpty);
    expect(client.closed, isFalse);
  });

  test(
      'retrait immédiat : ancienne passe et seconde source annulées, manuel conservé',
      () async {
    const firstUrl = 'http://provider.invalid/first.m3u';
    const secondUrl = 'http://provider.invalid/second.m3u';
    await repo.addM3uPlaylist(
      name: 'Manuel à conserver',
      url: 'http://manual.invalid/keep.m3u',
      httpClient: MockClient((_) async => http.Response(_m3u(2), 200)),
    );
    final started = Completer<void>();
    final release = Completer<void>();
    var secondRequests = 0;
    var sourceRequests = 0;
    http.Client client() => MockClient((request) async {
          if (request.url.path.startsWith('/api/device-source/')) {
            sourceRequests++;
            return http.Response(
                jsonEncode(<String, Object>{
                  'sources': <Object>[
                    <String, String>{
                      'type': 'm3u',
                      'm3u_url': firstUrl,
                      'origin': 'panel'
                    },
                    <String, String>{
                      'type': 'm3u',
                      'm3u_url': secondUrl,
                      'origin': 'panel'
                    },
                  ],
                }),
                200);
          }
          if (request.url.toString() == firstUrl) {
            started.complete();
            await release.future;
            return http.Response(_m3u(3), 200);
          }
          if (request.url.toString() == secondUrl) {
            secondRequests++;
            return http.Response(_m3u(3), 200);
          }
          return http.Response('{}', 404);
        });
    final old = http.runWithClient(
        () => RemoteSourceRepository.sync(force: true), client);
    await started.future;
    final queued = http.runWithClient(
        () => RemoteSourceRepository.sync(force: true), client);
    expect(RemoteSourceRepository.importing.value, isTrue);
    RemoteSourceRepository.supersedePendingPanelImports();
    expect(RemoteSourceRepository.importing.value, isFalse);
    expect(RemoteSourceRepository.syncing.value, isFalse);
    await RemoteSourceRepository.applyRevocations(
        SourceFingerprint.ofM3uUrl(firstUrl));
    expect((await repo.getAllPlaylists()).single.name, 'Manuel à conserver');
    expect(repo.currentChannels.length, 2);
    // La suppression est réellement finie alors que le transport est bloqué.
    expect(release.isCompleted, isFalse);
    release.complete();
    expect(await old, RemoteSyncResult.superseded);
    expect(await queued, RemoteSyncResult.superseded);
    expect(sourceRequests, 1,
        reason: 'la passe déjà en file est aussi périmée');
    expect(secondRequests, 0);
    expect((await repo.getAllPlaylists()).single.name, 'Manuel à conserver');
    expect(repo.currentChannels.length, 2);
  });

  test(
      'reset après premier lot : aucun lot tardif ne revient dans SQLite ou le cache',
      () async {
    final firstBatch = Completer<void>();
    final sizes = <int>[];
    final subscription = repo.channelsStream.listen((channels) {
      sizes.add(channels.length);
      if (channels.length == 1000 && !firstBatch.isCompleted) {
        // Même invalidation synchrone que le reset, avant les DELETE.
        RemoteSourceRepository.supersedePendingPanelImports(resetAll: true);
        firstBatch.complete();
      }
    });
    final stopped = expectLater(
        repo.addM3uPlaylist(
          name: 'Grand lot',
          url: 'http://provider.invalid/batches.m3u',
          httpClient: MockClient((_) async => http.Response(_m3u(3500), 200)),
        ),
        throwsA(isA<PlaylistImportSuperseded>()));
    await firstBatch.future;
    expect(repo.currentChannels, isEmpty);
    await BoxReset.maybeApply(200, strict: true);
    await stopped;
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    expect(await db.query('playlists'), isEmpty);
    expect(await db.query('channels'), isEmpty);
    expect(repo.currentChannels, isEmpty);
    expect(sizes.where((size) => size > 1000), isEmpty);
    expect(sizes.last, 0);
  });

  test(
      'retrait partiel conserve le manuel ; reset annule le manuel en cours et en file',
      () async {
    final started = Completer<void>();
    final release = Completer<int>();
    final inFlight = RemoteSourceRepository.runUserImport(() {
      started.complete();
      return release.future;
    });
    final stopped =
        expectLater(inFlight, throwsA(isA<PlaylistImportSuperseded>()));
    await started.future;
    var queuedRan = false;
    final queued = RemoteSourceRepository.runUserImport(() async {
      queuedRan = true;
      return 2;
    });
    final queuedStopped =
        expectLater(queued, throwsA(isA<PlaylistImportSuperseded>()));
    RemoteSourceRepository.supersedePendingPanelImports();
    expect(RemoteSourceRepository.manualImporting.value, isTrue);
    await BoxReset.maybeApply(250, strict: true);
    expect(RemoteSourceRepository.manualImporting.value, isFalse);
    release.complete(1);
    await Future.wait(<Future<void>>[stopped, queuedStopped]);
    expect(queuedRan, isFalse);
    expect(await RemoteSourceRepository.runUserImport(() async => 3), 3);
    expect(RemoteSourceRepository.manualImporting.value, isFalse);
  });

  for (final phase in <String>[
    'device-source',
    'xtream-auth',
    'm3u-headers',
    'm3u-body',
    'manual-xtream-auth',
    'manual-m3u-headers',
    'manual-m3u-batch',
  ]) {
    test(
        'socket $phase bloqué : retrait ferme le HTTP et nouvelle source démarre en moins de 1 s',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = 'http://127.0.0.1:${server.port}';
      final oldStarted = Completer<void>();
      final newStarted = Completer<void>();
      final releaseOldServer = Completer<void>();
      final isManual = phase.startsWith('manual-');
      final isXtream = phase.endsWith('xtream-auth');
      var useNewSource = false;
      server.listen((request) async {
        if (request.uri.path == '/new.m3u') {
          if (!newStarted.isCompleted) newStarted.complete();
          request.response.write(_m3u(2));
          await request.response.close();
          return;
        }
        if (phase == 'm3u-body') {
          request.response.write('#EXTM3U\n');
          await request.response.flush();
        }
        if (!oldStarted.isCompleted) oldStarted.complete();
        await releaseOldServer.future;
        try {
          request.response.write(isXtream
              ? '{"user_info":{"auth":1,"status":"Active"}}'
              : _m3u(3));
          await request.response.close();
        } catch (_) {
          // Le client a réellement fermé le socket pendant l'attente.
        }
      });
      final oldSource = isXtream
          ? <String, String>{
              'type': 'xtream',
              'server_url': base,
              'username': 'fixture',
              'password': 'fixture',
              'origin': 'panel'
            }
          : <String, String>{
              'type': 'm3u',
              'm3u_url': '$base/old.m3u',
              'origin': 'panel'
            };
      http.Client client() => _PanelFixtureClient(
          () => <String, Object>{
                'sources': <Object>[
                  useNewSource
                      ? <String, String>{
                          'type': 'm3u',
                          'm3u_url': '$base/new.m3u',
                          'origin': 'panel'
                        }
                      : oldSource,
                ],
              },
          sourceServer:
              phase == 'device-source' && !useNewSource ? base : null);
      try {
        final Future<Object?> old = http.runWithClient(() {
          if (isManual) {
            if (phase == 'manual-m3u-batch') {
              return RemoteSourceRepository.runUserImport(
                  () => repo.addM3uPlaylistsBatch(entries: [
                        (name: 'Ancienne première', url: '$base/old.m3u'),
                        (
                          name: 'Ancienne seconde',
                          url: '$base/must-not-load.m3u'
                        ),
                      ]));
            }
            return RemoteSourceRepository.runUserImport(() => isXtream
                ? repo.addXtreamPlaylist(
                    name: 'Manuel',
                    serverUrl: base,
                    username: 'fixture',
                    password: 'fixture')
                : repo.addM3uPlaylist(name: 'Manuel', url: '$base/old.m3u'));
          }
          return RemoteSourceRepository.sync(force: true);
        }, client);
        final Future<void>? manualStopped = isManual
            ? expectLater(old, throwsA(isA<PlaylistImportSuperseded>()))
            : null;
        await oldStarted.future.timeout(const Duration(seconds: 2));
        expect(
            RemoteSourceRepository.supersedeRevokedPanelImport(
                <String>['m3u|http://unrelated.invalid/stale.m3u']),
            isFalse);
        expect(RemoteSourceRepository.importing.value,
            !isManual && phase != 'device-source');
        expect(RemoteSourceRepository.manualImporting.value, isManual);
        final revoked = SourceFingerprint.allFromMap(oldSource);
        final elapsed = Stopwatch()..start();
        if (phase == 'device-source' || isManual) {
          expect(await BoxReset.maybeApply(275, strict: true), isTrue);
        } else {
          expect(RemoteSourceRepository.supersedeRevokedPanelImport(revoked),
              isTrue);
          await RemoteSourceRepository.applyRevocations(revoked);
        }
        useNewSource = true;
        final fresh = http.runWithClient(
            () => RemoteSourceRepository.sync(force: true), client);
        await newStarted.future.timeout(const Duration(seconds: 1));
        expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
        expect(releaseOldServer.isCompleted, isFalse,
            reason: 'la nouvelle source ne dépend plus de la réponse ancienne');
        if (isManual) {
          await manualStopped;
        } else {
          expect(await old, RemoteSyncResult.superseded);
        }
        expect(await fresh, RemoteSyncResult.loaded);
        expect((await repo.getAllPlaylists()).single.m3uUrl, '$base/new.m3u');
        expect(repo.currentChannels.length, 2);
      } finally {
        releaseOldServer.complete();
        await server.close(force: true);
      }
    });
  }

  test(
      'ancien ajout manuel annulé au milieu de la restauration : refus durables conservés',
      () async {
    const fingerprints = <String>[
      'm3u|http://first.invalid/list.m3u',
      'm3u|http://second.invalid/list.m3u',
    ];
    await DeletedSources.remember(fingerprints);
    final before = await DeletedSources.read();
    var checks = 0;
    await expectLater(
        DeletedSources.restoreManually(fingerprints, checkCurrent: () {
          // Entrée, début de transaction, première suppression, puis annulation
          // avant la seconde : le premier DELETE doit être annulé lui aussi.
          if (++checks == 4) throw const PlaylistImportSuperseded();
        }),
        throwsA(isA<PlaylistImportSuperseded>()));
    expect(await DeletedSources.read(), before);
    expect(before, hasLength(2));
  });

  test('activation annulée dans la transaction : autre liste reste active',
      () async {
    final first = await repo.addM3uPlaylist(
        name: 'A',
        url: 'http://active.invalid/a.m3u',
        httpClient: MockClient((_) async => http.Response(_m3u(1), 200)));
    final second = await repo.addM3uPlaylist(
        name: 'B',
        url: 'http://active.invalid/b.m3u',
        httpClient: MockClient((_) async => http.Response(_m3u(1), 200)));
    var checks = 0;
    await expectLater(
        repo.setActivePlaylist(first.id!, checkCurrent: () {
          if (++checks == 4) throw const PlaylistImportSuperseded();
        }),
        throwsA(isA<PlaylistImportSuperseded>()));
    final active =
        await db.query('playlists', columns: ['id'], where: 'is_active = 1');
    expect(active, [
      <String, Object?>{'id': second.id}
    ]);
  });

  test(
      'reset SQL en échec : aucun marqueur prématuré, nouvelle tentative unique',
      () async {
    await repo.addM3uPlaylist(
      name: 'Liste',
      url: 'http://provider.invalid/reset-failure.m3u',
      httpClient: MockClient((_) async => http.Response(_m3u(2), 200)),
    );
    await db.execute("CREATE TRIGGER fail_reset BEFORE DELETE ON playlists "
        "BEGIN SELECT RAISE(ABORT, 'fixture reset failure'); END");
    final prefs = await SharedPreferences.getInstance();
    try {
      expect(await BoxReset.maybeApply(300), isFalse);
      expect(prefs.getInt(BoxReset.appliedKey), isNull);
      await expectLater(
          BoxReset.maybeApply(300, strict: true), throwsA(anything));
      expect(prefs.getInt(BoxReset.appliedKey), isNull);
      expect(await db.query('playlists'), hasLength(1));
    } finally {
      await db.execute('DROP TRIGGER fail_reset');
    }
    final outcomes = await Future.wait(<Future<bool>>[
      BoxReset.maybeApply(300, strict: true),
      BoxReset.maybeApply(300, strict: true),
    ]);
    expect(outcomes.where((applied) => applied), hasLength(1));
    expect(prefs.getInt(BoxReset.appliedKey), 300);
    expect(await db.query('playlists'), isEmpty);
    expect(await db.query('channels'), isEmpty);
    expect(repo.currentChannels, isEmpty);
  });
}
