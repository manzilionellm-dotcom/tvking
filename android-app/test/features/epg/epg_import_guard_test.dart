// =========================================================
//  epg_import_guard_test.dart — import EPG borné et sans doublon
// =========================================================
//  Base SQLite réelle (sqflite_common_ffi), réseau simulé.
//    1. Un serveur qui ne répond jamais : l'import s'arrête (délai de
//       connexion), le verrou `isSyncing` est rendu, l'import suivant part.
//    2. Un serveur qui envoie un début puis se tait : délai de silence.
//    3. Deux imports du même guide ne doublent pas les programmes.
//  Avant l'audit : aucun délai (verrou tenu jusqu'au redémarrage), et
//  chaque ré-import ajoutait les mêmes lignes.
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tv_king/features/epg/data/epg_repository.dart';
import 'package:tv_king/features/playlists/data/playlist_database.dart';

String _stamp(DateTime t) {
  final DateTime u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
}

String _guide(DateTime now, int perChannel) {
  final StringBuffer b = StringBuffer('<?xml version="1.0"?><tv>');
  for (final String ch in <String>['tf1', 'f2', 'm6']) {
    for (int i = 0; i < perChannel; i++) {
      final DateTime s = now.add(Duration(hours: i + 1));
      final DateTime e = s.add(const Duration(hours: 1));
      b.write('<programme start="${_stamp(s)}" stop="${_stamp(e)}" channel="$ch">'
          '<title>$ch n°$i</title></programme>');
    }
  }
  b.write('</tv>');
  return b.toString();
}

/// Ne répond jamais aux en-têtes.
class _SilentClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

/// Envoie un début de fichier, puis plus rien (socket qui pend).
class _StallingClient extends http.BaseClient {
  final StreamController<List<int>> _ctrl = StreamController<List<int>>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _ctrl.add(utf8.encode('<?xml version="1.0"?><tv>'));
    return http.StreamedResponse(_ctrl.stream, 200);
  }

  @override
  void close() {
    _ctrl.close();
    super.close();
  }
}

/// Sert le même guide à chaque appel.
class _FixedClient extends http.BaseClient {
  _FixedClient(this.body);
  final String body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(body)),
        200,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('zuno-epg-');
    PlaylistDatabase.debugFilePath = '${dir.path}/tv_king.db';
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<int> count() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.rawQuery('SELECT COUNT(*) AS n FROM epg_programs');
    return (rows.first['n'] as int?) ?? 0;
  }

  test('un serveur muet ne garde pas le verrou : l\'import suivant part', () async {
    final EpgRepository repo = EpgRepository.instance;
    await expectLater(
      repo.downloadAndImport(
        url: 'http://epg.example.invalid/guide.xml',
        httpClient: _SilentClient(),
        connectTimeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(repo.isSyncing, isFalse, reason: 'le verrou doit être rendu');

    final DateTime now = DateTime.now();
    final int n = await repo.downloadAndImport(
      url: 'http://epg.example.invalid/guide.xml',
      httpClient: _FixedClient(_guide(now, 2)),
    );
    expect(n, 6, reason: 'après l\'échec, un vrai import doit marcher');
  });

  test('un flux qui se tait après le début est interrompu', () async {
    final EpgRepository repo = EpgRepository.instance;
    final _StallingClient client = _StallingClient();
    await expectLater(
      repo.downloadAndImport(
        url: 'http://epg.example.invalid/guide.xml',
        httpClient: client,
        idleTimeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(repo.isSyncing, isFalse);
    client.close();
  });

  test('ré-importer le même guide ne double pas les programmes', () async {
    final EpgRepository repo = EpgRepository.instance;
    await repo.clearAll();
    final DateTime now = DateTime.now();
    final String body = _guide(now, 4);
    expect(await repo.downloadAndImport(
      url: 'http://epg.example.invalid/guide.xml',
      httpClient: _FixedClient(body),
    ), 12);
    expect(await count(), 12);
    expect(await repo.downloadAndImport(
      url: 'http://epg.example.invalid/guide.xml',
      httpClient: _FixedClient(body),
    ), 12);
    expect(await count(), 12, reason: 'une chaîne ré-importée remplace son guide');
    // Une chaîne absente du nouveau fichier garde son ancien guide.
    final String partial = body.replaceAll(RegExp(r'<programme[^>]*channel="m6">.*?</programme>'), '');
    expect(await repo.downloadAndImport(
      url: 'http://epg.example.invalid/guide.xml',
      httpClient: _FixedClient(partial),
    ), 8);
    expect(await count(), 12);
  });
}
