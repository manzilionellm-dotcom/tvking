// Un guide reste en téléchargement après une remise à zéro. Les lots déjà
// écrits dans la table staging ne doivent pas ressusciter le guide effacé.
// Même chemin de publication vérifié avec et sans isolate, sur vrai SQLite.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';

String _stamp(DateTime value) {
  final DateTime utc = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)} +0000';
}

String _programs(String prefix, int count) {
  final DateTime start = DateTime.now().toUtc();
  final DateTime stop = start.add(const Duration(hours: 1));
  return List<String>.generate(
          count,
          (int i) => '<programme channel="fixture" start="${_stamp(start)}" '
              'stop="${_stamp(stop)}"><title>$prefix $i</title></programme>')
      .join();
}

Future<void> _waitForStagedRows(Database db) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name = 'epg_import_stage'",
    );
    if (tables.isNotEmpty) {
      final rows =
          await db.rawQuery('SELECT COUNT(*) AS n FROM epg_import_stage');
      if ((rows.single['n'] as int) >= 500) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Le premier lot EPG doit être écrit avant de déclencher le reset.');
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.bytes);
  final Stream<List<int>> Function(String path) bytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(bytes(request.url.path), 200);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('zuno-epg-reset-');
    PlaylistDatabase.debugFilePath = '${directory.path}/tv_king.db';
  });

  tearDownAll(() async {
    await PlaylistDatabase.instance.closeForTesting();
    PlaylistDatabase.debugFilePath = null;
    await directory.delete(recursive: true);
  });

  for (final bool isolate in <bool>[false, true]) {
    test('reset pendant staging : aucun ancien guide publié (isolate=$isolate)',
        () async {
      final EpgRepository repo = EpgRepository.instance;
      await repo.clearAll();
      final Database db = await PlaylistDatabase.instance.database;
      final HttpServer server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final Completer<void> releaseDownload = Completer<void>();
      final Completer<void> slowRequest = Completer<void>();
      Stream<List<int>> bytes(String path) async* {
        if (path == '/old.xml') {
          yield utf8.encode('<tv>${_programs('Ancien', 600)}');
          slowRequest.complete();
          await releaseDownload.future;
          yield utf8.encode('</tv>');
        } else {
          yield utf8.encode('<tv>${_programs('Valide', 2)}</tv>');
        }
      }

      final http.Client? client = isolate ? null : _StreamingClient(bytes);
      server.listen((HttpRequest request) async {
        request.response.headers.contentType =
            ContentType('application', 'xml');
        await for (final List<int> chunk in bytes(request.uri.path)) {
          request.response.add(chunk);
          await request.response.flush();
        }
        await request.response.close();
      });
      addTearDown(() async {
        if (!releaseDownload.isCompleted) releaseDownload.complete();
        client?.close();
        await server.close(force: true);
      });
      String url(String path) => 'http://127.0.0.1:${server.port}/$path';

      expect(
          await repo.downloadAndImport(
              url: url('initial.xml'), inIsolate: isolate, httpClient: client),
          2);
      int notifications = 0;
      final subscription = repo.changes.listen((_) {
        notifications++;
      });
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      notifications = 0;

      final Future<int> oldImport = repo.downloadAndImport(
        url: url('old.xml'),
        inIsolate: isolate,
        httpClient: client,
        idleTimeout: const Duration(seconds: 10),
      );
      await slowRequest.future.timeout(const Duration(seconds: 5));
      await _waitForStagedRows(db);
      expect(await repo.totalCount(), 2,
          reason: 'le guide complet reste visible pendant le téléchargement');
      expect(repo.isSyncing, isTrue);

      // C'est exactement l'opération EPG appelée par BoxReset.wipe.
      await repo.clearAll();
      await pumpEventQueue();
      expect(await repo.totalCount(), 0);
      expect(notifications, 1,
          reason: 'le reset annonce immédiatement le vide');
      releaseDownload.complete();
      expect(await oldImport, 0, reason: 'le lot périmé n’est pas un succès');
      await pumpEventQueue();
      expect(await repo.totalCount(), 0);
      expect(notifications, 1,
          reason: 'aucune notification de succès après annulation');
      expect(repo.isSyncing, isFalse);
      expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE name = 'epg_import_stage'",
          ),
          isEmpty,
          reason: 'le staging périmé est nettoyé');

      expect(
          await repo.downloadAndImport(
              url: url('fresh.xml'), inIsolate: isolate, httpClient: client),
          2);
      await pumpEventQueue();
      expect(await repo.totalCount(), 2);
      expect(notifications, 2);
      final rows = await db.query('epg_programs');
      expect(rows.every((row) => (row['title'] as String).startsWith('Valide')),
          isTrue);
      expect(repo.isSyncing, isFalse);
    });
  }
}
